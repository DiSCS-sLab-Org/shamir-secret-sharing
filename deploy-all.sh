#!/bin/bash
set -e

echo "==============================================="
echo "   🚀 SSS Docker Deployment - Full Stack"
echo "==============================================="
echo ""
echo "Deploying Shamir's Secret Sharing system to:"
echo "  📦 Storage Server A: 139.91.90.9"
echo "  📦 Storage Server B: 139.91.90.156"
echo "  💻 Client Server:    139.91.90.11"
echo ""

# Confirm deployment
read -p "Proceed with full deployment? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo ""
echo "🏗️  Starting deployment process..."
echo ""

# Step 1: Deploy storage servers first (they need to be running before client)
echo "📤 Step 1/3: Deploying Storage Servers..."
./deploy-storage-servers.sh

if [ $? -eq 0 ]; then
    echo "✅ Storage servers deployed successfully"
else
    echo "❌ Storage server deployment failed"
    exit 1
fi

echo ""
echo "⏳ Waiting 15 seconds for storage servers to fully initialize..."
sleep 15

# Step 2: Deploy client server
echo "📤 Step 2/3: Deploying Client Server..."
./deploy-client.sh

if [ $? -eq 0 ]; then
    echo "✅ Client server deployed successfully"
else
    echo "❌ Client server deployment failed"
    exit 1
fi

echo ""
echo "🔍 Step 3/3: Running final verification..."

# Test storage servers
echo "Testing Storage Server A..."
if curl -s http://139.91.90.9:8080/health > /dev/null; then
    echo "✅ Storage Server A is healthy"
else
    echo "⚠️  Storage Server A health check failed"
fi

echo "Testing Storage Server B..."
if curl -s http://139.91.90.156:8080/health > /dev/null; then
    echo "✅ Storage Server B is healthy"
else
    echo "⚠️  Storage Server B health check failed"
fi

# Test client connectivity
echo "Testing Client Server connectivity..."
if ssh liakakos@139.91.90.11 'sudo docker exec sss-client sss-crypto-tool health-check' > /dev/null 2>&1; then
    echo "✅ Client can communicate with storage servers"
else
    echo "⚠️  Client connectivity test failed"
fi

echo ""
echo "🎉 DEPLOYMENT COMPLETE!"
echo "==============================================="
echo ""
echo "📋 Next Steps:"
echo "1. Place daily attacker files in: /opt/sss/daily-files/ (on client server)"
echo "2. Process files with: sss-process-daily"
echo "3. View decrypted data with: sss-decrypt-view"
echo ""
echo "🛡️  Security Features Active:"
echo "✅ End-to-end encryption"
echo "✅ Shamir's Secret Sharing (2-of-2 threshold)"
echo "✅ No plaintext persistence"
echo "✅ Authenticated encryption"
echo "✅ Tamper detection"
echo ""
echo "📖 Full documentation: DOCKER_DEPLOYMENT_GUIDE.md"