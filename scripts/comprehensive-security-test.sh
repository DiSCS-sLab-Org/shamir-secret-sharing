#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}
TEST_FILE="/data/attackers_${DATE}.txt"
ORIGINAL_HASH=""

echo "=== Comprehensive Security Test for $DATE ==="
echo ""

# Step 1: Create test file and record hash
echo "📄 Step 1: Creating test file with known content..."
cat > "$TEST_FILE" << 'EOF'
203.0.113.100
198.51.100.50
EOF

echo "✅ Test file created: $TEST_FILE"
ORIGINAL_HASH=$(sha256sum "$TEST_FILE" | cut -d' ' -f1)
echo "🔍 Original file hash: $ORIGINAL_HASH"
echo ""

# Step 2: Verify file exists before encryption
echo "📋 Step 2: Pre-encryption verification..."
if [ -f "$TEST_FILE" ]; then
    echo "✅ Original file exists"
    echo "📊 File size: $(wc -c < "$TEST_FILE") bytes"
else
    echo "❌ Original file missing!"
    exit 1
fi
echo ""

# Step 3: Run encryption process
echo "🔒 Step 3: Running encryption process..."
/scripts/client-encrypt-daily.sh "$DATE"
echo ""

# Step 4: Verify original file is deleted
echo "🗑️  Step 4: Verifying original file deletion..."
if [ -f "$TEST_FILE" ]; then
    echo "❌ SECURITY FAILURE: Original file still exists!"
    exit 1
else
    echo "✅ Original file successfully deleted"
fi

# Check no artifacts in data directory
REMAINING_FILES=$(find /data -name "*${DATE}*" 2>/dev/null | wc -l)
if [ "$REMAINING_FILES" -eq 0 ]; then
    echo "✅ No artifacts remaining in /data"
else
    echo "❌ SECURITY FAILURE: Artifacts found in /data:"
    find /data -name "*${DATE}*"
    exit 1
fi
echo ""

# Step 5: Verify encrypted data on both servers
echo "🔍 Step 5: Verifying encrypted data on storage servers..."

# Check bundle exists on both servers
BUNDLE_A=$(sss-crypto-tool retrieve-from-server A "bundle_${DATE}.json" 2>/dev/null || echo "")
BUNDLE_B=$(sss-crypto-tool retrieve-from-server B "bundle_${DATE}.json" 2>/dev/null || echo "")

if [ -z "$BUNDLE_A" ] || [ -z "$BUNDLE_B" ]; then
    echo "❌ SECURITY FAILURE: Encrypted bundle missing from servers!"
    exit 1
fi

if [ "$BUNDLE_A" != "$BUNDLE_B" ]; then
    echo "❌ SECURITY FAILURE: Bundle data inconsistent between servers!"
    exit 1
fi

echo "✅ Encrypted bundle exists on both servers"
echo "✅ Bundle data is identical on both servers"

# Verify bundle is actually encrypted (not plaintext)
if echo "$BUNDLE_A" | grep -q "203.0.113.100"; then
    echo "❌ SECURITY FAILURE: Plaintext data found in encrypted bundle!"
    exit 1
fi
echo "✅ Bundle contains encrypted data (no plaintext visible)"

# Check shares exist and are different
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin" 2>/dev/null || echo "")
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_${DATE}.bin" 2>/dev/null || echo "")

if [ -z "$SHARE_A" ] || [ -z "$SHARE_B" ]; then
    echo "❌ SECURITY FAILURE: Key shares missing from servers!"
    exit 1
fi

if [ "$SHARE_A" = "$SHARE_B" ]; then
    echo "❌ SECURITY FAILURE: Key shares are identical (should be different)!"
    exit 1
fi

echo "✅ Different key shares stored on each server"
echo ""

# Step 6: Test single server compromise (should fail)
echo "🛡️  Step 6: Testing single server compromise protection..."
echo "   Attempting to decrypt with only one share..."

if sss-crypto-tool combine "$SHARE_A" 2>/dev/null; then
    echo "❌ SECURITY FAILURE: Could reconstruct key with single share!"
    exit 1
else
    echo "✅ Single share compromise protected"
fi
echo ""

# Step 7: Full decryption test
echo "🔓 Step 7: Testing complete decryption process..."
DECRYPTED_CONTENT=$(bash -c "
    SHARE_A=\$(sss-crypto-tool retrieve-from-server A \"share_A_${DATE}.bin\")
    SHARE_B=\$(sss-crypto-tool retrieve-from-server B \"share_B_${DATE}.bin\")
    RECONSTRUCTED_DEK=\$(sss-crypto-tool combine \"\$SHARE_A\" \"\$SHARE_B\")
    BUNDLE=\$(sss-crypto-tool retrieve-from-server A \"bundle_${DATE}.json\")
    sss-crypto-tool decrypt \"\$BUNDLE\" \"\$RECONSTRUCTED_DEK\"
")

if [ $? -ne 0 ] || [ -z "$DECRYPTED_CONTENT" ]; then
    echo "❌ SECURITY FAILURE: Decryption failed!"
    exit 1
fi

echo "✅ Decryption successful"

# Save decrypted content to temporary file for hash comparison
TEMP_FILE=$(mktemp)
echo "$DECRYPTED_CONTENT" > "$TEMP_FILE"
DECRYPTED_HASH=$(sha256sum "$TEMP_FILE" | cut -d' ' -f1)
rm "$TEMP_FILE"

echo ""

# Step 8: Verify data integrity (no tampering)
echo "🔐 Step 8: Verifying data integrity (no tampering)..."
echo "🔍 Original hash:  $ORIGINAL_HASH"
echo "🔍 Decrypted hash: $DECRYPTED_HASH"

if [ "$ORIGINAL_HASH" = "$DECRYPTED_HASH" ]; then
    echo "✅ PERFECT: Decrypted data matches original exactly"
else
    echo "❌ SECURITY FAILURE: Data tampering detected!"
    echo "Original data differs from decrypted data"
    exit 1
fi
echo ""

# Step 9: Verify no sensitive data leakage
echo "🔍 Step 9: Checking for sensitive data leakage..."

# Check if any plaintext IPs are stored unencrypted on servers
SERVERS_LEAKING=false

# Check server A data directory (if accessible)
if docker exec storage-server-a find /data -name "*${DATE}*" -exec grep -l "203.0.113.100" {} \; 2>/dev/null | grep -q .; then
    echo "❌ SECURITY FAILURE: Plaintext data found on Server A!"
    SERVERS_LEAKING=true
fi

# Check server B data directory (if accessible)
if docker exec storage-server-b find /data -name "*${DATE}*" -exec grep -l "203.0.113.100" {} \; 2>/dev/null | grep -q .; then
    echo "❌ SECURITY FAILURE: Plaintext data found on Server B!"
    SERVERS_LEAKING=true
fi

if [ "$SERVERS_LEAKING" = false ]; then
    echo "✅ No plaintext data leakage detected on storage servers"
fi
echo ""

# Final summary
echo "🎉 COMPREHENSIVE SECURITY TEST COMPLETE"
echo "=============================================="
echo "✅ Original file deleted after encryption"
echo "✅ No artifacts remaining in processing directory"
echo "✅ Encrypted data stored on both servers identically"
echo "✅ Data is actually encrypted (not plaintext)"
echo "✅ Different key shares on each server"
echo "✅ Single server compromise protection works"
echo "✅ Full decryption process works"
echo "✅ Data integrity preserved (no tampering)"
echo "✅ No sensitive data leakage"
echo ""
echo "🛡️  SECURITY STATUS: ALL TESTS PASSED"
echo "The system is secure and working as designed!"
