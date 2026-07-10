# SocialPhoto Backend

This backend is a small Python 3 service for the HarmonyOS app. It uses only the
Python standard library:

- HTTP API: `http.server`
- Database: SQLite
- File storage: local `uploads/` directory

It matches the ArkTS client endpoints in `entry/src/main/ets/service/DistributedService.ets`.

## API

Base URL:

```text
http://39.106.70.214:3000/api
```

Endpoints:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `POST /api/images/upload`
- `POST /api/sync/upload`
- `POST /api/sync/download`
- `GET /api/health`
- `GET /uploads/<file>`

All API responses use the same shape:

```json
{
  "success": true,
  "message": "",
  "data": {}
}
```

## Run On Server

Copy the `backend/` directory to the server, then run:

```bash
cd /home/admin/social-photo-backend
mkdir -p data uploads
HOST=0.0.0.0 \
PORT=3000 \
PUBLIC_BASE_URL=http://39.106.70.214:3000 \
python3 server.py
```

Check health:

```bash
curl http://127.0.0.1:3000/api/health
curl http://39.106.70.214:3000/api/health
```

The server stores:

- SQLite database: `data/social_photo.db`
- Uploaded images: `uploads/`

## Alibaba Cloud Settings

Open inbound TCP port `3000` in the ECS security group. If the OS firewall is
enabled, allow the port too:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

## systemd Example

Create `/etc/systemd/system/social-photo-backend.service`:

```ini
[Unit]
Description=SocialPhoto Backend
After=network.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/social-photo-backend
Environment=HOST=0.0.0.0
Environment=PORT=3000
Environment=PUBLIC_BASE_URL=http://39.106.70.214:3000
ExecStart=/usr/bin/python3 /home/admin/social-photo-backend/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now social-photo-backend
sudo systemctl status social-photo-backend
```

## Sync Contract

The app uploads local AI classification results with each post:

- `imagePaths`: public image URL list
- `categoryId`: such as `cat_food`
- `categoryName`: such as `美食`

The backend stores these fields and returns them from `/api/sync/download`, so
other devices can refresh local SQLite and show images in the category page.
