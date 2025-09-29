#!/bin/bash
set -e

# Deploy Client Server
CLIENT_SERVER_IP="139.91.90.11"
LOCAL_USER="liakakos"

echo "=== Deploying Client Server ==="
echo "Client Server: $CLIENT_SERVER_IP"
echo ""

# Create temporary directory structure for client
TEMP_DIR="/tmp/sss-client-deploy"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/scripts"

echo "📦 Preparing client server files..."

# Copy only files needed for client server
cp Dockerfile.client "$TEMP_DIR/"
cp docker-compose-client.yml "$TEMP_DIR/"
cp -r crypto-tools/ "$TEMP_DIR/"

# Copy client-specific scripts only
cp scripts/client-encrypt-daily.sh "$TEMP_DIR/scripts/"
cp scripts/client-decrypt-view.sh "$TEMP_DIR/scripts/"
cp scripts/comprehensive-security-test.sh "$TEMP_DIR/scripts/"
cp scripts/test-failures.sh "$TEMP_DIR/scripts/"

# Copy documentation
cp DOCKER_DEPLOYMENT_GUIDE.md "$TEMP_DIR/"

echo ""
echo "🚀 Deploying to Client Server ($CLIENT_SERVER_IP)..."
scp -r "$TEMP_DIR"/* "${LOCAL_USER}@${CLIENT_SERVER_IP}:/tmp/sss-client/"

echo ""
echo "🏗️  Building and starting Client Server..."
ssh "${LOCAL_USER}@${CLIENT_SERVER_IP}" << 'EOF'
cd /tmp/sss-client

# Create necessary directories
sudo mkdir -p /opt/sss/daily-files
sudo chmod 755 /opt/sss/daily-files

# Stop existing container if running
sudo docker-compose -f docker-compose-client.yml down || true

# Build and start client container
sudo docker-compose -f docker-compose-client.yml up -d --build

# Wait for container to start
echo "⏳ Waiting for client container to start..."
sleep 10

# Test health check
echo "🔍 Testing client connectivity to storage servers..."
if sudo docker exec sss-client sss-crypto-tool health-check; then
    echo "✅ Client deployed successfully and can reach storage servers!"
else
    echo "⚠️  Client deployed but cannot reach storage servers."
    echo "   Please verify storage servers are running and accessible."
fi

# Create convenience scripts
echo "📜 Creating system commands..."
sudo tee /usr/local/bin/sss-process-daily > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
DATE=${1:-$(date +%Y-%m-%d)}
echo "Processing daily files for date: $DATE"
sudo docker exec sss-client /scripts/client-encrypt-daily.sh "$DATE"
SCRIPT_EOF

sudo tee /usr/local/bin/sss-decrypt-view > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
DATE=${1:-$(date +%Y-%m-%d)}
echo "Decrypting and viewing data for date: $DATE"
sudo docker exec sss-client /scripts/client-decrypt-view.sh "$DATE"
SCRIPT_EOF

sudo chmod +x /usr/local/bin/sss-process-daily
sudo chmod +x /usr/local/bin/sss-decrypt-view

echo "✅ Client Server deployed and configured"
EOF

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "🎉 Client server deployment complete!"
echo ""
echo "📋 Usage commands on client server:"
echo "# Place daily files in:"
echo "sudo cp attacker_file.json /opt/sss/daily-files/"
echo ""
echo "# Process daily files:"
echo "sss-process-daily [YYYY-MM-DD]"
echo ""
echo "# Decrypt and view data:"
echo "sss-decrypt-view [YYYY-MM-DD]"
echo ""
echo "# Test security:"
echo "sudo docker exec sss-client /scripts/comprehensive-security-test.sh"