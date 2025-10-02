#!/bin/bash

# Generate API keys and their SHA256 hashes for the SSS system

echo "==============================================="
echo "   🔑 API Key Generator for SSS System"
echo "==============================================="
echo ""

# Generate random API keys (32 bytes = 64 hex characters)
SERVER_A_API_KEY=$(openssl rand -hex 32)
SERVER_B_API_KEY=$(openssl rand -hex 32)

# Generate SHA256 hashes of the keys
SERVER_A_API_KEY_HASH=$(echo -n "$SERVER_A_API_KEY" | sha256sum | awk '{print $1}')
SERVER_B_API_KEY_HASH=$(echo -n "$SERVER_B_API_KEY" | sha256sum | awk '{print $1}')

echo "Generated API Keys and Hashes:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Storage Server A"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "API Key:  $SERVER_A_API_KEY"
echo "Hash:     $SERVER_A_API_KEY_HASH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Storage Server B"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "API Key:  $SERVER_B_API_KEY"
echo "Hash:     $SERVER_B_API_KEY_HASH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create .env files for each server
echo "Creating environment files..."
echo ""

# Server A .env
cat > server-a.env <<EOF
# Storage Server A - API Key Hash (store this on Server A)
SERVER_A_API_KEY_HASH=$SERVER_A_API_KEY_HASH
EOF
echo "✅ Created: server-a.env (deploy to Server A)"

# Server B .env
cat > server-b.env <<EOF
# Storage Server B - API Key Hash (store this on Server B)
SERVER_B_API_KEY_HASH=$SERVER_B_API_KEY_HASH
EOF
echo "✅ Created: server-b.env (deploy to Server B)"

# Client .env
cat > client.env <<EOF
# Client Server - API Keys (store this on Client ONLY)
SERVER_A_API_KEY=$SERVER_A_API_KEY
SERVER_B_API_KEY=$SERVER_B_API_KEY
EOF
echo "✅ Created: client.env (deploy to Client)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Deployment Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. On Storage Server A (139.91.90.9):"
echo "   cd /tmp/sss-storage"
echo "   # Copy server-a.env to this directory"
echo "   docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d --build"
echo ""
echo "2. On Storage Server B (139.91.90.156):"
echo "   cd /tmp/sss-storage"
echo "   # Copy server-b.env to this directory"
echo "   docker-compose -f docker-compose-server-b.yml --env-file server-b.env up -d --build"
echo ""
echo "3. On Client Server (139.91.90.11):"
echo "   cd /tmp/sss-client"
echo "   # Copy client.env to this directory"
echo "   docker-compose -f docker-compose-client.yml --env-file client.env up -d --build"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 Security Notes:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "• Server A only knows the HASH of API Key A (cannot impersonate client)"
echo "• Server B only knows the HASH of API Key B (cannot impersonate client)"
echo "• Only the client has both actual API keys"
echo "• Even if Server A is compromised, attacker cannot authenticate to Server B"
echo "• Keep client.env SECRET and never copy to storage servers"
echo ""
echo "⚠️  IMPORTANT: Delete this output after distributing the .env files!"
echo ""
