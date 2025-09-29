#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}

echo "=== Testing Cryptographic Failure Modes for $DATE ==="

# Test 1: Single share compromise (cryptographic level)
echo ""
echo "🧪 Test 1: Attempting DEK reconstruction with only one share..."
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin")

if sss-crypto-tool combine "$SHARE_A" 2>/dev/null; then
    echo "❌ SECURITY FAILURE: Could reconstruct DEK with single share!"
    exit 1
else
    echo "✅ PASS: Cannot reconstruct DEK with single share (cryptographic protection)"
fi

# Test 2: Tamper detection
echo ""
echo "🧪 Test 2: Testing tamper detection..."

# Get valid bundle and DEK
BUNDLE=$(sss-crypto-tool retrieve-from-server A "bundle_${DATE}.json")
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin")
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_${DATE}.bin")
VALID_DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")

# Create tampered bundle by flipping one character in the ciphertext
TAMPERED_BUNDLE=$(echo "$BUNDLE" | sed 's/A/B/')

if sss-crypto-tool decrypt "$TAMPERED_BUNDLE" "$VALID_DEK" 2>/dev/null; then
    echo "❌ SECURITY FAILURE: Tampered data was accepted!"
    exit 1  
else
    echo "✅ PASS: Tampered data rejected (auth tag verification failed)"
fi

# Test 3: Wrong DEK
echo ""
echo "🧪 Test 3: Testing decryption with wrong DEK..."
WRONG_DEK=$(sss-crypto-tool generate-dek)

if sss-crypto-tool decrypt "$BUNDLE" "$WRONG_DEK" 2>/dev/null; then
    echo "❌ SECURITY FAILURE: Wrong DEK was accepted!"
    exit 1
else
    echo "✅ PASS: Wrong DEK rejected"
fi

# Test 4: Invalid share format
echo ""
echo "🧪 Test 4: Testing with corrupted share..."
CORRUPTED_SHARE="invalid-base64-content"

if sss-crypto-tool combine "$SHARE_A" "$CORRUPTED_SHARE" 2>/dev/null; then
    echo "❌ SECURITY FAILURE: Corrupted share was accepted!"
    exit 1
else
    echo "✅ PASS: Corrupted share rejected"
fi

echo ""
echo "🎉 All cryptographic security tests passed!"
echo "The system correctly enforces:"
echo "  - Threshold cryptography (k=2 shares required)"
echo "  - Authenticated encryption (tamper detection)"
echo "  - Key validation (wrong keys rejected)"
echo "  - Input validation (corrupted shares rejected)"

# Clear sensitive data
unset SHARE_A SHARE_B VALID_DEK WRONG_DEK BUNDLE TAMPERED_BUNDLE CORRUPTED_SHARE
