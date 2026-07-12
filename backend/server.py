#!/usr/bin/env python3
import base64
import hashlib
import hmac
import json
import mimetypes
import os
import secrets
import sqlite3
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import unquote, urlparse


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("DATA_DIR", BASE_DIR / "data"))
UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR", BASE_DIR / "uploads"))
DB_PATH = Path(os.environ.get("DB_PATH", DATA_DIR / "social_photo.db"))
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "3000"))
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", str(50 * 1024 * 1024)))
TOKEN_TTL_MS = int(os.environ.get("TOKEN_TTL_MS", str(30 * 24 * 60 * 60 * 1000)))
PASSWORD_ITERATIONS = 160_000


def now_ms() -> int:
    return int(time.time() * 1000)


def ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def connect_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db() -> None:
    ensure_dirs()
    with connect_db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
              id TEXT PRIMARY KEY,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              last_login_at INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS sessions (
              token_hash TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              device_name TEXT,
              created_at INTEGER NOT NULL,
              expires_at INTEGER NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);

            CREATE TABLE IF NOT EXISTS images (
              id TEXT PRIMARY KEY,
              owner_user_id TEXT NOT NULL,
              file_name TEXT NOT NULL,
              file_type TEXT NOT NULL,
              size INTEGER NOT NULL,
              url TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_images_owner ON images(owner_user_id);

            CREATE TABLE IF NOT EXISTS posts (
              owner_user_id TEXT NOT NULL,
              post_id TEXT NOT NULL,
              user_id TEXT,
              user_name TEXT,
              user_avatar TEXT,
              content TEXT,
              image_paths TEXT NOT NULL DEFAULT '[]',
              category_id TEXT,
              category_name TEXT,
              like_count INTEGER DEFAULT 0,
              comment_count INTEGER DEFAULT 0,
              create_time INTEGER DEFAULT 0,
              update_time INTEGER DEFAULT 0,
              device_id TEXT,
              is_deleted INTEGER DEFAULT 0,
              server_updated_at INTEGER NOT NULL,
              PRIMARY KEY(owner_user_id, post_id),
              FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_posts_owner_updated ON posts(owner_user_id, server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_posts_owner_category ON posts(owner_user_id, category_id);

            CREATE TABLE IF NOT EXISTS comments (
              owner_user_id TEXT NOT NULL,
              comment_id TEXT NOT NULL,
              post_id TEXT NOT NULL,
              user_id TEXT,
              user_name TEXT,
              user_avatar TEXT,
              content TEXT,
              parent_id TEXT,
              reply_to_user_id TEXT,
              reply_to_user_name TEXT,
              level INTEGER DEFAULT 1,
              like_count INTEGER DEFAULT 0,
              create_time INTEGER DEFAULT 0,
              device_id TEXT,
              is_deleted INTEGER DEFAULT 0,
              server_updated_at INTEGER NOT NULL,
              PRIMARY KEY(owner_user_id, comment_id),
              FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_comments_owner_updated ON comments(owner_user_id, server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_comments_owner_post ON comments(owner_user_id, post_id);

            CREATE TABLE IF NOT EXISTS likes (
              user_id TEXT NOT NULL,
              post_id TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              PRIMARY KEY(user_id, post_id)
            );
            CREATE INDEX IF NOT EXISTS idx_likes_user ON likes(user_id);
            """
        )


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        PASSWORD_ITERATIONS,
    ).hex()
    return f"pbkdf2_sha256${PASSWORD_ITERATIONS}${salt}${digest}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, iterations_text, salt, expected = encoded.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt.encode("utf-8"),
            int(iterations_text),
        ).hex()
        return hmac.compare_digest(digest, expected)
    except Exception:
        return False


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def normalize_text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def normalize_int(value: Any, default: int = 0) -> int:
    try:
        if value is None or value == "":
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def normalize_bool(value: Any) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return 1 if value else 0
    if isinstance(value, str):
        return 1 if value.lower() in ("1", "true", "yes") else 0
    return 0


def normalize_image_paths(value: Any) -> str:
    if isinstance(value, list):
        return json.dumps([normalize_text(item) for item in value], ensure_ascii=False)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return json.dumps([normalize_text(item) for item in parsed], ensure_ascii=False)
        except json.JSONDecodeError:
            pass
        return json.dumps([value], ensure_ascii=False) if value else "[]"
    return "[]"


def row_to_post(row: sqlite3.Row) -> Dict[str, Any]:
    try:
        image_paths = json.loads(row["image_paths"])
        if not isinstance(image_paths, list):
            image_paths = []
    except json.JSONDecodeError:
        image_paths = []
    return {
        "postId": row["post_id"],
        "userId": row["user_id"] or "",
        "userName": row["user_name"] or "",
        "userAvatar": row["user_avatar"] or "",
        "content": row["content"] or "",
        "imagePaths": image_paths,
        "categoryId": row["category_id"] or "cat_other",
        "categoryName": row["category_name"] or "Other",
        "likeCount": row["like_count"] or 0,
        "commentCount": row["comment_count"] or 0,
        "createTime": row["create_time"] or 0,
        "updateTime": row["update_time"] or 0,
        "deviceId": row["device_id"] or "",
        "isDeleted": bool(row["is_deleted"]),
    }


def row_to_comment(row: sqlite3.Row) -> Dict[str, Any]:
    return {
        "commentId": row["comment_id"],
        "postId": row["post_id"],
        "userId": row["user_id"] or "",
        "userName": row["user_name"] or "",
        "userAvatar": row["user_avatar"] or "",
        "content": row["content"] or "",
        "parentId": row["parent_id"] or "",
        "replyToUserId": row["reply_to_user_id"] or "",
        "replyToUserName": row["reply_to_user_name"] or "",
        "level": row["level"] or 1,
        "likeCount": row["like_count"] or 0,
        "createTime": row["create_time"] or 0,
        "deviceId": row["device_id"] or "",
        "isDeleted": bool(row["is_deleted"]),
    }


class SocialPhotoHandler(BaseHTTPRequestHandler):
    server_version = "SocialPhotoBackend/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {self.address_string()} {fmt % args}")

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/health", "/api/health"):
            self.send_api(True, "ok", {"status": "ok", "time": now_ms()})
            return
        if path.startswith("/uploads/"):
            self.serve_upload(path)
            return
        self.send_error_json("Not found", HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            body = self.read_json_body()
        except ValueError as err:
            self.send_api(False, str(err), None)
            return

        routes = {
            "/api/auth/register": self.handle_register,
            "/api/auth/login": self.handle_login,
            "/api/auth/logout": self.handle_logout,
            "/api/images/upload": self.handle_image_upload,
            "/api/like": self.handle_like,
            "/api/unlike": self.handle_unlike,
            "/api/sync/upload": self.handle_sync_upload,
            "/api/sync/download": self.handle_sync_download,
            "/api/clear": self.handle_clear,
        }
        handler = routes.get(path)
        if handler is None:
            self.send_api(False, "Unknown endpoint", None)
            return
        try:
            handler(body)
        except Exception as err:
            self.send_api(False, f"Server error: {err}", None)

    def read_json_body(self) -> Dict[str, Any]:
        length_text = self.headers.get("Content-Length", "0")
        try:
            length = int(length_text)
        except ValueError as exc:
            raise ValueError("Invalid Content-Length") from exc
        if length <= 0:
            return {}
        if length > MAX_BODY_BYTES:
            raise ValueError("Request body is too large")
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError("Invalid JSON body") from exc
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload

    def send_api(self, success: bool, message: str, data: Any, status: int = 200) -> None:
        payload = {
            "success": success,
            "message": message,
            "data": data,
        }
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def send_error_json(self, message: str, status: int) -> None:
        self.send_api(False, message, None, status)

    def get_public_base_url(self) -> str:
        if PUBLIC_BASE_URL:
            return PUBLIC_BASE_URL
        host = self.headers.get("Host", f"127.0.0.1:{PORT}")
        return f"http://{host}".rstrip("/")

    def serve_upload(self, path: str) -> None:
        file_name = unquote(path[len("/uploads/") :])
        if "/" in file_name or "\\" in file_name or not file_name:
            self.send_error_json("Invalid file path", HTTPStatus.BAD_REQUEST)
            return
        target = (UPLOAD_DIR / file_name).resolve()
        if not str(target).startswith(str(UPLOAD_DIR.resolve())) or not target.exists():
            self.send_error_json("File not found", HTTPStatus.NOT_FOUND)
            return
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=31536000")
        self.end_headers()
        self.wfile.write(data)

    def create_session(self, conn: sqlite3.Connection, user_id: str, device_name: str) -> Tuple[str, int]:
        token = secrets.token_urlsafe(32)
        expires_at = now_ms() + TOKEN_TTL_MS
        conn.execute(
            """
            INSERT INTO sessions(token_hash, user_id, device_name, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (token_hash(token), user_id, device_name, now_ms(), expires_at),
        )
        return token, expires_at

    def authenticate(self) -> Optional[sqlite3.Row]:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            self.send_api(False, "Missing Authorization token", None)
            return None
        token = header[len("Bearer ") :].strip()
        if not token:
            self.send_api(False, "Missing Authorization token", None)
            return None
        with connect_db() as conn:
            row = conn.execute(
                """
                SELECT users.*
                FROM sessions
                JOIN users ON users.id = sessions.user_id
                WHERE sessions.token_hash = ? AND sessions.expires_at > ?
                """,
                (token_hash(token), now_ms()),
            ).fetchone()
        if row is None:
            self.send_api(False, "Invalid or expired token", None)
            return None
        return row

    def handle_register(self, body: Dict[str, Any]) -> None:
        username = normalize_text(body.get("username")).strip()
        password = normalize_text(body.get("password"))
        device_name = normalize_text(body.get("deviceName"), "HarmonyOS device").strip()
        if not username or not password:
            self.send_api(False, "Username and password are required", None)
            return
        if len(password) < 6:
            self.send_api(False, "Password must contain at least 6 characters", None)
            return

        user_id = uuid.uuid4().hex
        with connect_db() as conn:
            try:
                conn.execute(
                    """
                    INSERT INTO users(id, username, password_hash, created_at, last_login_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (user_id, username, hash_password(password), now_ms(), now_ms()),
                )
                token, expires_at = self.create_session(conn, user_id, device_name)
            except sqlite3.IntegrityError:
                self.send_api(False, "Username already exists", None)
                return
        self.send_api(True, "", {"userId": user_id, "token": token, "expiresAt": expires_at})

    def handle_login(self, body: Dict[str, Any]) -> None:
        username = normalize_text(body.get("username")).strip()
        password = normalize_text(body.get("password"))
        device_name = normalize_text(body.get("deviceName"), "HarmonyOS device").strip()
        if not username or not password:
            self.send_api(False, "Username and password are required", None)
            return
        with connect_db() as conn:
            row = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
            if row is None or not verify_password(password, row["password_hash"]):
                self.send_api(False, "Invalid username or password", None)
                return
            conn.execute("UPDATE users SET last_login_at = ? WHERE id = ?", (now_ms(), row["id"]))
            token, expires_at = self.create_session(conn, row["id"], device_name)
        self.send_api(True, "", {"userId": row["id"], "token": token, "expiresAt": expires_at})

    def handle_logout(self, body: Dict[str, Any]) -> None:
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            token = header[len("Bearer ") :].strip()
            with connect_db() as conn:
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash(token),))
        self.send_api(True, "", {})

    def handle_image_upload(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        file_name = normalize_text(body.get("fileName"), "photo.jpg")
        file_type = normalize_text(body.get("fileType"), "image/jpeg")
        file_data = normalize_text(body.get("fileData"))
        if "," in file_data and file_data.lower().startswith("data:"):
            file_data = file_data.split(",", 1)[1]
        if not file_data:
            self.send_api(False, "fileData is required", {"remoteUrls": []})
            return
        try:
            binary = base64.b64decode(file_data, validate=True)
        except Exception:
            self.send_api(False, "fileData must be valid base64", {"remoteUrls": []})
            return
        if not binary:
            self.send_api(False, "Uploaded file is empty", {"remoteUrls": []})
            return

        extension = self.choose_extension(file_name, file_type)
        stored_name = f"{now_ms()}_{uuid.uuid4().hex}{extension}"
        target = UPLOAD_DIR / stored_name
        target.write_bytes(binary)
        url = f"{self.get_public_base_url()}/uploads/{stored_name}"

        with connect_db() as conn:
            conn.execute(
                """
                INSERT INTO images(id, owner_user_id, file_name, file_type, size, url, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (uuid.uuid4().hex, user["id"], stored_name, file_type, len(binary), url, now_ms()),
            )
        self.send_api(True, "", {"remoteUrls": [url]})

    def choose_extension(self, file_name: str, file_type: str) -> str:
        suffix = Path(file_name).suffix.lower()
        allowed = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}
        if suffix in allowed:
            return suffix
        guessed = mimetypes.guess_extension(file_type) or ".jpg"
        return guessed if guessed in allowed else ".jpg"

    def handle_sync_upload(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        posts = body.get("posts", [])
        comments = body.get("comments", [])
        if not isinstance(posts, list) or not isinstance(comments, list):
            self.send_api(False, "posts and comments must be arrays", None)
            return

        accepted_post_ids: List[str] = []
        accepted_comment_ids: List[str] = []
        with connect_db() as conn:
            for item in posts:
                if isinstance(item, dict):
                    post_id = self.upsert_post(conn, user["id"], item)
                    if post_id:
                        accepted_post_ids.append(post_id)
            for item in comments:
                if isinstance(item, dict):
                    comment_id = self.upsert_comment(conn, user["id"], item)
                    if comment_id:
                        accepted_comment_ids.append(comment_id)
        self.send_api(
            True,
            "",
            {
                "acceptedPostIds": accepted_post_ids,
                "acceptedCommentIds": accepted_comment_ids,
            },
        )

    def upsert_post(self, conn: sqlite3.Connection, owner_user_id: str, post: Dict[str, Any]) -> str:
        post_id = normalize_text(post.get("postId")).strip()
        if not post_id:
            return ""
        incoming_update_time = normalize_int(post.get("updateTime"), now_ms())
        existing = conn.execute(
            "SELECT update_time FROM posts WHERE owner_user_id = ? AND post_id = ?",
            (owner_user_id, post_id),
        ).fetchone()
        if existing is not None and normalize_int(existing["update_time"]) > incoming_update_time:
            return post_id

        values = (
            owner_user_id,
            post_id,
            normalize_text(post.get("userId")),
            normalize_text(post.get("userName")),
            normalize_text(post.get("userAvatar")),
            normalize_text(post.get("content")),
            normalize_image_paths(post.get("imagePaths")),
            normalize_text(post.get("categoryId"), "cat_other"),
            normalize_text(post.get("categoryName"), "Other"),
            normalize_int(post.get("likeCount")),
            normalize_int(post.get("commentCount")),
            normalize_int(post.get("createTime"), incoming_update_time),
            incoming_update_time,
            normalize_text(post.get("deviceId")),
            normalize_bool(post.get("isDeleted")),
            now_ms(),
        )
        conn.execute(
            """
            INSERT INTO posts(
              owner_user_id, post_id, user_id, user_name, user_avatar, content,
              image_paths, category_id, category_name, like_count, comment_count,
              create_time, update_time, device_id, is_deleted, server_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_user_id, post_id) DO UPDATE SET
              user_id = excluded.user_id,
              user_name = excluded.user_name,
              user_avatar = excluded.user_avatar,
              content = excluded.content,
              image_paths = excluded.image_paths,
              category_id = excluded.category_id,
              category_name = excluded.category_name,
              like_count = excluded.like_count,
              comment_count = excluded.comment_count,
              create_time = excluded.create_time,
              update_time = excluded.update_time,
              device_id = excluded.device_id,
              is_deleted = excluded.is_deleted,
              server_updated_at = excluded.server_updated_at
            """,
            values,
        )
        return post_id

    def upsert_comment(self, conn: sqlite3.Connection, owner_user_id: str, comment: Dict[str, Any]) -> str:
        comment_id = normalize_text(comment.get("commentId")).strip()
        post_id = normalize_text(comment.get("postId")).strip()
        if not comment_id or not post_id:
            return ""
        incoming_create_time = normalize_int(comment.get("createTime"), now_ms())
        existing = conn.execute(
            "SELECT create_time FROM comments WHERE owner_user_id = ? AND comment_id = ?",
            (owner_user_id, comment_id),
        ).fetchone()
        if existing is not None and normalize_int(existing["create_time"]) > incoming_create_time:
            return comment_id

        values = (
            owner_user_id,
            comment_id,
            post_id,
            normalize_text(comment.get("userId")),
            normalize_text(comment.get("userName")),
            normalize_text(comment.get("userAvatar")),
            normalize_text(comment.get("content")),
            normalize_text(comment.get("parentId")),
            normalize_text(comment.get("replyToUserId")),
            normalize_text(comment.get("replyToUserName")),
            normalize_int(comment.get("level"), 1),
            normalize_int(comment.get("likeCount")),
            incoming_create_time,
            normalize_text(comment.get("deviceId")),
            normalize_bool(comment.get("isDeleted")),
            now_ms(),
        )
        conn.execute(
            """
            INSERT INTO comments(
              owner_user_id, comment_id, post_id, user_id, user_name, user_avatar,
              content, parent_id, reply_to_user_id, reply_to_user_name, level,
              like_count, create_time, device_id, is_deleted, server_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_user_id, comment_id) DO UPDATE SET
              post_id = excluded.post_id,
              user_id = excluded.user_id,
              user_name = excluded.user_name,
              user_avatar = excluded.user_avatar,
              content = excluded.content,
              parent_id = excluded.parent_id,
              reply_to_user_id = excluded.reply_to_user_id,
              reply_to_user_name = excluded.reply_to_user_name,
              level = excluded.level,
              like_count = excluded.like_count,
              create_time = excluded.create_time,
              device_id = excluded.device_id,
              is_deleted = excluded.is_deleted,
              server_updated_at = excluded.server_updated_at
            """,
            values,
        )
        return comment_id

    def handle_like(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        post_id = normalize_text(body.get("postId"))
        if not post_id:
            self.send_api(False, "postId is required", None)
            return
        with connect_db() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO likes(user_id, post_id, created_at) VALUES (?, ?, ?)",
                (user["id"], post_id, now_ms()),
            )
            conn.execute(
                "UPDATE posts SET like_count = (SELECT COUNT(*) FROM likes WHERE post_id = ?), server_updated_at = ? WHERE post_id = ?",
                (post_id, now_ms(), post_id),
            )
        self.send_api(True, "", {})

    def handle_unlike(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        post_id = normalize_text(body.get("postId"))
        if not post_id:
            self.send_api(False, "postId is required", None)
            return
        with connect_db() as conn:
            conn.execute(
                "DELETE FROM likes WHERE user_id = ? AND post_id = ?",
                (user["id"], post_id),
            )
            conn.execute(
                "UPDATE posts SET like_count = (SELECT COUNT(*) FROM likes WHERE post_id = ?), server_updated_at = ? WHERE post_id = ?",
                (post_id, now_ms(), post_id),
            )
        self.send_api(True, "", {})

    def handle_clear(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        with connect_db() as conn:
            conn.execute("DELETE FROM posts WHERE owner_user_id = ?", (user["id"],))
            conn.execute("DELETE FROM comments WHERE owner_user_id = ?", (user["id"],))
            conn.execute("DELETE FROM images WHERE owner_user_id = ?", (user["id"],))
            conn.execute("DELETE FROM likes WHERE user_id = ?", (user["id"],))
        self.send_api(True, "all data cleared", {})

    def handle_sync_download(self, body: Dict[str, Any]) -> None:
        user = self.authenticate()
        if user is None:
            return
        last_sync = normalize_int(body.get("lastSyncTimestamp"), 0)
        with connect_db() as conn:
            post_rows = conn.execute(
                """
                SELECT * FROM posts
                WHERE owner_user_id = ? AND server_updated_at > ?
                ORDER BY server_updated_at ASC
                """,
                (user["id"], last_sync),
            ).fetchall()
            comment_rows = conn.execute(
                """
                SELECT * FROM comments
                WHERE owner_user_id = ? AND server_updated_at > ?
                ORDER BY server_updated_at ASC
                """,
                (user["id"], last_sync),
            ).fetchall()
            like_rows = conn.execute(
                "SELECT post_id FROM likes WHERE user_id = ?",
                (user["id"],),
            ).fetchall()

        latest = last_sync
        for row in list(post_rows) + list(comment_rows):
            latest = max(latest, normalize_int(row["server_updated_at"]))
        self.send_api(
            True,
            "",
            {
                "posts": [row_to_post(row) for row in post_rows],
                "comments": [row_to_comment(row) for row in comment_rows],
                "likedPostIds": [row["post_id"] for row in like_rows],
                "lastSyncTimestamp": latest,
            },
        )


def main() -> None:
    init_db()
    server = ThreadingHTTPServer((HOST, PORT), SocialPhotoHandler)
    print(f"SocialPhoto backend listening on http://{HOST}:{PORT}")
    if PUBLIC_BASE_URL:
        print(f"Public base URL: {PUBLIC_BASE_URL}")
    print(f"SQLite database: {DB_PATH}")
    print(f"Upload directory: {UPLOAD_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
