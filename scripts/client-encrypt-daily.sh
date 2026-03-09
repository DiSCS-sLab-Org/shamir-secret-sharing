#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}
DATA_FILE="/data/attackers_${DATE}.txt"

echo "=== Client Server: Daily Encryption Process for $DATE ==="

# Check if data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "❌ Data file not found: $DATA_FILE"
    echo "Please place the attacker IP file in /data/"
    exit 1
fi

echo "📄 Processing file: $DATA_FILE"

# Step 0: Health check storage servers
echo "🔍 Checking storage server connectivity..."
if ! sss-crypto-tool health-check; then
    echo "❌ Storage servers not accessible"
    exit 1
fi

# Step 1: Generate DEK
echo "🔑 Generating DEK..."
DEK=$(sss-crypto-tool generate-dek)
echo "DEK generated: ${DEK:0:16}... (truncated for display)"

# Step 2: Encrypt the data
echo "🔒 Encrypting attacker IP data..."
BUNDLE=$(sss-crypto-tool encrypt "$DATA_FILE" "$DEK" "$DATE")

# Step 3: Store encrypted bundle on both storage servers
echo "📤 Storing encrypted bundle on both storage servers..."
sss-crypto-tool store-on-servers "bundle_${DATE}.json" "$BUNDLE"

# Step 4: Split DEK with SSS (k=2, n=2)
echo "✂️  Splitting DEK with Shamir's Secret Sharing (k=2, n=2)..."
SHARES=$(sss-crypto-tool split "$DEK" 2 2)

# Step 5: Store shares separately on each storage server
SHARE_A=$(echo "$SHARES" | grep "share_A:" | cut -d: -f2)
SHARE_B=$(echo "$SHARES" | grep "share_B:" | cut -d: -f2)

echo "📤 Storing share A on Storage Server A..."
sss-crypto-tool store-on-server A "share_A_${DATE}.bin" "$SHARE_A"

echo "📤 Storing share B on Storage Server B..."
sss-crypto-tool store-on-server B "share_B_${DATE}.bin" "$SHARE_B"

# Delete processed file
echo "🗑️  Deleting processed file..."
rm "$DATA_FILE"

echo "✅ Daily encryption process complete for $DATE"
echo ""
echo "Files created on storage servers:"
echo "  - Storage Server A & B: bundle_${DATE}.json"
echo "  - Storage Server A only: share_A_${DATE}.bin"
echo "  - Storage Server B only: share_B_${DATE}.bin"
echo ""
echo "🗑️  Original file deleted after processing"

# Clear sensitive data from memory
unset DEK SHARES SHARE_A SHARE_B BUNDLE
