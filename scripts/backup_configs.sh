#!/bin/bash

BACKUP_DIR="/srv/sambashare/data/server-configs"
mkdir -p "$BACKUP_DIR"

echo "[$(date "+%Y-%m-%d %H:%M:%S")] Starting config backup..."

# Immich Postgres dump
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Dumping Immich Postgres..."
docker exec immich_postgres pg_dumpall -U postgres > "$BACKUP_DIR/immich_postgres.sql"

# NPM config
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying NPM config..."
rsync -a /home/drc/npm/data/ "$BACKUP_DIR/npm/"

# AdGuard config — read via docker (the host file is root-owned 0600, so a plain
# rsync as drc fails "Permission denied"; docker exec runs as root inside the
# container and can read it). Config lives at /opt/adguardhome/conf/.
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying AdGuard config..."
mkdir -p "$BACKUP_DIR/adguard"
docker exec adguard cat /opt/adguardhome/conf/AdGuardHome.yaml > "$BACKUP_DIR/adguard/AdGuardHome.yaml"

# Uptime Kuma data
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying Uptime Kuma data..."
rsync -a /home/drc/uptime-kuma/data/ "$BACKUP_DIR/uptime-kuma/"

# Backrest config — same root-owned 0600 problem; read via docker exec.
# NOTE: config.json contains the B2 keys + restic repo password. This copy is for
# reconstructing Backrest's SETTINGS; it is NOT a recovery path for the password
# itself (it's inside the encrypted backup = circular). Keep the repo password
# escrowed OUT-OF-BAND (password manager / printed).
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying Backrest config..."
mkdir -p "$BACKUP_DIR/backrest"
docker exec backrest cat /config/config.json > "$BACKUP_DIR/backrest/config.json"

# Filebrowser (settings DB + config)
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying Filebrowser config..."
rsync -a /home/drc/filebrowser/ "$BACKUP_DIR/filebrowser/"

# Beszel (server stats): settings, users, alerts, and metric history live in
# data.db. Take a consistent SQLite snapshot (safe while the hub is writing),
# and copy the hub key so a rebuilt agent can still authenticate.
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Backing up Beszel..."
mkdir -p "$BACKUP_DIR/beszel"
python3 - /home/drc/beszel/beszel_data/data.db "$BACKUP_DIR/beszel/data.db" <<'PYEOF'
import sqlite3, sys
s = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); d = sqlite3.connect(sys.argv[2])
with d: s.backup(d)
d.close(); s.close()
PYEOF
cp /home/drc/beszel/beszel_data/id_ed25519 "$BACKUP_DIR/beszel/id_ed25519"

# NOTE: cloudflared / cloudflared-tunnel have no config files — their tunnel tokens
# live in the compose/.env captured below, so they're already covered.

# Docker compose files
echo "[$(date "+%Y-%m-%d %H:%M:%S")] Copying compose files..."
mkdir -p "$BACKUP_DIR/compose"
for dir in /home/drc/*/docker-compose.yml; do
  service=$(basename "$(dirname "$dir")")
  cp "$dir" "$BACKUP_DIR/compose/${service}.yml"
done

# .env files (needed for immich, etc.)
for dir in /home/drc/*/; do
  if [ -f "$dir/.env" ]; then
    service=$(basename "$dir")
    cp "$dir/.env" "$BACKUP_DIR/compose/${service}.env"
  fi
done


echo "[$(date "+%Y-%m-%d %H:%M:%S")] Config backup complete."
