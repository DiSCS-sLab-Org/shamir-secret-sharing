#!/bin/bash
set -euo pipefail

# Daily encryption cron job
# This script runs on the host machine, fetches the latest IP list,
# stores it in the client data directory, and triggers encryption.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATE=$(date +%Y-%m-%d)
PYTHON_BIN="${PYTHON_BIN:-python3}"
FETCH_TIME="${FETCH_TIME:-24h}"
FETCH_PROTOCOL="${FETCH_PROTOCOL:-all}"
FETCH_SCRIPT="$SCRIPT_DIR/fetch_all_cowrie_attackers.py"
DEST_DIR="${DEST_DIR:-$PROJECT_DIR/data}"
DEST_FILE="$DEST_DIR/attackers_${DATE}.txt"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="$LOG_DIR/encryption_${DATE}.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Start logging
exec > >(tee "$LOG_FILE") 2>&1

echo "=== Daily IP Fetch + Encryption Cron Job - $DATE ==="
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Project directory: $PROJECT_DIR"
echo "Fetch window: $FETCH_TIME"
echo "Protocol filter: $FETCH_PROTOCOL"
echo ""

# Ensure fetch script exists
if [ ! -f "$FETCH_SCRIPT" ]; then
    echo "❌ Error: Fetch script not found: $FETCH_SCRIPT"
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "❌ Error: Python interpreter not found: $PYTHON_BIN"
    echo "Set PYTHON_BIN to the interpreter that has the fetch script dependencies installed."
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
fi

if ! "$PYTHON_BIN" -c "import elasticsearch" >/dev/null 2>&1; then
    echo "❌ Error: Python package 'elasticsearch' is not available in $PYTHON_BIN"
    echo "Install the dependency or set PYTHON_BIN to a virtualenv interpreter that has it."
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
fi

# Ensure destination directory exists
mkdir -p "$DEST_DIR"

# Remove a stale output file so the size and existence checks only reflect this run
rm -f "$DEST_FILE"

# Fetch the current IP list directly into the client data directory
echo "📥 Fetching attacker IP list to: $DEST_FILE"
"$PYTHON_BIN" "$FETCH_SCRIPT" \
    --time "$FETCH_TIME" \
    --protocol "$FETCH_PROTOCOL" \
    --output-dir "$DEST_DIR" \
    --output "$(basename "$DEST_FILE")"

if [ ! -s "$DEST_FILE" ]; then
    echo "❌ Error: Fetch completed but no output file was created: $DEST_FILE"
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
fi

FILE_SIZE=$(wc -c < "$DEST_FILE")
LINE_COUNT=$(wc -l < "$DEST_FILE")
echo "✅ IP list fetched successfully"
echo "   File size: $FILE_SIZE bytes"
echo "   IP count: $LINE_COUNT"
echo ""

# Trigger encryption inside the container
echo "🔒 Starting encryption process..."
docker exec sss-client /scripts/client-encrypt-daily.sh "$DATE"

echo ""
echo "🎉 Daily encryption completed successfully!"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log saved to: $LOG_FILE"
