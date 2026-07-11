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
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn
from urllib.parse import unquote, urlparse


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("DATA_DIR", str(BASE_DIR / "data")))
UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR", str(BASE_DIR / "uploads")))
DB_PATH = Path(os.environ.get("DB_PATH", str(DATA_DIR / "social_photo.db")))
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "3000"))
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", str(50 * 1024 * 1024)))
TOKEN_TTL_MS = int(os.environ.get("TOKEN_TTL_MS", str(30 * 24 * 60 * 60 * 1000)))
PASSWORD_ITERATIONS = 160000


def now_ms():
    return int(time.time() * 1000)


def connect_db():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
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

            CREATE TABLE IF NOT EXISTS images (
              id TEXT PRIMARY KEY,
              owner_user_id TEXT NOT NULL,
              file_name TEXT NOT NULL,
              file_type TEXT NOT NULL,
              size INTEGER NOT NULL,
              url TEXT NOT NULL,
              created_at INTEGER NOT NULL
            );

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
              PRIMARY KEY(owner_user_id, post_id)
            );
            CREATE INDEX IF NOT EXISTS idx_posts_owner_updated
              ON posts(owner_user_id, server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_posts_owner_category
              ON posts(owner_user_id, category_id);
            CREATE INDEX IF NOT EXISTS idx_posts_global_updated
              ON posts(server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_posts_global_post_updated
              ON posts(post_id, server_updated_at);

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
              PRIMARY KEY(owner_user_id, comment_id)
            );
            CREATE INDEX IF NOT EXISTS idx_comments_owner_updated
              ON comments(owner_user_id, server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_comments_owner_post
              ON comments(owner_user_id, post_id);
            CREATE INDEX IF NOT EXISTS idx_comments_global_updated
              ON comments(server_updated_at);
            CREATE INDEX IF NOT EXISTS idx_comments_global_comment_updated
              ON comments(comment_id, server_updated_at);
            """
        )


def hash_password(password):
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        PASSWORD_ITERATIONS,
    ).hex()
    return "pbkdf2_sha256${}${}${}".format(PASSWORD_ITERATIONS, salt, digest)


def verify_password(password, encoded):
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


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def text(value, default=""):
    if value is None:
        return default
    return str(value)


def integer(value, default=0):
    try:
        if value is None or value == "":
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


def bool_int(value):
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return 1 if value else 0
    if isinstance(value, str):
        return 1 if value.lower() in ("1", "true", "yes") else 0
    return 0


def image_paths_json(value):
    if isinstance(value, list):
        return json.dumps([text(item) for item in value], ensure_ascii=False)
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return json.dumps([text(item) for item in parsed], ensure_ascii=False)
        except Exception:
            pass
        return json.dumps([value], ensure_ascii=False) if value else "[]"
    return "[]"


def row_to_post(row):
    try:
        paths = json.loads(row["image_paths"])
        if not isinstance(paths, list):
            paths = []
    except Exception:
        paths = []
    return {
        "postId": row["post_id"],
        "userId": row["user_id"] or "",
        "userName": row["user_name"] or "",
        "userAvatar": row["user_avatar"] or "",
        "content": row["content"] or "",
        "imagePaths": paths,
        "categoryId": row["category_id"] or "cat_other",
        "categoryName": row["category_name"] or "其他",
        "likeCount": row["like_count"] or 0,
        "commentCount": row["comment_count"] or 0,
        "createTime": row["create_time"] or 0,
        "updateTime": row["update_time"] or 0,
        "deviceId": row["device_id"] or "",
        "isDeleted": bool(row["is_deleted"]),
    }


def row_to_comment(row):
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


class Handler(BaseHTTPRequestHandler):
    server_version = "SocialPhotoBackend/1.0"

    def log_message(self, fmt, *args):
        print("[{}] {} {}".format(self.log_date_time_string(), self.address_string(), fmt % args))

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/health", "/api/health"):
            self.send_api(True, "ok", {"status": "ok", "time": now_ms()})
            return
        if path.startswith("/uploads/"):
            self.serve_upload(path)
            return
        self.send_api(False, "Not found", None, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            body = self.read_json()
        except ValueError as err:
            self.send_api(False, str(err), None)
            return
        routes = {
            "/api/auth/register": self.handle_register,
            "/api/auth/login": self.handle_login,
            "/api/auth/logout": self.handle_logout,
            "/api/images/upload": self.handle_image_upload,
            "/api/sync/upload": self.handle_sync_upload,
            "/api/sync/download": self.handle_sync_download,
        }
        route = routes.get(path)
        if route is None:
            self.send_api(False, "Unknown endpoint", None, 404)
            return
        try:
            route(body)
        except Exception as err:
            self.send_api(False, "Server error: {}".format(err), None, 500)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        if length > MAX_BODY_BYTES:
            raise ValueError("Request body is too large")
        raw = self.rfile.read(length)
        data = json.loads(raw.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("JSON body must be an object")
        return data

    def send_api(self, success, message, data, status=200):
        payload = {"success": success, "message": message, "data": data}
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def public_base_url(self):
        if PUBLIC_BASE_URL:
            return PUBLIC_BASE_URL
        return "http://{}".format(self.headers.get("Host", "127.0.0.1:{}".format(PORT))).rstrip("/")

    def serve_upload(self, path):
        name = unquote(path[len("/uploads/"):])
        if "/" in name or "\\" in name or not name:
            self.send_api(False, "Invalid file path", None, 400)
            return
        target = (UPLOAD_DIR / name).resolve()
        if not str(target).startswith(str(UPLOAD_DIR.resolve())) or not target.exists():
            self.send_api(False, "File not found", None, 404)
            return
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=31536000")
        self.end_headers()
        self.wfile.write(data)

    def create_session(self, conn, user_id, device_name):
        token = secrets.token_urlsafe(32)
        expires_at = now_ms() + TOKEN_TTL_MS
        conn.execute(
            "INSERT INTO sessions(token_hash, user_id, device_name, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
            (token_hash(token), user_id, device_name, now_ms(), expires_at),
        )
        return token, expires_at

    def auth_user(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            self.send_api(False, "Missing Authorization token", None)
            return None
        token = header[len("Bearer "):].strip()
        with connect_db() as conn:
            row = conn.execute(
                """
                SELECT users.* FROM sessions
                JOIN users ON users.id = sessions.user_id
                WHERE sessions.token_hash = ? AND sessions.expires_at > ?
                """,
                (token_hash(token), now_ms()),
            ).fetchone()
        if row is None:
            self.send_api(False, "Invalid or expired token", None)
            return None
        return row

    def handle_register(self, body):
        username = text(body.get("username")).strip()
        password = text(body.get("password"))
        device_name = text(body.get("deviceName"), "HarmonyOS device").strip()
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
                    "INSERT INTO users(id, username, password_hash, created_at, last_login_at) VALUES (?, ?, ?, ?, ?)",
                    (user_id, username, hash_password(password), now_ms(), now_ms()),
                )
                token, expires_at = self.create_session(conn, user_id, device_name)
            except sqlite3.IntegrityError:
                self.send_api(False, "Username already exists", None)
                return
        self.send_api(True, "", {"userId": user_id, "token": token, "expiresAt": expires_at})

    def handle_login(self, body):
        username = text(body.get("username")).strip()
        password = text(body.get("password"))
        device_name = text(body.get("deviceName"), "HarmonyOS device").strip()
        with connect_db() as conn:
            row = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
            if row is None or not verify_password(password, row["password_hash"]):
                self.send_api(False, "Invalid username or password", None)
                return
            conn.execute("UPDATE users SET last_login_at = ? WHERE id = ?", (now_ms(), row["id"]))
            token, expires_at = self.create_session(conn, row["id"], device_name)
        self.send_api(True, "", {"userId": row["id"], "token": token, "expiresAt": expires_at})

    def handle_logout(self, body):
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            token = header[len("Bearer "):].strip()
            with connect_db() as conn:
                conn.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash(token),))
        self.send_api(True, "", {})

    def handle_image_upload(self, body):
        user = self.auth_user()
        if user is None:
            return
        file_name = text(body.get("fileName"), "photo.jpg")
        file_type = text(body.get("fileType"), "image/jpeg")
        file_data = text(body.get("fileData"))
        if "," in file_data and file_data.lower().startswith("data:"):
            file_data = file_data.split(",", 1)[1]
        try:
            binary = base64.b64decode(file_data, validate=True)
        except Exception:
            self.send_api(False, "fileData must be valid base64", {"remoteUrls": []})
            return
        if not binary:
            self.send_api(False, "Uploaded file is empty", {"remoteUrls": []})
            return
        suffix = Path(file_name).suffix.lower()
        if suffix not in (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"):
            suffix = mimetypes.guess_extension(file_type) or ".jpg"
        stored = "{}_{}{}".format(now_ms(), uuid.uuid4().hex, suffix)
        (UPLOAD_DIR / stored).write_bytes(binary)
        url = "{}/uploads/{}".format(self.public_base_url(), stored)
        with connect_db() as conn:
            conn.execute(
                "INSERT INTO images(id, owner_user_id, file_name, file_type, size, url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (uuid.uuid4().hex, user["id"], stored, file_type, len(binary), url, now_ms()),
            )
        self.send_api(True, "", {"remoteUrls": [url]})

    def handle_sync_upload(self, body):
        user = self.auth_user()
        if user is None:
            return
        posts = body.get("posts", [])
        comments = body.get("comments", [])
        accepted_posts = []
        accepted_comments = []
        with connect_db() as conn:
            for post in posts if isinstance(posts, list) else []:
                if isinstance(post, dict):
                    post_id = self.upsert_post(conn, user["id"], post)
                    if post_id:
                        accepted_posts.append(post_id)
            for comment in comments if isinstance(comments, list) else []:
                if isinstance(comment, dict):
                    comment_id = self.upsert_comment(conn, user["id"], comment)
                    if comment_id:
                        accepted_comments.append(comment_id)
        self.send_api(True, "", {"acceptedPostIds": accepted_posts, "acceptedCommentIds": accepted_comments})

    def upsert_post(self, conn, owner, post):
        post_id = text(post.get("postId")).strip()
        if not post_id:
            return ""
        update_time = integer(post.get("updateTime"), now_ms())
        existing = conn.execute(
            "SELECT update_time FROM posts WHERE owner_user_id = ? AND post_id = ?",
            (owner, post_id),
        ).fetchone()
        if existing is not None and integer(existing["update_time"]) > update_time:
            return post_id
        conn.execute(
            """
            INSERT INTO posts(
              owner_user_id, post_id, user_id, user_name, user_avatar, content, image_paths,
              category_id, category_name, like_count, comment_count, create_time, update_time,
              device_id, is_deleted, server_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_user_id, post_id) DO UPDATE SET
              user_id=excluded.user_id, user_name=excluded.user_name,
              user_avatar=excluded.user_avatar, content=excluded.content,
              image_paths=excluded.image_paths, category_id=excluded.category_id,
              category_name=excluded.category_name, like_count=excluded.like_count,
              comment_count=excluded.comment_count, create_time=excluded.create_time,
              update_time=excluded.update_time, device_id=excluded.device_id,
              is_deleted=excluded.is_deleted, server_updated_at=excluded.server_updated_at
            """,
            (
                owner,
                post_id,
                text(post.get("userId")),
                text(post.get("userName")),
                text(post.get("userAvatar")),
                text(post.get("content")),
                image_paths_json(post.get("imagePaths")),
                text(post.get("categoryId"), "cat_other"),
                text(post.get("categoryName"), "其他"),
                integer(post.get("likeCount")),
                integer(post.get("commentCount")),
                integer(post.get("createTime"), update_time),
                update_time,
                text(post.get("deviceId")),
                bool_int(post.get("isDeleted")),
                now_ms(),
            ),
        )
        return post_id

    def upsert_comment(self, conn, owner, comment):
        comment_id = text(comment.get("commentId")).strip()
        post_id = text(comment.get("postId")).strip()
        if not comment_id or not post_id:
            return ""
        create_time = integer(comment.get("createTime"), now_ms())
        conn.execute(
            """
            INSERT INTO comments(
              owner_user_id, comment_id, post_id, user_id, user_name, user_avatar, content,
              parent_id, reply_to_user_id, reply_to_user_name, level, like_count, create_time,
              device_id, is_deleted, server_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_user_id, comment_id) DO UPDATE SET
              post_id=excluded.post_id, user_id=excluded.user_id, user_name=excluded.user_name,
              user_avatar=excluded.user_avatar, content=excluded.content,
              parent_id=excluded.parent_id, reply_to_user_id=excluded.reply_to_user_id,
              reply_to_user_name=excluded.reply_to_user_name, level=excluded.level,
              like_count=excluded.like_count, create_time=excluded.create_time,
              device_id=excluded.device_id, is_deleted=excluded.is_deleted,
              server_updated_at=excluded.server_updated_at
            """,
            (
                owner,
                comment_id,
                post_id,
                text(comment.get("userId")),
                text(comment.get("userName")),
                text(comment.get("userAvatar")),
                text(comment.get("content")),
                text(comment.get("parentId")),
                text(comment.get("replyToUserId")),
                text(comment.get("replyToUserName")),
                integer(comment.get("level"), 1),
                integer(comment.get("likeCount")),
                create_time,
                text(comment.get("deviceId")),
                bool_int(comment.get("isDeleted")),
                now_ms(),
            ),
        )
        return comment_id

    def handle_sync_download(self, body):
        user = self.auth_user()
        if user is None:
            return
        last_sync = integer(body.get("lastSyncTimestamp"), 0)
        with connect_db() as conn:
            post_rows = conn.execute(
                """
                SELECT p.* FROM posts p
                WHERE p.server_updated_at > ?
                  AND NOT EXISTS (
                    SELECT 1 FROM posts newer
                    WHERE newer.post_id = p.post_id
                      AND (
                        newer.server_updated_at > p.server_updated_at
                        OR (
                          newer.server_updated_at = p.server_updated_at
                          AND newer.owner_user_id > p.owner_user_id
                        )
                      )
                  )
                ORDER BY p.server_updated_at ASC
                """,
                (last_sync,),
            ).fetchall()
            comment_rows = conn.execute(
                """
                SELECT c.* FROM comments c
                WHERE c.server_updated_at > ?
                  AND NOT EXISTS (
                    SELECT 1 FROM comments newer
                    WHERE newer.comment_id = c.comment_id
                      AND (
                        newer.server_updated_at > c.server_updated_at
                        OR (
                          newer.server_updated_at = c.server_updated_at
                          AND newer.owner_user_id > c.owner_user_id
                        )
                      )
                  )
                ORDER BY c.server_updated_at ASC
                """,
                (last_sync,),
            ).fetchall()
        latest = last_sync
        for row in list(post_rows) + list(comment_rows):
            latest = max(latest, integer(row["server_updated_at"]))
        self.send_api(
            True,
            "",
            {
                "posts": [row_to_post(row) for row in post_rows],
                "comments": [row_to_comment(row) for row in comment_rows],
                "lastSyncTimestamp": latest,
            },
        )


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    init_db()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("SocialPhoto backend listening on http://{}:{}".format(HOST, PORT))
    if PUBLIC_BASE_URL:
        print("Public base URL: {}".format(PUBLIC_BASE_URL))
    print("SQLite database: {}".format(DB_PATH))
    print("Upload directory: {}".format(UPLOAD_DIR))
    server.serve_forever()


if __name__ == "__main__":
    main()
