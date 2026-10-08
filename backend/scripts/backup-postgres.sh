#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
backup_dir="${BACKUP_DIR:-./backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
backup_file="$backup_dir/yenko_${timestamp}.dump"

pg_dump --dbname="$DATABASE_URL" --format=custom --no-owner --no-privileges --file="$backup_file"
shasum -a 256 "$backup_file" > "$backup_file.sha256"
printf 'Created %s and checksum. Encrypt and copy this backup to independent storage.\n' "$backup_file"
