#!/bin/bash
set -e

# SSS System - Cleanup Script
# This script stops and removes all containers and deployment directories
# Usage: ./cleanup.sh [tmp|opt]

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
    echo "📍 Cleanup mode: PRODUCTION (~/ home directory)"
else
    STORAGE_BASE_DIR="/tmp/sss-storage"
    CLIENT_BASE_DIR="/tmp/sss-client"
    USE_SUDO=""
    echo "📍 Cleanup mode: TESTING (/tmp)"
fi

echo "==============================================="
echo "   🧹 SSS Cleanup Script"
echo "==============================================="
echo ""
echo "This script will:"
echo "  1. Stop and remove all containers"
echo "  2. Remove deployment directories"
echo "  3. Clean up Docker images (optional)"
echo ""
echo "Target Servers:"
echo "  📦 Storage Server A: $STORAGE_SERVER_A_IP → $STORAGE_BASE_DIR"
echo "  📦 Storage Server B: $STORAGE_SERVER_B_IP → $STORAGE_BASE_DIR"
echo "  💻 Client Server:    $CLIENT_SERVER_IP → $CLIENT_BASE_DIR"
echo ""

# Confirm cleanup
read -p "⚠️  Proceed with cleanup? This will delete all data! [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Cleaning Storage Server A"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🛑 Stopping containers..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-a.yml down 2>/dev/null || true"

echo "🗑️  Removing deployment directory..."
ssh "${USER}@${STORAGE_SERVER_A_IP}" "rm -rf $STORAGE_BASE_DIR"

echo "✅ Storage Server A cleaned"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Cleaning Storage Server B"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🛑 Stopping containers..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" "cd $STORAGE_BASE_DIR && docker-compose -f docker-compose-server-b.yml down 2>/dev/null || true"

echo "🗑️  Removing deployment directory..."
ssh "${USER}@${STORAGE_SERVER_B_IP}" "rm -rf $STORAGE_BASE_DIR"

echo "✅ Storage Server B cleaned"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Cleaning Client Server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🛑 Stopping containers..."
ssh "${USER}@${CLIENT_SERVER_IP}" "cd $CLIENT_BASE_DIR && docker-compose -f docker-compose-client.yml down 2>/dev/null || true"

echo "🗑️  Removing deployment directory..."
ssh "${USER}@${CLIENT_SERVER_IP}" "rm -rf $CLIENT_BASE_DIR"

echo "✅ Client Server cleaned"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Optional Docker Image Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Remove Docker images? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing Docker images from Storage Server A..."
    ssh "${USER}@${STORAGE_SERVER_A_IP}" "docker rmi sss-storage-server:latest 2>/dev/null || true"

    echo "🗑️  Removing Docker images from Storage Server B..."
    ssh "${USER}@${STORAGE_SERVER_B_IP}" "docker rmi sss-storage-server:latest 2>/dev/null || true"

    echo "🗑️  Removing Docker images from Client Server..."
    ssh "${USER}@${CLIENT_SERVER_IP}" "docker rmi sss-client:latest 2>/dev/null || true"

    echo "✅ Docker images removed"
else
    echo "⏭️  Skipping Docker image removal"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 CLEANUP COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Summary:"
echo "  ✅ All containers stopped and removed"
echo "  ✅ Deployment directories deleted"
echo "  ✅ System cleaned"
echo ""
echo "💡 Note: Local .env files are preserved for redeployment"
echo ""
