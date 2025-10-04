#!/bin/bash
set -e

# Daily CSV Encryption Cron Job
# This script runs on the HOST machine (not in container)
# It moves the CSV file to the correct location and triggers encryption

DATE=$(date +%Y-%m-%d)
SOURCE_FILE="/home/csvreceiver/incoming/top_100_enriched_${DATE}.csv"
DEST_DIR="$HOME/sss-client/data"
DEST_FILE="$DEST_DIR/attackers_${DATE}.json"
LOG_DIR="$HOME/sss-client/logs"
LOG_FILE="$LOG_DIR/encryption_${DATE}.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Start logging
exec > >(tee "$LOG_FILE") 2>&1

echo "=== Daily CSV Encryption Cron Job - $DATE ==="
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Error: Source CSV file not found: $SOURCE_FILE"
    echo "Exiting without encryption"
    echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 1
fi

echo "✅ Found CSV file: $SOURCE_FILE"
FILE_SIZE=$(wc -c < "$SOURCE_FILE")
echo "   File size: $FILE_SIZE bytes"
echo ""

# Ensure destination directory exists
mkdir -p "$DEST_DIR"

# Move and rename the file
echo "📦 Moving file to: $DEST_FILE"
mv "$SOURCE_FILE" "$DEST_FILE"
echo "✅ File moved successfully"
echo ""

# Trigger encryption inside the container
echo "🔒 Starting encryption process..."
docker exec sss-client /scripts/client-encrypt-daily.sh "$DATE"

echo ""
echo "🎉 Daily encryption completed successfully!"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log saved to: $LOG_FILE"
