#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <backup_file>" >&2
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE" >&2
    exit 1
fi

CONTAINER_BACKUP="/tmp/barq_restore.dump"

echo "Restoring PostgreSQL backup..."

docker cp "$BACKUP_FILE" "postgres:${CONTAINER_BACKUP}"

docker exec postgres pg_restore \
    -U barq_app \
    -d barq_tasks \
    --clean \
    --if-exists \
    "${CONTAINER_BACKUP}"

RECORD_COUNT=$(docker exec postgres psql -U barq_app -d barq_tasks -tAc "SELECT COUNT(*) FROM records;")
if [ "$RECORD_COUNT" -gt 0 ]; then
    echo "Restore verified: $RECORD_COUNT record(s) found."
else
    echo "Restore verification failed: no records found." >&2
    exit 1
fi

docker exec postgres rm "${CONTAINER_BACKUP}"
echo "Restore completed successfully."
