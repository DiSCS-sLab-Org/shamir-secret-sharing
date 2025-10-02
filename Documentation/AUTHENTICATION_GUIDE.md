# API Key Authentication Guide

## Overview

This system now uses **separate API key authentication** for each storage server to prevent cross-server attacks.

## Security Model

```
┌─────────────────────────────────────────────────────────────┐
│                        Client Server                         │
│  Has: API_KEY_A (plaintext) + API_KEY_B (plaintext)         │
│  Can: Authenticate to both Server A and Server B            │
└──────────────────┬─────────────────────┬────────────────────┘
                   │                     │
         Uses API_KEY_A         Uses API_KEY_B
                   │                     │
                   ▼                     ▼
       ┌─────────────────┐   ┌─────────────────┐
       │  Storage A       │   │  Storage B      │
       │  Has: HASH(A)    │   │  Has: HASH(B)   │
       │  Cannot: Get B   │   │  Cannot: Get A  │
       └─────────────────┘   └─────────────────┘
```

### Key Security Properties

1. **Separate Keys**: Each storage server has its own unique API key
2. **Hash-Based Verification**: Servers only store SHA256 hashes of keys
3. **Zero Knowledge**: Server A doesn't know API_KEY_B, Server B doesn't know API_KEY_A
4. **Constant-Time Comparison**: Protection against timing attacks
5. **Bearer Token Format**: Standard Authorization header format

### Why This Matters

**Without Authentication (OLD):**
```bash
# Attacker compromises Server A
ssh attacker@server-a
curl http://139.91.90.156:8080/retrieve?filename=share_B_2025-09-30.bin
# ✅ Success - no authentication required
# Attacker now has both shares → can decrypt
```

**With Separate API Keys (NEW):**
```bash
# Attacker compromises Server A
ssh attacker@server-a
cat /tmp/sss-storage/server-a.env
# Shows: SERVER_A_API_KEY_HASH=abc123...
# This is the HASH, not the actual key

curl -H "Authorization: Bearer abc123..." http://139.91.90.156:8080/retrieve?filename=share_B_2025-09-30.bin
# ❌ FAIL - hash doesn't work as a key

# Attacker cannot get Share B → cannot decrypt
```

---

## Setup Instructions

### Step 1: Generate API Keys

```bash
cd /home/djenti/C-SOC/sss-docker-lab
./generate-api-keys.sh
```

This creates three files:
- `server-a.env` - Contains hash for Server A
- `server-b.env` - Contains hash for Server B
- `client.env` - Contains actual API keys for client

**Output Example:**
```
Storage Server A
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
API Key:  a1b2c3d4e5f6...  (64 hex chars)
Hash:     7f8a9b0c1d2e...  (64 hex chars)

Storage Server B
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
API Key:  f9e8d7c6b5a4...  (64 hex chars)
Hash:     3e4d5c6b7a8f...  (64 hex chars)
```

⚠️ **IMPORTANT**: Save this output securely, then delete it!

---

### Step 2: Deploy Environment Files

#### On Storage Server A (139.91.90.9):

```bash
# Upload server-a.env
scp server-a.env liakakos@139.91.90.9:/tmp/sss-storage/

# SSH to server
ssh liakakos@139.91.90.9
cd /tmp/sss-storage

# Verify file
cat server-a.env
# Should show: SERVER_A_API_KEY_HASH=...

# Rebuild with authentication
docker-compose -f docker-compose-server-a.yml --env-file server-a.env down
docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d --build

# Check logs
docker logs sss-storage-server-a
# Should see: "Authentication: ENABLED (API key hash: ...)"
```

#### On Storage Server B (139.91.90.156):

```bash
# Upload server-b.env
scp server-b.env liakakos@139.91.90.156:/tmp/sss-storage/

# SSH to server
ssh liakakos@139.91.90.156
cd /tmp/sss-storage

# Verify file
cat server-b.env
# Should show: SERVER_B_API_KEY_HASH=...

# Rebuild with authentication
docker-compose -f docker-compose-server-b.yml --env-file server-b.env down
docker-compose -f docker-compose-server-b.yml --env-file server-b.env up -d --build

# Check logs
docker logs sss-storage-server-b
# Should see: "Authentication: ENABLED (API key hash: ...)"
```

#### On Client Server (139.91.90.11):

```bash
# Upload client.env
scp client.env liakakos@139.91.90.11:/tmp/sss-client/

# SSH to server
ssh liakakos@139.91.90.11
cd /tmp/sss-client

# ⚠️ SECURE THE FILE - contains plaintext keys
chmod 600 client.env
cat client.env
# Should show: SERVER_A_API_KEY=... and SERVER_B_API_KEY=...

# Rebuild with API keys
docker-compose -f docker-compose-client.yml --env-file client.env down
docker-compose -f docker-compose-client.yml --env-file client.env up -d --build
```

---

### Step 3: Test Authentication

#### Test 1: Verify Authentication is Enabled

```bash
# From any machine, try accessing without auth
curl http://139.91.90.9:8080/retrieve?filename=test.bin
# Expected: {"error": "Unauthorized: Missing API key"}

curl http://139.91.90.156:8080/retrieve?filename=test.bin
# Expected: {"error": "Unauthorized: Missing API key"}
```

✅ **Success**: Servers reject unauthenticated requests

#### Test 2: Verify Client Can Authenticate

```bash
# On client server
ssh liakakos@139.91.90.11

# Health check (should work)
docker exec sss-client sss-crypto-tool health-check
# Expected:
# ✅ Server A (http://139.91.90.9:8080): healthy
# ✅ Server B (http://139.91.90.156:8080): healthy
```

✅ **Success**: Client successfully authenticates to both servers

#### Test 3: Full Encryption/Decryption Flow

```bash
# Create test file
docker exec sss-client sh -c 'echo '\''["1.2.3.4", "5.6.7.8"]'\'' > /daily-files/attackers_2025-10-01.json'

# Encrypt (will fail if auth broken)
docker exec sss-client /scripts/client-encrypt-daily.sh 2025-10-01
# Expected: Success with shares distributed

# Decrypt (will fail if auth broken)
docker exec sss-client /scripts/client-decrypt-view.sh 2025-10-01
# Expected: Display plaintext IPs
```

✅ **Success**: Full workflow works with authentication

---

## How Authentication Works

### Client → Server Flow

1. **Client Request**:
   ```http
   POST /store HTTP/1.1
   Host: 139.91.90.9:8080
   Authorization: Bearer a1b2c3d4e5f6...
   Content-Type: application/json

   {"filename": "share_A_2025-10-01.bin", "content": "..."}
   ```

2. **Server Verification**:
   ```go
   // Extract key from header
   providedKey := "a1b2c3d4e5f6..."

   // Hash the provided key
   providedHash := SHA256(providedKey)
   // = "7f8a9b0c1d2e..."

   // Compare with stored hash (constant-time)
   if providedHash == apiKeyHash {
       // ✅ Authenticated
   } else {
       // ❌ Unauthorized
   }
   ```

3. **Security Features**:
   - **SHA256 Hash**: Server stores hash, not plaintext key
   - **Constant-Time Comparison**: Uses `subtle.ConstantTimeCompare()` to prevent timing attacks
   - **Bearer Token**: Standard OAuth 2.0 format
   - **Audit Logging**: All auth attempts logged with IP and timestamp

---

## Attack Scenarios Analysis

### Scenario 1: Attacker Compromises Storage Server A

**What attacker finds:**
```bash
# On Server A
cat /tmp/sss-storage/server-a.env
SERVER_A_API_KEY_HASH=7f8a9b0c1d2e...

ls /tmp/sss-storage/data/
share_A_2025-10-01.bin  bundle_2025-10-01.json
```

**What attacker can do:**
- ✅ Read Share A (already on this server)
- ✅ Read encrypted bundles (already on this server)
- ✅ See the hash of API_KEY_A

**What attacker CANNOT do:**
- ❌ Derive API_KEY_A from hash (SHA256 is one-way)
- ❌ Authenticate to Server B (doesn't have API_KEY_B)
- ❌ Retrieve Share B from Server B
- ❌ Decrypt any data (needs both shares)

**Result:** 🛡️ **Attack Blocked** - Attacker stuck with useless fragments

---

### Scenario 2: Attacker Compromises Client Server

**What attacker finds:**
```bash
# On Client
cat /tmp/sss-client/client.env
SERVER_A_API_KEY=a1b2c3d4e5f6...
SERVER_B_API_KEY=f9e8d7c6b5a4...
```

**What attacker can do:**
- ✅ Authenticate to both Server A and Server B
- ✅ Retrieve all shares
- ✅ Retrieve all bundles
- ✅ Decrypt all data

**Result:** 🚨 **Full Compromise** - This is the trusted client, expected behavior

**Mitigation:**
- Harden client server security
- Use encrypted filesystem for client.env
- Monitor client access patterns
- Implement 2FA for SSH to client

---

### Scenario 3: Network Eavesdropper (No HTTPS)

**What attacker sees:**
```http
POST /store HTTP/1.1
Authorization: Bearer a1b2c3d4e5f6...
```

**What attacker can do:**
- ✅ Capture API_KEY_A from network traffic
- ✅ Replay requests to Server A

**What attacker CANNOT do:**
- ❌ Capture API_KEY_B (sent in different request to different server)

**Result:** ⚠️ **Partial Compromise** - Can impersonate client to one server only

**Mitigation:** Use HTTPS/TLS for all communication (recommended upgrade)

---

## Best Practices

### 1. Secure Storage of client.env

```bash
# On client server
chmod 600 /tmp/sss-client/client.env
chown root:root /tmp/sss-client/client.env

# Even better: use Docker secrets
docker secret create server_a_api_key -
# paste key, press Ctrl+D
```

### 2. Rotate API Keys Regularly

```bash
# Generate new keys
./generate-api-keys.sh

# Deploy to all 3 servers
# Old keys remain valid during rollout

# After all services restarted, old keys automatically invalid
```

### 3. Monitor Authentication Logs

```bash
# On storage servers
docker logs sss-storage-server-a | grep "UNAUTHORIZED"
docker logs sss-storage-server-b | grep "UNAUTHORIZED"

# Look for:
# - Repeated failures from same IP
# - Failed attempts from storage server IPs (indicates compromise)
# - Unexpected source IPs
```

### 4. Network Isolation (Recommended)

```bash
# Firewall rules on Server A
iptables -A INPUT -p tcp --dport 8080 -s 139.91.90.11 -j ACCEPT  # Client only
iptables -A INPUT -p tcp --dport 8080 -j DROP  # Block all others

# Firewall rules on Server B
iptables -A INPUT -p tcp --dport 8080 -s 139.91.90.11 -j ACCEPT  # Client only
iptables -A INPUT -p tcp --dport 8080 -j DROP  # Block all others
```

**Result:** Even if attacker gets API key, cannot reach servers from compromised storage server

---

## Upgrading to HTTPS (Optional but Recommended)

### Why HTTPS?

Without HTTPS, API keys are sent in plaintext over the network:
```
Authorization: Bearer a1b2c3d4e5f6...  ← Visible to network eavesdroppers
```

### How to Add HTTPS

1. **Generate Certificates**:
   ```bash
   # Self-signed (for testing)
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout server.key -out server.crt

   # Production: use Let's Encrypt
   certbot certonly --standalone -d storage-a.yourdomain.com
   ```

2. **Update Storage Server Code**:
   ```go
   // In main()
   certFile := os.Getenv("TLS_CERT")
   keyFile := os.Getenv("TLS_KEY")

   if certFile != "" && keyFile != "" {
       log.Fatal(http.ListenAndServeTLS(":"+port, certFile, keyFile, nil))
   } else {
       log.Fatal(http.ListenAndServe(":"+port, nil))
   }
   ```

3. **Update Client URLs**:
   ```bash
   # In client.env
   STORAGE_SERVER_A_URL=https://139.91.90.9:8443
   STORAGE_SERVER_B_URL=https://139.91.90.156:8443
   ```

---

## Troubleshooting

### Problem: "Authentication failed: Invalid or missing API key"

**Check:**
```bash
# On client
docker exec sss-client env | grep API_KEY
# Should show: STORAGE_SERVER_A_API_KEY=... and STORAGE_SERVER_B_API_KEY=...

# If missing, recreate container with --env-file
cd /tmp/sss-client
docker-compose -f docker-compose-client.yml --env-file client.env up -d
```

### Problem: Storage server won't start

**Check logs:**
```bash
docker logs sss-storage-server-a

# If you see: "API_KEY_HASH environment variable is required"
# Fix: Provide --env-file when starting
docker-compose -f docker-compose-server-a.yml --env-file server-a.env up -d
```

### Problem: Keys don't match

**Verify hash calculation:**
```bash
# On your local machine
API_KEY="a1b2c3d4e5f6..."  # From client.env
echo -n "$API_KEY" | sha256sum

# Should match the hash in server-a.env
# Note: Use echo -n (no newline) for correct hash
```

---

## Security Checklist

Before going to production:

- [ ] Generated strong API keys (64 hex characters each)
- [ ] Distributed correct .env files to each server
- [ ] Verified Server A only has HASH(API_KEY_A)
- [ ] Verified Server B only has HASH(API_KEY_B)
- [ ] Verified Client has both plaintext API keys
- [ ] Set client.env permissions to 600
- [ ] Tested authentication with health-check
- [ ] Tested full encrypt/decrypt workflow
- [ ] Configured firewall rules (storage servers only accept from client IP)
- [ ] Enabled audit logging
- [ ] Documented key rotation procedure
- [ ] (Optional) Enabled HTTPS/TLS
- [ ] Deleted generate-api-keys.sh output after distribution

---

## Summary

**Security Improvement:**

| Scenario | Before (No Auth) | After (Separate Keys) |
|----------|------------------|----------------------|
| Server A compromised | ⚠️ Can get Share B via HTTP | ✅ Cannot authenticate to Server B |
| Server B compromised | ⚠️ Can get Share A via HTTP | ✅ Cannot authenticate to Server A |
| Both servers compromised | 🚨 Full decrypt | 🚨 Full decrypt (accepted risk) |
| Client compromised | 🚨 Full decrypt | 🚨 Full decrypt (expected) |
| Network eavesdrop | ⚠️ N/A (no auth) | ⚠️ Capture keys (use HTTPS) |

**Key Takeaway:** Separate API keys prevent cross-server attacks. A compromised storage server cannot impersonate the client to retrieve data from the other server.
