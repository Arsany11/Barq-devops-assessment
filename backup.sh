#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=".local-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="barq_tasks_${TIMESTAMP}.dump"
CONTAINER_BACKUP="/tmp/${BACKUP_FILE}"

mkdir -p "${BACKUP_DIR}"
echo "Creating PostgreSQL backup..."

docker exec postgres pg_dump \
    -U barq_app \
    -d barq_tasks \
    -Fc \
    -f "${CONTAINER_BACKUP}" 

docker cp "postgres:${CONTAINER_BACKUP}" "$BACKUP_DIR/$BACKUP_FILE"

docker exec postgres rm "${CONTAINER_BACKUP}"
echo "Backup created successfully:"
echo "$BACKUP_DIR/$BACKUP_FILE"
