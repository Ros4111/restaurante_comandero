# AGENTS.md

## Cursor Cloud specific instructions

### Architecture overview

This is a Restaurant TPV (Point-of-Sale) system with three components:
- **Flutter app** (root `pubspec.yaml`): Mobile/web client targeting Sunmi V2 Android devices
- **PHP backend** (`backend/api/index.php`): REST API, single entry point with router
- **MySQL database**: Schema in `backend/guardabcomandero.sql`
- **Python print worker** (`backend/worker/print_worker.py`): Optional, polls print queue

### Starting services

#### MySQL

MySQL must be started manually (systemd doesn't work in the container):
```bash
sudo mkdir -p /var/run/mysqld && sudo chown mysql:mysql /var/run/mysqld && sudo chmod 755 /var/run/mysqld
sudo mysqld --user=mysql --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --port=3306 --bind-address=127.0.0.1 &
```

#### PHP API server

The PHP backend has hardcoded `require_once` paths to `/home/guardab/restaurante/`. Symlinks must exist:
```bash
sudo mkdir -p /home/guardab/restaurante
sudo ln -sf /workspace/backend/config /home/guardab/restaurante/config
sudo ln -sf /workspace/backend/lib /home/guardab/restaurante/lib
```

The hostname `guardabcomandero.mysql.db` must resolve to 127.0.0.1 (add to `/etc/hosts`).

Start the dev server:
```bash
php -S 0.0.0.0:8080 -t /workspace/backend/api /workspace/backend/api/index.php
```

#### Flutter app

```bash
flutter pub get
flutter analyze        # lint check
flutter build web      # build for web testing
flutter build apk      # build for Android (requires Android SDK)
```

### Key gotchas

- The PHP `index.php` uses absolute paths (`/home/guardab/restaurante/...`) — symlinks are required.
- MySQL `--skip-grant-tables` flag disables TCP networking; do NOT use it once users are configured.
- The login endpoint uses `id_usuario` + `password_sha256` (SHA-256 of `username + password`), not plaintext credentials.
- Default admin login: `id_usuario=1`, password hash `ac9689e2272427085e35b9d3e3e8bed88cb3434828b43b86fc0596cad4c6e270` (password is "1234" hashed as `sha256("admin" + "1234")`).
- The Flutter app requires HTTPS in production but works with HTTP for local dev (config screen validation).
- No automated test suite exists in the repository.
- `flutter analyze` reports only info/warnings (no errors) — this is the lint check.
