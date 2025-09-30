#!/bin/bash
set -e

# Configuration
STORAGE_SERVER_A_IP="139.91.90.9"
STORAGE_SERVER_B_IP="139.91.90.156"
CLIENT_SERVER_IP="139.91.90.11"
USER="liakakos"

echo "==============================================="
echo "   📤 SSS File Upload Script"
echo "==============================================="
echo ""
echo "Target Servers:"
echo "  📦 Storage Server A: $STORAGE_SERVER_A_IP"
echo "  📦 Storage Server B: $STORAGE_SERVER_B_IP"
echo "  💻 Client Server:    $CLIENT_SERVER_IP"
echo ""

# Confirm upload
read -p "Proceed with file upload? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Upload cancelled"
    exit 1
fi

echo ""
echo "📦 Uploading files to Storage Server A..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" 'mkdir -p /tmp/sss-storage'
scp Dockerfile.server "${USER}@${STORAGE_SERVER_A_IP}:/tmp/sss-storage/"
scp docker-compose-server-a.yml "${USER}@${STORAGE_SERVER_A_IP}:/tmp/sss-storage/"
scp -r crypto-tools "${USER}@${STORAGE_SERVER_A_IP}:/tmp/sss-storage/server"
echo "✅ Storage Server A files uploaded"

echo ""
echo "📦 Uploading files to Storage Server B..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" 'mkdir -p /tmp/sss-storage'
scp Dockerfile.server "${USER}@${STORAGE_SERVER_B_IP}:/tmp/sss-storage/"
scp docker-compose-server-b.yml "${USER}@${STORAGE_SERVER_B_IP}:/tmp/sss-storage/"
scp -r crypto-tools "${USER}@${STORAGE_SERVER_B_IP}:/tmp/sss-storage/server"
echo "✅ Storage Server B files uploaded"

echo ""
echo "📦 Uploading files to Client Server..."
ssh "${USER}@${CLIENT_SERVER_IP}" 'mkdir -p /tmp/sss-client/crypto-tools /tmp/sss-client/scripts'
scp Dockerfile.client "${USER}@${CLIENT_SERVER_IP}:/tmp/sss-client/"
scp docker-compose-client.yml "${USER}@${CLIENT_SERVER_IP}:/tmp/sss-client/"
scp -r crypto-tools/* "${USER}@${CLIENT_SERVER_IP}:/tmp/sss-client/crypto-tools/"
scp -r scripts/* "${USER}@${CLIENT_SERVER_IP}:/tmp/sss-client/scripts/"
echo "✅ Client Server files uploaded"

echo ""
echo "🎉 All files uploaded successfully!"
echo ""
echo "📋 Next steps:"
echo "1. On Storage Server A ($STORAGE_SERVER_A_IP):"
echo "   cd /tmp/sss-storage && docker-compose -f docker-compose-server-a.yml up -d --build"
echo ""
echo "2. On Storage Server B ($STORAGE_SERVER_B_IP):"
echo "   cd /tmp/sss-storage && docker-compose -f docker-compose-server-b.yml up -d --build"
echo ""
echo "3. On Client Server ($CLIENT_SERVER_IP):"
echo "   cd /tmp/sss-client && docker-compose -f docker-compose-client.yml up -d --build"
echo ""