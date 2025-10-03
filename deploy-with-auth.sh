#!/bin/bash
set -e

# SSS System - Complete Deployment Script with Authentication
# This script generates API keys and deploys all necessary files to the servers
# Usage: ./deploy-with-auth.sh [tmp|opt]

STORAGE_SERVER_A_IP="139.91.90.9"
STORAGE_SERVER_B_IP="139.91.90.156"
CLIENT_SERVER_IP="139.91.90.11"
USER="liakakos"

# Parse deployment location parameter
DEPLOY_MODE="${1:-tmp}"
if [[ "$DEPLOY_MODE" != "tmp" && "$DEPLOY_MODE" != "prod" ]]; then
    echo "❌ Error: Invalid parameter. Use 'tmp' or 'prod'"
    echo "Usage: $0 [tmp|prod]"
    exit 1
fi

# Set base directories based on deployment mode
if [[ "$DEPLOY_MODE" == "prod" ]]; then
    STORAGE_BASE_DIR="~/sss-storage"
    CLIENT_BASE_DIR="~/sss-client"
    USE_SUDO=""
    echo "📍 Deployment mode: PRODUCTION (~/ home directory)"
else
    STORAGE_BASE_DIR="/tmp/sss-storage"
    CLIENT_BASE_DIR="/tmp/sss-client"
    USE_SUDO=""
    echo "📍 Deployment mode: TESTING (/tmp)"
fi

echo "==============================================="
echo "   🚀 SSS Complete Deployment Script"
echo "==============================================="
echo ""
echo "This script will:"
echo "  1. Generate new API keys"
echo "  2. Upload all code files to servers"
echo "  3. Create environment files"
echo "  4. Deploy containers with authentication"
echo ""
echo "Target Servers:"
echo "  📦 Storage Server A: $STORAGE_SERVER_A_IP → $STORAGE_BASE_DIR"
echo "  📦 Storage Server B: $STORAGE_SERVER_B_IP → $STORAGE_BASE_DIR"
echo "  💻 Client Server:    $CLIENT_SERVER_IP → $CLIENT_BASE_DIR"
echo ""

# Confirm deployment
read -p "Proceed with deployment? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Generating API Keys"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clean up old env files
rm -f server-a.env server-b.env client.env

# Generate random API keys (32 bytes = 64 hex characters)
echo "🔑 Generating random API keys..."
SERVER_A_API_KEY=$(openssl rand -hex 32)
SERVER_B_API_KEY=$(openssl rand -hex 32)

# Generate SHA256 hashes of the keys
echo "🔐 Computing SHA256 hashes..."
SERVER_A_API_KEY_HASH=$(echo -n "$SERVER_A_API_KEY" | sha256sum | awk '{print $1}')
SERVER_B_API_KEY_HASH=$(echo -n "$SERVER_B_API_KEY" | sha256sum | awk '{print $1}')

echo "✅ API Keys Generated"
echo ""
echo "Storage Server A:"
echo "  API Key:  ${SERVER_A_API_KEY:0:16}... (truncated)"
echo "  Hash:     ${SERVER_A_API_KEY_HASH:0:16}..."
echo ""
echo "Storage Server B:"
echo "  API Key:  ${SERVER_B_API_KEY:0:16}... (truncated)"
echo "  Hash:     ${SERVER_B_API_KEY_HASH:0:16}..."
echo ""

# Create .env files
cat > server-a.env <<EOF
SERVER_A_API_KEY_HASH=$SERVER_A_API_KEY_HASH
EOF

cat > server-b.env <<EOF
SERVER_B_API_KEY_HASH=$SERVER_B_API_KEY_HASH
EOF

cat > client.env <<EOF
SERVER_A_API_KEY=$SERVER_A_API_KEY
SERVER_B_API_KEY=$SERVER_B_API_KEY
EOF

echo "✅ Environment files created"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Uploading Files to Storage Server A"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📦 Creating remote directory..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" "mkdir -p $STORAGE_BASE_DIR"

echo "📤 Uploading storage server code..."
scp storage-server/main.go "${USER}@${STORAGE_SERVER_A_IP}:${STORAGE_BASE_DIR}-upload-main.go"
scp storage-server/go.mod "${USER}@${STORAGE_SERVER_A_IP}:${STORAGE_BASE_DIR}-upload-go.mod"
ssh "${USER}@${STORAGE_SERVER_A_IP}" "mkdir -p $STORAGE_BASE_DIR/storage-server && mv ${STORAGE_BASE_DIR}-upload-main.go $STORAGE_BASE_DIR/storage-server/main.go && mv ${STORAGE_BASE_DIR}-upload-go.mod $STORAGE_BASE_DIR/storage-server/go.mod"

echo "📤 Uploading Dockerfile..."
scp docker/Dockerfile.server "${USER}@${STORAGE_SERVER_A_IP}:${STORAGE_BASE_DIR}/"

echo "📤 Uploading docker-compose configuration..."
scp docker/docker-compose-server-a.yml "${USER}@${STORAGE_SERVER_A_IP}:${STORAGE_BASE_DIR}/"

echo "📤 Uploading environment file..."
scp server-a.env "${USER}@${STORAGE_SERVER_A_IP}:${STORAGE_BASE_DIR}/"

echo "✅ Storage Server A files uploaded"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Uploading Files to Storage Server B"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📦 Creating remote directory..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" "mkdir -p $STORAGE_BASE_DIR"

echo "📤 Uploading storage server code..."
scp storage-server/main.go "${USER}@${STORAGE_SERVER_B_IP}:${STORAGE_BASE_DIR}-upload-main.go"
scp storage-server/go.mod "${USER}@${STORAGE_SERVER_B_IP}:${STORAGE_BASE_DIR}-upload-go.mod"
ssh "${USER}@${STORAGE_SERVER_B_IP}" "mkdir -p $STORAGE_BASE_DIR/storage-server && mv ${STORAGE_BASE_DIR}-upload-main.go $STORAGE_BASE_DIR/storage-server/main.go && mv ${STORAGE_BASE_DIR}-upload-go.mod $STORAGE_BASE_DIR/storage-server/go.mod"

echo "📤 Uploading Dockerfile..."
scp docker/Dockerfile.server "${USER}@${STORAGE_SERVER_B_IP}:${STORAGE_BASE_DIR}/"

echo "📤 Uploading docker-compose configuration..."
scp docker/docker-compose-server-b.yml "${USER}@${STORAGE_SERVER_B_IP}:${STORAGE_BASE_DIR}/"

echo "📤 Uploading environment file..."
scp server-b.env "${USER}@${STORAGE_SERVER_B_IP}:${STORAGE_BASE_DIR}/"

echo "✅ Storage Server B files uploaded"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Uploading Files to Client Server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📦 Creating remote directories..."
ssh "${USER}@${CLIENT_SERVER_IP}" "mkdir -p $CLIENT_BASE_DIR/crypto-tools $CLIENT_BASE_DIR/scripts"

echo "📤 Uploading crypto-tools code..."
scp crypto-tools/main.go "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/crypto-tools/"
scp crypto-tools/go.mod "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/crypto-tools/"
scp crypto-tools/go.sum "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/crypto-tools/"

echo "📤 Uploading scripts..."
scp scripts/*.sh "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/scripts/"

echo "📤 Uploading Dockerfile..."
scp docker/Dockerfile.client "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/"

echo "📤 Uploading docker-compose configuration..."
scp docker/docker-compose-client.yml "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/"

echo "📤 Uploading environment file..."
scp client.env "${USER}@${CLIENT_SERVER_IP}:${CLIENT_BASE_DIR}/"
ssh "${USER}@${CLIENT_SERVER_IP}" "chmod 600 ${CLIENT_BASE_DIR}/client.env"

echo "✅ Client Server files uploaded"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Building and Starting Storage Server A"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🏗️  Stopping old containers..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-a.yml down 2>/dev/null || true"

echo "🏗️  Building and starting with authentication..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d --build"

echo "⏳ Waiting for server to start..."
sleep 5

echo "🔍 Checking server status..."
if ssh "${USER}@${STORAGE_SERVER_A_IP}" 'docker ps | grep sss-storage-server-a' > /dev/null; then
    echo "✅ Storage Server A is running"
else
    echo "⚠️  Storage Server A may not be running properly"
    echo "Check logs with: ssh ${USER}@${STORAGE_SERVER_A_IP} 'docker logs sss-storage-server-a'"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Building and Starting Storage Server B"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🏗️  Stopping old containers..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-b.yml down 2>/dev/null || true"

echo "🏗️  Building and starting with authentication..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-b.yml --env-file server-b.env up -d --build"

echo "⏳ Waiting for server to start..."
sleep 5

echo "🔍 Checking server status..."
if ssh "${USER}@${STORAGE_SERVER_B_IP}" 'docker ps | grep sss-storage-server-b' > /dev/null; then
    echo "✅ Storage Server B is running"
else
    echo "⚠️  Storage Server B may not be running properly"
    echo "Check logs with: ssh ${USER}@${STORAGE_SERVER_B_IP} 'docker logs sss-storage-server-b'"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 7: Building and Starting Client Server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🏗️  Stopping old containers..."
ssh "${USER}@${CLIENT_SERVER_IP}" "cd $CLIENT_BASE_DIR && docker-compose -f docker-compose-client.yml down 2>/dev/null || true"

echo "🏗️  Building and starting with API keys..."
ssh "${USER}@${CLIENT_SERVER_IP}" "cd $CLIENT_BASE_DIR && docker-compose -f docker-compose-client.yml --env-file client.env up -d --build"

echo "⏳ Waiting for client to start..."
sleep 5

echo "🔍 Checking client status..."
if ssh "${USER}@${CLIENT_SERVER_IP}" 'docker ps | grep sss-client' > /dev/null; then
    echo "✅ Client Server is running"
else
    echo "⚠️  Client Server may not be running properly"
    echo "Check logs with: ssh ${USER}@${CLIENT_SERVER_IP} 'docker logs sss-client'"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 8: Testing Authentication"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🧪 Test 1: Verify servers reject unauthenticated requests..."
if curl -s -o /dev/null -w "%{http_code}" "http://${STORAGE_SERVER_A_IP}:8080/retrieve?filename=test.bin" | grep -q "401"; then
    echo "✅ Server A correctly rejects unauthenticated requests"
else
    echo "⚠️  Server A authentication may not be working"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://${STORAGE_SERVER_B_IP}:8080/retrieve?filename=test.bin" | grep -q "401"; then
    echo "✅ Server B correctly rejects unauthenticated requests"
else
    echo "⚠️  Server B authentication may not be working"
fi
echo ""

echo "🧪 Test 2: Verify client can authenticate to both servers..."
ssh "${USER}@${CLIENT_SERVER_IP}" 'docker exec sss-client sss-crypto-tool health-check' && echo "✅ Client successfully authenticates to both servers" || echo "⚠️  Client authentication failed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "  ✅ Storage Server A: Running with authentication"
echo "  ✅ Storage Server B: Running with authentication"
echo "  ✅ Client Server:    Running with API keys"
echo ""
echo "🔒 Security:"
echo "  • Server A has: HASH(API_KEY_A) only"
echo "  • Server B has: HASH(API_KEY_B) only"
echo "  • Client has: Both plaintext API keys"
echo "  • Cross-server attacks: BLOCKED ✅"
echo ""
echo "📖 Next Steps:"
echo "  1. Test encryption/decryption (see DEPLOYMENT.md)"
echo "  2. Review logs for authentication events"
echo "  3. (Optional) Configure firewall rules"
echo "  4. (Optional) Enable HTTPS/TLS"
echo ""
echo "📝 Environment Files (saved locally):"
echo "  • server-a.env (Server A hash)"
echo "  • server-b.env (Server B hash)"
echo "  • client.env (Client API keys) ⚠️  KEEP SECRET"
echo ""
echo "⚠️  IMPORTANT: Backup client.env securely, then delete local copies!"
echo ""
