# SSS System - Deployment Guide

## Quick Start

### One-Command Deployment (Recommended)

```bash
cd /home/djenti/C-SOC/sss-docker-lab
./deploy-with-auth.sh
```

This script will:
1. ✅ Generate fresh API keys
2. ✅ Upload all code files to all servers
3. ✅ Create environment files
4. ✅ Build and start Docker containers
5. ✅ Test authentication

**Total time:** ~3-5 minutes

---

## What Gets Deployed

### Storage Server A (139.91.90.9)
```
/tmp/sss-storage/
├── storage-server/
│   ├── main.go          ← HTTP storage server with auth
│   └── go.mod
├── Dockerfile.server
├── docker-compose-server-a.yml
├── server-a.env         ← Contains HASH(API_KEY_A)
└── data/                ← Volume for stored files
```

### Storage Server B (139.91.90.156)
```
/tmp/sss-storage/
├── storage-server/
│   ├── main.go          ← HTTP storage server with auth
│   └── go.mod
├── Dockerfile.server
├── docker-compose-server-b.yml
├── server-b.env         ← Contains HASH(API_KEY_B)
└── data/                ← Volume for stored files
```

### Client Server (139.91.90.11)
```
/tmp/sss-client/
├── crypto-tools/
│   ├── main.go          ← Crypto tool with auth support
│   ├── go.mod
│   └── go.sum
├── scripts/
│   ├── client-encrypt-daily.sh
│   └── client-decrypt-view.sh
├── Dockerfile.client
├── docker-compose-client.yml
├── client.env           ← Contains plaintext API keys (SECRET!)
└── daily-files/         ← Input directory for IP lists
```

---

## Manual Deployment (Step by Step)

If you prefer manual control or need to debug:

### Step 1: Generate API Keys

```bash
cd /home/djenti/C-SOC/sss-docker-lab
./generate-api-keys.sh
```

This creates:
- `server-a.env` - Hash for Server A
- `server-b.env` - Hash for Server B
- `client.env` - Plaintext keys for Client

**Save the output!** You'll need the keys if you lose the files.

---

### Step 2: Deploy Storage Server A

```bash
# Upload files
scp -r storage-server liakakos@139.91.90.9:/tmp/sss-storage/
scp Dockerfile.server liakakos@139.91.90.9:/tmp/sss-storage/
scp docker-compose-server-a.yml liakakos@139.91.90.9:/tmp/sss-storage/
scp server-a.env liakakos@139.91.90.9:/tmp/sss-storage/

# SSH and deploy
ssh liakakos@139.91.90.9
cd /tmp/sss-storage

# Build and start with authentication
docker-compose -f docker-compose-server-a.yml --env-file server-a.env down
docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d --build

# Check logs
docker logs sss-storage-server-a
# Should see: "Authentication: ENABLED"

# Test
curl http://localhost:8080/health
# Should return: {"status":"healthy","server_id":"A"}

# Test auth (should fail)
curl http://localhost:8080/retrieve?filename=test.bin
# Should return: Unauthorized
```

---

### Step 3: Deploy Storage Server B

```bash
# Upload files
scp -r storage-server liakakos@139.91.90.156:/tmp/sss-storage/
scp Dockerfile.server liakakos@139.91.90.156:/tmp/sss-storage/
scp docker-compose-server-b.yml liakakos@139.91.90.156:/tmp/sss-storage/
scp server-b.env liakakos@139.91.90.156:/tmp/sss-storage/

# SSH and deploy
ssh liakakos@139.91.90.156
cd /tmp/sss-storage

# Build and start with authentication
docker-compose -f docker-compose-server-b.yml --env-file server-b.env down
docker-compose -f docker-compose-server-b.yml --env-file server-b.env up -d --build

# Check logs
docker logs sss-storage-server-b
# Should see: "Authentication: ENABLED"

# Test
curl http://localhost:8080/health
curl http://localhost:8080/retrieve?filename=test.bin
# Should return: Unauthorized
```

---

### Step 4: Deploy Client Server

```bash
# Upload files
scp -r crypto-tools liakakos@139.91.90.11:/tmp/sss-client/
scp -r scripts liakakos@139.91.90.11:/tmp/sss-client/
scp Dockerfile.client liakakos@139.91.90.11:/tmp/sss-client/
scp docker-compose-client.yml liakakos@139.91.90.11:/tmp/sss-client/
scp client.env liakakos@139.91.90.11:/tmp/sss-client/

# SSH and deploy
ssh liakakos@139.91.90.11
cd /tmp/sss-client

# Secure the API keys file
chmod 600 client.env

# Build and start with API keys
docker-compose -f docker-compose-client.yml --env-file client.env down
docker-compose -f docker-compose-client.yml --env-file client.env up -d --build

# Check logs
docker logs sss-client

# Test authentication
docker exec sss-client sss-crypto-tool health-check
# Should see:
# ✅ Server A (http://139.91.90.9:8080): healthy
# ✅ Server B (http://139.91.90.156:8080): healthy
```

---

## Testing the System

### Test 1: Authentication Verification

```bash
# From any machine - test without auth (should fail)
curl http://139.91.90.9:8080/retrieve?filename=test.bin
# Expected: {"error":"Unauthorized: Missing API key"}

curl http://139.91.90.156:8080/retrieve?filename=test.bin
# Expected: {"error":"Unauthorized: Missing API key"}
```

✅ **Success:** Servers reject unauthenticated requests

---

### Test 2: Client Health Check

```bash
ssh liakakos@139.91.90.11
docker exec sss-client sss-crypto-tool health-check
```

**Expected output:**
```
=== Storage Server Health Check ===
✅ Server A (http://139.91.90.9:8080): healthy
✅ Server B (http://139.91.90.156:8080): healthy
```

✅ **Success:** Client authenticates to both servers

---

### Test 3: Full Encryption/Decryption Workflow

```bash
ssh liakakos@139.91.90.11

# Create test file
docker exec sss-client sh -c 'echo '\''["192.168.1.100", "10.0.0.5", "172.16.0.20"]'\'' > /daily-files/attackers_2025-10-02.json'

# Verify file exists
docker exec sss-client cat /daily-files/attackers_2025-10-02.json

# Encrypt and distribute
docker exec sss-client /scripts/client-encrypt-daily.sh 2025-10-02
```

**Expected output:**
```
=== Client Server: Daily Encryption Process for 2025-10-02 ===
📄 Processing file: /daily-files/attackers_2025-10-02.json
🔍 Checking storage server connectivity...
=== Storage Server Health Check ===
✅ Server A (http://139.91.90.9:8080): healthy
✅ Server B (http://139.91.90.156:8080): healthy
🔑 Generating DEK...
DEK generated: Ql0QOWyJw97PuuWQ... (truncated for display)
🔒 Encrypting attacker IP data...
📤 Storing encrypted bundle on both storage servers...
✅ Stored bundle_2025-10-02.json on Server A
✅ Stored bundle_2025-10-02.json on Server B
✂️  Splitting DEK with Shamir's Secret Sharing (k=2, n=2)...
📤 Storing share A on Storage Server A...
✅ Stored share_A_2025-10-02.bin on Server A
📤 Storing share B on Storage Server B...
✅ Stored share_B_2025-10-02.bin on Server B
🗑️  Deleting processed file...
✅ Daily encryption process complete for 2025-10-02

Files created on storage servers:
  - Storage Server A & B: bundle_2025-10-02.json
  - Storage Server A only: share_A_2025-10-02.bin
  - Storage Server B only: share_B_2025-10-02.bin

🗑️  Original file deleted after processing
```

**Now verify original file is deleted:**
```bash
docker exec sss-client ls /daily-files/
# Should be empty or not show attackers_2025-10-02.json
```

**Check storage servers have the files:**
```bash
# Server A
ssh liakakos@139.91.90.9 'ls -lh /tmp/sss-storage/data/'
# Should show: bundle_2025-10-02.json, share_A_2025-10-02.bin

# Server B
ssh liakakos@139.91.90.156 'ls -lh /tmp/sss-storage/data/'
# Should show: bundle_2025-10-02.json, share_B_2025-10-02.bin
```

**Verify Server A does NOT have share_B:**
```bash
ssh liakakos@139.91.90.9 'ls /tmp/sss-storage/data/ | grep share_B'
# Should return nothing (empty)
```

**Verify Server B does NOT have share_A:**
```bash
ssh liakakos@139.91.90.156 'ls /tmp/sss-storage/data/ | grep share_A'
# Should return nothing (empty)
```

✅ **Success:** Shares properly separated

**Now decrypt and view:**
```bash
docker exec sss-client /scripts/client-decrypt-view.sh 2025-10-02
```

**Expected output:**
```
=== Client Server: Decrypt and View Attacker IPs for 2025-10-02 ===
🔍 Checking storage server connectivity...
=== Storage Server Health Check ===
✅ Server A (http://139.91.90.9:8080): healthy
✅ Server B (http://139.91.90.156:8080): healthy
📥 Retrieving share A from Storage Server A...
📥 Retrieving share B from Storage Server B...
🔑 Combining shares to reconstruct DEK...
DEK reconstructed successfully
📥 Retrieving encrypted bundle from Storage Server A...
🔓 Decrypting bundle...

🎯 Attacker IP addresses for 2025-10-02:
===============================================
[
  "192.168.1.100",
  "10.0.0.5",
  "172.16.0.20"
]
📊 Total attacker IPs: 3

🎉 Decryption and viewing successful!
```

✅ **Success:** Full workflow complete!

---

## Verifying Security

### Test: Cross-Server Attack Prevention

Simulate an attacker who compromised Server A trying to get Share B:

```bash
# SSH to Server A (simulate compromise)
ssh liakakos@139.91.90.9

# Try to retrieve Share B from Server B without proper API key
curl http://139.91.90.156:8080/retrieve?filename=share_B_2025-10-02.bin
# Expected: Unauthorized: Missing API key

# Try with the hash (all Server A knows)
HASH=$(grep SERVER_A_API_KEY_HASH /tmp/sss-storage/server-a.env | cut -d= -f2)
curl -H "Authorization: Bearer $HASH" http://139.91.90.156:8080/retrieve?filename=share_B_2025-10-02.bin
# Expected: Unauthorized: Invalid API key
```

✅ **Success:** Cross-server attack blocked!

---

## Monitoring and Logs

### View Authentication Logs

**Storage Server A:**
```bash
ssh liakakos@139.91.90.9
docker logs sss-storage-server-a | grep -E "AUTHENTICATED|UNAUTHORIZED"
```

**Storage Server B:**
```bash
ssh liakakos@139.91.90.156
docker logs sss-storage-server-b | grep -E "AUTHENTICATED|UNAUTHORIZED"
```

**Look for:**
- `AUTHENTICATED: Request from <IP>` - Successful auth
- `UNAUTHORIZED: Invalid API key from <IP>` - Failed auth attempt
- Repeated failures from unexpected IPs

---

## Troubleshooting

### Problem: "API_KEY_HASH environment variable is required"

**Cause:** Container started without environment file

**Fix:**
```bash
# Make sure to use --env-file flag
docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d
```

---

### Problem: "Authentication failed: Invalid or missing API key"

**Cause:** Client doesn't have API keys or wrong keys

**Check:**
```bash
ssh liakakos@139.91.90.11
docker exec sss-client env | grep API_KEY
# Should show:
# STORAGE_SERVER_A_API_KEY=...
# STORAGE_SERVER_B_API_KEY=...
```

**Fix:**
```bash
# Recreate container with correct env file
cd /tmp/sss-client
docker-compose -f docker-compose-client.yml --env-file client.env down
docker-compose -f docker-compose-client.yml --env-file client.env up -d
```

---

### Problem: Storage server crashes on startup

**Check logs:**
```bash
docker logs sss-storage-server-a
```

**Common issues:**
- Missing `API_KEY_HASH` in environment
- Invalid hash format
- Port 8080 already in use

---

### Problem: Servers accept requests without auth

**Check environment:**
```bash
ssh liakakos@139.91.90.9
docker exec sss-storage-server-a env | grep API_KEY_HASH
# Should show the hash
```

**If empty, container wasn't started with env file:**
```bash
cd /tmp/sss-storage
docker-compose -f docker-compose-server-a.yml --env-file server-a.env down
docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d
```

---

## Redeployment (Code Changes)

If you modify code and need to redeploy:

```bash
# Option 1: Full redeployment (generates new keys)
./deploy-with-auth.sh

# Option 2: Keep existing keys, just update code
./upload-files.sh  # If you still have this script

# Or manually:
# Update specific files, then rebuild containers
scp storage-server/main.go liakakos@139.91.90.9:/tmp/sss-storage/storage-server/
ssh liakakos@139.91.90.9 'cd /tmp/sss-storage && docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d --build'
```

---

## Security Checklist

Before production deployment:

- [ ] API keys generated (64 hex chars each)
- [ ] Server A only has `HASH(API_KEY_A)` in server-a.env
- [ ] Server B only has `HASH(API_KEY_B)` in server-b.env
- [ ] Client has both plaintext keys in client.env
- [ ] client.env has 600 permissions
- [ ] Tested: Servers reject unauthenticated requests
- [ ] Tested: Client health-check succeeds
- [ ] Tested: Full encrypt/decrypt workflow
- [ ] Tested: Cross-server attack prevention
- [ ] Verified: Original plaintext files deleted after encryption
- [ ] Verified: Shares properly separated (A on Server A, B on Server B)
- [ ] Firewall rules configured (optional but recommended)
- [ ] HTTPS/TLS enabled (optional but recommended)
- [ ] Backup of client.env stored securely
- [ ] Local .env files deleted from deployment machine

---

## Quick Reference Commands

### Health Checks
```bash
# From client
ssh liakakos@139.91.90.11 'docker exec sss-client sss-crypto-tool health-check'
```

### Process Daily File
```bash
ssh liakakos@139.91.90.11
docker exec sss-client /scripts/client-encrypt-daily.sh YYYY-MM-DD
```

### Decrypt and View
```bash
ssh liakakos@139.91.90.11
docker exec sss-client /scripts/client-decrypt-view.sh YYYY-MM-DD
```

### View Logs
```bash
# Storage A
ssh liakakos@139.91.90.9 'docker logs sss-storage-server-a'

# Storage B
ssh liakakos@139.91.90.156 'docker logs sss-storage-server-b'

# Client
ssh liakakos@139.91.90.11 'docker logs sss-client'
```

### Check Running Containers
```bash
ssh liakakos@139.91.90.9 'docker ps'
ssh liakakos@139.91.90.156 'docker ps'
ssh liakakos@139.91.90.11 'docker ps'
```

### Restart Everything
```bash
# Storage A
ssh liakakos@139.91.90.9 'cd /tmp/sss-storage && docker-compose -f docker-compose-server-a.yml --env-file server-a.env restart'

# Storage B
ssh liakakos@139.91.90.156 'cd /tmp/sss-storage && docker-compose -f docker-compose-server-b.yml --env-file server-b.env restart'

# Client
ssh liakakos@139.91.90.11 'cd /tmp/sss-client && docker-compose -f docker-compose-client.yml --env-file client.env restart'
```

---

## Support

For issues or questions:
1. Check logs with `docker logs <container-name>`
2. Review `AUTHENTICATION_GUIDE.md` for auth troubleshooting
3. Review `SECURITY_DOCUMENTATION.md` for architecture details

---

## Summary

**One-command deployment:**
```bash
./deploy-with-auth.sh
```

**Then test:**
```bash
ssh liakakos@139.91.90.11
docker exec sss-client sh -c 'echo '\''["1.2.3.4"]'\'' > /daily-files/attackers_$(date +%Y-%m-%d).json'
docker exec sss-client /scripts/client-encrypt-daily.sh $(date +%Y-%m-%d)
docker exec sss-client /scripts/client-decrypt-view.sh $(date +%Y-%m-%d)
```

✅ **Done!**
