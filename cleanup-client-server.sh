#!/bin/bash
set -e

echo "🧹 SSS Client Server Cleanup"
echo "============================="

# Stop and remove any running containers
echo "🛑 Stopping Docker containers..."
sudo docker stop sss-client 2>/dev/null || true
sudo docker rm sss-client 2>/dev/null || true

# Remove Docker images
echo "🗑️  Removing Docker images..."
sudo docker rmi sss-client:latest 2>/dev/null || true
sudo docker rmi csoc-crypto-cli:latest 2>/dev/null || true

# Remove all deployment and data files
echo "📁 Removing deployment and data files..."
sudo rm -rf /tmp/sss-client
sudo rm -rf /opt/sss

# Remove system commands
echo "🔧 Removing system commands..."
sudo rm -f /usr/local/bin/sss-process-daily
sudo rm -f /usr/local/bin/sss-decrypt-view

# Clean up Docker system (remove unused images, containers, networks, build cache)
echo "🧽 Cleaning Docker system..."
sudo docker system prune -a -f
sudo docker volume prune -f

# Remove any docker-compose files that might be elsewhere
find /tmp -name "*sss*" -type d -exec sudo rm -rf {} + 2>/dev/null || true
find /tmp -name "*docker-compose*client*" -type f -exec sudo rm -f {} + 2>/dev/null || true

echo "✅ Client server cleanup complete!"
echo ""
echo "🔍 Verification:"
echo "Containers: $(sudo docker ps -a | grep -E 'sss-client|csoc-crypto' | wc -l || echo 0)"
echo "Images: $(sudo docker images | grep -E 'sss-client|csoc-crypto' | wc -l || echo 0)"
echo "Files in /opt/sss: $(ls /opt/sss 2>/dev/null | wc -l || echo 0)"
echo "Files in /tmp/sss-client: $(ls /tmp/sss-client 2>/dev/null | wc -l || echo 0)"
echo "System commands: $(ls /usr/local/bin/sss-* 2>/dev/null | wc -l || echo 0)"