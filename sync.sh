#!/bin/bash

# === Load config ===
source .env
source .last_db_sync_time

# === Initialize LAST_SYNC ===
if [ ! -f "$LAST_SYNC_FILE" ]; then
    echo "2024-01-01 00:00:00" > "$LAST_SYNC_FILE"
fi
LAST_SYNC=$(cat "$LAST_SYNC_FILE")
NOW=$(date "+%F %T")

echo "[INFO] Last sync: $LAST_SYNC"
echo "[INFO] Current time: $NOW"

# === Start SSH tunnel ===
# === Kill any stale tunnel
EXISTING_TUNNEL_PID=$(lsof -ti tcp:$LOCAL_TUNNEL_PORT)
if [ -n "$EXISTING_TUNNEL_PID" ]; then
    echo "[WARN] Existing SSH tunnel on port $LOCAL_TUNNEL_PORT found (PID $EXISTING_TUNNEL_PID), killing it..."
    kill -9 $EXISTING_TUNNEL_PID
    sleep 1
fi

# === Start SSH tunnel
echo "[INFO] Opening SSH tunnel..."
ssh -i "$SSH_KEY" -f -N -L ${LOCAL_TUNNEL_PORT}:127.0.0.1:${REMOTE_MYSQL_PORT} \
    -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}

sleep 2

# === Get the actual SSH tunnel PID ===
TUNNEL_PID=$(pgrep -f "ssh.*-L ${LOCAL_TUNNEL_PORT}:127.0.0.1:${REMOTE_MYSQL_PORT}")

if [ -z "$TUNNEL_PID" ]; then
    echo "[ERROR] Failed to open SSH tunnel."
    exit 1
fi

echo "[INFO] SSH tunnel established with PID $TUNNEL_PID"

# === Trap to auto-cleanup tunnel ===
trap '[ -n "$TUNNEL_PID" ] && echo "[TRAP] Closing SSH tunnel..." && kill $TUNNEL_PID 2>/dev/null' EXIT

# === Sync each table ===
for TABLE in $TABLES; do
    echo "[SYNC] Exporting $TABLE from remote..."
    mysqldump -h 127.0.0.1 -P $LOCAL_TUNNEL_PORT \
        -u $REMOTE_DB_USER -p$REMOTE_DB_PASS $REMOTE_DB $TABLE \
        --where="created_at >= '$LAST_SYNC'" \
	--no-create-info --skip-add-drop-table --replace \
        --skip-lock-tables --quick \
        > /tmp/${TABLE}_delta.sql

    echo "[IMPORT] Importing $TABLE into local $LOCAL_DB..."
    mysql -u $LOCAL_DB_USER -p$LOCAL_DB_PASS $LOCAL_DB < /tmp/${TABLE}_delta.sql
done

# === Update last sync time ===
echo "$NOW" > "$LAST_SYNC_FILE"
echo "[DONE] Sync completed at $NOW"

