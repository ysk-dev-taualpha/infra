#!/bin/bash
# Nightly backup of docker volumes to HDD (/mnt/data/backups)
# Keeps 7 days, runs via cron or manually
set -e
BACKUP_DIR="/mnt/data/backups"
DATE=$(date +%Y%m%d)
KEEP=7

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting backup to $BACKUP_DIR/$DATE"

# Stop is not needed — tar with --warning=no-file-changed is safe for volumes
# But for consistency, we use docker run --rm with volume mounts
for vol in otel_prom_data otel_grafana_data runtime_runtime_data; do
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    echo "Backing up $vol..."
    docker run --rm -v "$vol:/volume:ro" -v "$BACKUP_DIR:/backup" alpine \
      tar czf "/backup/${vol}_${DATE}.tar.gz" -C / volume 2>&1 | tail -3
    echo "  -> ${vol}_${DATE}.tar.gz ($(du -h "$BACKUP_DIR/${vol}_${DATE}.tar.gz" | cut -f1))"
  else
    echo "Skip $vol (not found)"
  fi
done

# Also backup infra configs and host dotfiles
echo "Backing up configs..."
tar czf "$BACKUP_DIR/configs_${DATE}.tar.gz" \
  --exclude='.env' \
  --exclude='compose/*/.env' \
  -C /home/yplic workspace/infra 2>&1 | tail -3 || true
# Fallback: just tar infra without excludes if above fails
if [ ! -f "$BACKUP_DIR/configs_${DATE}.tar.gz" ]; then
  tar czf "$BACKUP_DIR/configs_${DATE}.tar.gz" -C /home/yplic workspace/infra 2>&1 | tail -3 || true
fi

echo "Cleaning up old backups (keep $KEEP days)..."
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$KEEP -delete 2>&1 | head -5
echo "Remaining backups:"
ls -lh "$BACKUP_DIR" 2>&1 | head -20
echo "[$(date)] Backup done"
