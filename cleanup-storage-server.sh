#!/bin/bash
set -e

echo "🧹 SSS Storage Server Cleanup"
echo "=============================="

# Stop and remove any running containers
echo "🛑 Stopping Docker containers..."
sudo docker stop csoc-serverA csoc-serverB 2>/dev/null || true
sudo docker rm csoc-serverA csoc-serverB 2>/dev/null || true

# Remove Docker images
echo "🗑️  Removing Docker images..."
sudo docker rmi csoc-server:latest 2>/dev/null || true
sudo docker rmi sss-server:latest 2>/dev/null || true

# Remove all deployment files
echo "📁 Removing deployment files..."
sudo rm -rf /tmp/sss-storage
sudo rm -rf /opt/sss

# Clean up Docker system (remove unused images, containers, networks, build cache)
echo "🧽 Cleaning Docker system..."
sudo docker system prune -a -f
sudo docker volume prune -f

# Remove any docker-compose files that might be elsewhere
find /tmp -name "*sss*" -type d -exec sudo rm -rf {} + 2>/dev/null || true
find /tmp -name "*docker-compose*server*" -type f -exec sudo rm -f {} + 2>/dev/null || true

echo "✅ Storage server cleanup complete!"
echo ""
echo "🔍 Verification:"
echo "Containers: $(sudo docker ps -a | grep -E 'csoc-server|sss-server' | wc -l || echo 0)"
echo "Images: $(sudo docker images | grep -E 'csoc-server|sss-server' | wc -l || echo 0)"
echo "Files in /opt/sss: $(ls /opt/sss 2>/dev/null | wc -l || echo 0)"
echo "Files in /tmp/sss-storage: $(ls /tmp/sss-storage 2>/dev/null | wc -l || echo 0)"