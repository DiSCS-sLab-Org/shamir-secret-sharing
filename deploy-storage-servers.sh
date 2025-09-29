#!/bin/bash
set -e

# Deploy Storage Servers A & B
STORAGE_SERVER_A_IP="139.91.90.9"
STORAGE_SERVER_B_IP="139.91.90.156"
LOCAL_USER="liakakos"

echo "=== Deploying Storage Servers ==="
echo "Storage Server A: $STORAGE_SERVER_A_IP"
echo "Storage Server B: $STORAGE_SERVER_B_IP"
echo ""

# Create temporary directory structure for storage servers
TEMP_DIR="/tmp/sss-storage-deploy"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "📦 Preparing storage server files..."

# Copy only files needed for storage servers
cp Dockerfile.server "$TEMP_DIR/"
cp docker-compose-server-a.yml "$TEMP_DIR/"
cp docker-compose-server-b.yml "$TEMP_DIR/"
cp -r server-src/ "$TEMP_DIR/" 2>/dev/null || echo "⚠️  No server-src directory found"

# Copy server source code (the actual Go server implementation)
mkdir -p "$TEMP_DIR/server"
cp server/*.go "$TEMP_DIR/server/" 2>/dev/null || {
    echo "ℹ️  Server source not found in /server, checking /crypto-tools..."
    # If server code is in crypto-tools, we'll need the whole directory
    cp -r crypto-tools/ "$TEMP_DIR/" 2>/dev/null || {
        echo "❌ Error: No server source code found!"
        echo "Please ensure server implementation is available."
        exit 1
    }
}

echo ""
echo "🚀 Deploying to Storage Server A ($STORAGE_SERVER_A_IP)..."
scp -r "$TEMP_DIR"/* "${LOCAL_USER}@${STORAGE_SERVER_A_IP}:/tmp/sss-storage/"

echo ""
echo "🚀 Deploying to Storage Server B ($STORAGE_SERVER_B_IP)..."
scp -r "$TEMP_DIR"/* "${LOCAL_USER}@${STORAGE_SERVER_B_IP}:/tmp/sss-storage/"

echo ""
echo "🏗️  Building and starting Storage Server A..."
ssh "${LOCAL_USER}@${STORAGE_SERVER_A_IP}" << 'EOF'
cd /tmp/sss-storage
sudo docker-compose -f docker-compose-server-a.yml down || true
sudo docker-compose -f docker-compose-server-a.yml up -d --build
echo "✅ Storage Server A deployed and running"
EOF

echo ""
echo "🏗️  Building and starting Storage Server B..."
ssh "${LOCAL_USER}@${STORAGE_SERVER_B_IP}" << 'EOF'
cd /tmp/sss-storage
sudo docker-compose -f docker-compose-server-b.yml down || true
sudo docker-compose -f docker-compose-server-b.yml up -d --build
echo "✅ Storage Server B deployed and running"
EOF

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "🎉 Storage servers deployment complete!"
echo ""
echo "📋 Verification commands:"
echo "# Test Storage Server A:"
echo "curl http://$STORAGE_SERVER_A_IP:8080/health"
echo ""
echo "# Test Storage Server B:"
echo "curl http://$STORAGE_SERVER_B_IP:8080/health"