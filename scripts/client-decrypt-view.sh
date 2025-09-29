#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}

echo "=== Client Server: Decrypt and View Attacker IPs for $DATE ==="

# Step 0: Health check storage servers
echo "🔍 Checking storage server connectivity..."
if ! sss-crypto-tool health-check; then
    echo "❌ Storage servers not accessible"
    exit 1
fi

# Step 1: Retrieve shares from both storage servers
echo "📥 Retrieving share A from Storage Server A..."
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin")

echo "📥 Retrieving share B from Storage Server B..."
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_${DATE}.bin")

# Step 2: Combine shares to reconstruct DEK
echo "🔑 Combining shares to reconstruct DEK..."
RECONSTRUCTED_DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")
echo "DEK reconstructed successfully"

# Step 3: Retrieve encrypted bundle from storage server
echo "📥 Retrieving encrypted bundle from Storage Server A..."
BUNDLE=$(sss-crypto-tool retrieve-from-server A "bundle_${DATE}.json")

echo "🔓 Decrypting bundle..."
DECRYPTED=$(sss-crypto-tool decrypt "$BUNDLE" "$RECONSTRUCTED_DEK")

# Step 4: Display results
echo ""
echo "🎯 Attacker IP addresses for $DATE:"
echo "==============================================="
echo "$DECRYPTED" | jq '.'

# Security: NO plaintext files saved to disk

# Step 5: Show statistics
if command -v jq >/dev/null 2>&1; then
    IP_COUNT=$(echo "$DECRYPTED" | jq '. | length' 2>/dev/null || echo "unknown")
    echo "📊 Total attacker IPs: $IP_COUNT"
fi

echo ""
echo "🎉 Decryption and viewing successful!"

# Clear sensitive data from memory
unset SHARE_A SHARE_B RECONSTRUCTED_DEK DECRYPTED BUNDLE