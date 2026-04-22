#!/usr/bin/env bash
set -euo pipefail

# Simple Koha instance backup + optional shutdown script
# Usage: koha-backup.sh [-i instance] [-o outdir] [--shutdown]

INSTANCE="pul-km"
OUTDIR="/root/koha-backup"
SHUTDOWN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--instance) INSTANCE="$2"; shift 2 ;;
    -o|--outdir) OUTDIR="$2"; shift 2 ;;
    --shutdown) SHUTDOWN=1; shift ;;
    -h|--help) echo "Usage: $0 [-i instance] [-o outdir] [--shutdown]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

TS=$(date +%Y%m%d-%H%M%S)
DEST="$OUTDIR/${INSTANCE}-${TS}"
mkdir -p "$DEST"

echo "Backing up Koha instance '$INSTANCE' to $DEST"

# find mysql client
if ! command -v mysql >/dev/null 2>&1; then
  echo "mysql client not found" >&2
  exit 1
fi

# parse DB credentials from koha-conf.xml
KOHA_CONF="/etc/koha/sites/${INSTANCE}/koha-conf.xml"
if [ ! -f "$KOHA_CONF" ]; then
  echo "Koha config $KOHA_CONF not found" >&2
  exit 1
fi
DB_NAME=$(grep -oPm1 '(?<=<database>)[^<]+' "$KOHA_CONF" || echo "koha_${INSTANCE}")
DB_USER=$(grep -oPm1 '(?<=<user>)[^<]+' "$KOHA_CONF" || echo "koha_${INSTANCE}")
DB_PASS=$(grep -oPm1 '(?<=<pass>)[^<]+' "$KOHA_CONF" || echo "")

echo "DB: $DB_NAME user:$DB_USER"

# Dump database
SQLFILE="$DEST/${DB_NAME}.sql.gz"
echo "Dumping database to $SQLFILE"
if [ -n "$DB_PASS" ]; then
  mysqldump -u"$DB_USER" -p"$DB_PASS" --skip-lock-tables --single-transaction --routines --triggers "$DB_NAME" | gzip -c > "$SQLFILE"
else
  mysqldump -u"$DB_USER" --skip-lock-tables --single-transaction --routines --triggers "$DB_NAME" | gzip -c > "$SQLFILE"
fi

# Backup var/lib files (uploads, plugins, tmp, biblios)
TARFILE="$DEST/${INSTANCE}-files.tar.gz"
echo "Archiving /var/lib/koha/$INSTANCE -> $TARFILE"
tar -czf "$TARFILE" -C / var/lib/koha/${INSTANCE} || true

# Backup apache vhost and koha-conf copy
if [ -f "/etc/apache2/sites-available/${INSTANCE}.conf" ]; then
  cp "/etc/apache2/sites-available/${INSTANCE}.conf" "$DEST/"
fi
cp "$KOHA_CONF" "$DEST/" || true

# Optional: shutdown Koha services (if requested)
if [ "$SHUTDOWN" -eq 1 ]; then
  echo "Stopping Koha services (apache2, koha-common, memcached)"
  systemctl stop koha-common || true
  systemctl stop memcached || true
  systemctl stop apache2 || true
  koha-plack --stop "$INSTANCE" || true
fi

# permissions
chown -R root:root "$DEST"

echo "Backup complete:"
ls -lah "$DEST"

echo "To restore, use koha-restore or follow the documented hybrid-restore steps."

exit 0
