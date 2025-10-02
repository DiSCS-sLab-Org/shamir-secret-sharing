# SSS Docker Deployment Guide

This guide provides step-by-step instructions for deploying the Shamir's Secret Sharing (SSS) system using Docker across your three servers.

## Prerequisites

Ensure Docker and Docker Compose are installed on all servers:

```bash
# Install Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

**Note:** Log out and back in after adding your user to the docker group.

## Server Configuration

- **Storage Server A**: 139.91.90.9:8080
- **Storage Server B**: 139.91.90.156:8080
- **Client Server**: 139.91.90.11

## Deployment Steps

### Step 1: Deploy Storage Server A (139.91.90.9)

```bash
# Copy project to server
scp -r /home/djenti/C-SOC/sss-docker-lab liakakos@139.91.90.9:/tmp/

# SSH to server
ssh liakakos@139.91.90.9

# Deploy
cd /tmp/sss-docker-lab
sudo ./deploy-docker-storage-server.sh A

# Verify deployment
curl http://localhost:8080/health
```

### Step 2: Deploy Storage Server B (139.91.90.156)

```bash
# Copy project to server
scp -r /home/djenti/C-SOC/sss-docker-lab liakakos@139.91.90.156:/tmp/

# SSH to server
ssh liakakos@139.91.90.156

# Deploy
cd /tmp/sss-docker-lab
sudo ./deploy-docker-storage-server.sh B

# Verify deployment
curl http://localhost:8080/health
```

### Step 3: Deploy Client Server (139.91.90.11)

```bash
# Copy project to server
scp -r /home/djenti/C-SOC/sss-docker-lab liakakos@139.91.90.11:/tmp/

# SSH to server
ssh liakakos@139.91.90.11

# Deploy (automatically configures server IPs)
cd /tmp/sss-docker-lab
sudo ./deploy-docker-client.sh 139.91.90.9 139.91.90.156

# Test connectivity
sss-process-daily --help
```

## Usage

### Processing Daily Files

1. **Place files** in `/opt/sss/daily-files/` on the client server:
```bash
# Example daily file: attackers_2025-09-29.json
sudo tee /opt/sss-docker-lab/daily-files/attackers_$(date +%Y-%m-%d).json << 'EOF'
[
  {
    "ip": "192.168.1.100",
    "attacks": 45,
    "severity": "high",
    "first_seen": "2025-09-29T08:15:30Z",
    "last_seen": "2025-09-29T18:42:15Z",
    "country": "CN",
    "attack_types": ["brute_force", "port_scan"]
  }
]
EOF
```

2. **Process files manually**:
```bash
# Process today's files
sss-process-daily

# Process specific date
sss-process-daily 2025-09-29
```

3. **View encrypted data**:
```bash
# Decrypt and view today's data
sss-decrypt-view

# Decrypt specific date
sss-decrypt-view 2025-09-29
```

4. **Enable automatic processing**:
```bash
# Enable daily timer (runs at 2 AM)
sudo systemctl start sss-daily-process.timer
sudo systemctl status sss-daily-process.timer
```

## Management Commands

### Container Management

**Storage Servers:**
```bash
# Check status
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-server-a.yml ps

# View logs
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-server-a.yml logs -f

# Restart
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-server-a.yml restart

# Stop
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-server-a.yml down
```

**Client:**
```bash
# Check status
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-client.yml ps

# Interactive shell
sudo docker exec -it sss-client /bin/bash

# View logs
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-client.yml logs -f
```

### Health Checks

**Storage Servers:**
```bash
curl http://localhost:8080/health
curl http://localhost:8080/list
```

**Client Connectivity:**
```bash
sudo docker exec sss-client sss-crypto-tool health-check
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
sudo docker-compose logs

# Rebuild container
sudo docker-compose down
sudo docker-compose up -d --build

# Check system resources
docker system df
docker system prune  # Clean up if needed
```

### Network Issues
```bash
# Test connectivity between servers
ping 139.91.90.9
ping 139.91.90.156

# Check firewall
sudo ufw status
sudo iptables -L

# Test port accessibility
telnet 139.91.90.9 8080
```

### Storage Issues
```bash
# Check disk space
df -h

# Check data directory permissions
ls -la /opt/sss/data
sudo chown -R 1000:1000 /opt/sss/data
```

## Security Notes

1. **Firewall Configuration**: Ensure port 8080 is only accessible from your client server
2. **Data Encryption**: All data is encrypted before storage - storage servers never see plaintext
3. **Key Management**: Encryption keys are split using Shamir's Secret Sharing (2-of-2)
4. **Container Security**: Containers run with minimal privileges and non-root users where possible

## File Structure

```
/opt/sss-docker-lab/          # Docker project files
├── docker-compose-*.yml      # Service definitions
├── Dockerfile.*             # Container build instructions
└── scripts/                 # Processing scripts

/opt/sss/daily-files/        # Input files (plaintext)
/opt/sss/processed/          # Processed files archive
/opt/sss/data/              # Storage server data
```

## Cleanup (if needed)

```bash
# Stop and remove all containers
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-server-a.yml down
sudo docker-compose -f /opt/sss-docker-lab/docker-compose-client.yml down

# Remove data (WARNING: This deletes all stored data!)
sudo rm -rf /opt/sss/

# Remove timer
sudo systemctl stop sss-daily-process.timer
sudo systemctl disable sss-daily-process.timer
sudo rm /etc/systemd/system/sss-daily-process.*
sudo systemctl daemon-reload
```

## Benefits of Docker Deployment

✅ **No Compatibility Issues**: Containers include all dependencies
✅ **Consistent Environment**: Same runtime across all servers
✅ **Easy Updates**: Simply rebuild and restart containers
✅ **Isolation**: Services run in isolated environments
✅ **Resource Management**: Built-in resource limits and monitoring
✅ **Health Checks**: Automatic container health monitoring
✅ **Simple Rollback**: Easy to revert to previous versions




  # 1. Create a test file
  docker exec sss-client sh -c 'echo '\''["192.168.1.100", "10.0.0.5", "172.16.0.20"]'\'' > /daily-files/attackers_2025-09-30.json'

  # 2. Run the encryption process
  docker exec sss-client /scripts/client-encrypt-daily.sh 2025-09-30

  # 3. Decrypt and view (without saving plaintext)
  docker exec sss-client /scripts/client-decrypt-view.sh 2025-09-30

