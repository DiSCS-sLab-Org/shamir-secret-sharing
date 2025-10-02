# Shamir's Secret Sharing System - Comprehensive Security Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Crypto-Tools Code Analysis](#crypto-tools-code-analysis)
4. [Storage Server Code Analysis](#storage-server-code-analysis)
5. [Scripts Analysis](#scripts-analysis)
6. [Docker Configuration](#docker-configuration)
7. [Security Assessment](#security-assessment)
8. [Plaintext Traces Analysis](#plaintext-traces-analysis)
9. [Attack Scenarios](#attack-scenarios)

---

## System Overview

### Purpose
This system securely processes and stores daily attacker IP lists using **Shamir's Secret Sharing (SSS)** to split encryption keys across two storage servers. Only the client server can decrypt the data by retrieving shares from both storage servers.

### Key Security Goals
✅ **No plaintext persistence** - Original files deleted after encryption
✅ **Split trust** - No single server has complete access to data
✅ **End-to-end encryption** - Data encrypted before leaving client
✅ **Authenticated encryption** - Tamper detection via Poly1305 MAC
✅ **Access control** - Only client can decrypt (requires both shares)

---

## Architecture

```
┌─────────────────────┐
│  Client Server      │
│  (139.91.90.11)     │
│                     │
│  1. Receives IPs    │
│  2. Generates DEK   │
│  3. Encrypts data   │
│  4. Splits DEK      │
│  5. Distributes     │
│  6. Deletes source  │
└──────┬──────────────┘
       │
       ├─────────────────────┬──────────────────────┐
       │                     │                      │
       ▼                     ▼                      ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│ Storage A    │      │ Storage B    │      │              │
│ 139.91.90.9  │      │ 139.91.90.156│      │   Stored:    │
│              │      │              │      │              │
│ Has:         │      │ Has:         │      │ • Bundle     │
│ • Share A    │      │ • Share B    │      │   (both)     │
│ • Bundle     │      │ • Bundle     │      │ • Share A    │
│              │      │              │      │   (A only)   │
└──────────────┘      └──────────────┘      │ • Share B    │
                                             │   (B only)   │
                                             └──────────────┘
```

### Data Flow

**Encryption Process:**
1. Client receives `attackers_YYYY-MM-DD.json`
2. Generates 32-byte DEK (Data Encryption Key)
3. Encrypts JSON with XChaCha20-Poly1305 using DEK
4. Creates bundle: `{algorithm, nonce, ciphertext, date}`
5. Stores bundle on **both** servers (redundancy)
6. Splits DEK into 2 shares using SSS (k=2, n=2)
7. Stores Share A **only** on Server A
8. Stores Share B **only** on Server B
9. **Deletes** original plaintext file
10. Clears sensitive variables from memory

**Decryption Process:**
1. Client requests Share A from Server A
2. Client requests Share B from Server B
3. Client combines shares to reconstruct DEK
4. Client retrieves bundle from either server
5. Client decrypts bundle using reconstructed DEK
6. Data displayed to stdout (**NOT saved to disk**)
7. Clears all sensitive variables from memory

---

## Crypto-Tools Code Analysis

### File: `crypto-tools/main.go`

This is the **client-side cryptographic tool** that handles all encryption, decryption, key splitting, and server communication.

#### Key Functions

### 1. **DEK Generation** (`generateDEK()`)

```go
func generateDEK() {
    key := make([]byte, 32)
    if _, err := rand.Read(key); err != nil {
        log.Fatal("Failed to generate DEK:", err)
    }
    fmt.Print(base64.StdEncoding.EncodeToString(key))
}
```

**What it does:**
- Generates a **256-bit (32-byte)** random key using `crypto/rand`
- Uses cryptographically secure random number generator
- Outputs base64-encoded key to stdout

**Security:** Uses Go's `crypto/rand` which reads from `/dev/urandom` on Linux - cryptographically secure.

---

### 2. **Encryption** (`encrypt()`)

```go
func encrypt(plaintextFile, dekB64, date string) {
    // Read plaintext
    plaintext, err := os.ReadFile(plaintextFile)

    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)

    // Create cipher (XChaCha20-Poly1305)
    aead, err := chacha20poly1305.NewX(dek)

    // Generate 24-byte nonce
    nonce := make([]byte, aead.NonceSize())
    rand.Read(nonce)

    // Associated data (authenticated but not encrypted)
    ad := []byte(date)

    // Encrypt: ciphertext = plaintext || MAC
    ciphertext := aead.Seal(nil, nonce, plaintext, ad)

    // Create bundle
    bundle := CipherBundle{
        Algorithm:      "XChaCha20-Poly1305",
        Nonce:         base64.StdEncoding.EncodeToString(nonce),
        Ciphertext:    base64.StdEncoding.EncodeToString(ciphertext),
        AssociatedData: date,
        Date:          date,
    }

    fmt.Print(string(bundleJSON))
}
```

**What it does:**
1. Reads plaintext file from disk (only time plaintext is read)
2. Creates XChaCha20-Poly1305 AEAD cipher
3. Generates random 24-byte nonce (extended nonce for XChaCha20)
4. Encrypts data with authenticated encryption
5. Outputs JSON bundle to stdout

**Security Features:**
- **XChaCha20-Poly1305**: Modern AEAD cipher (Authenticated Encryption with Associated Data)
- **Extended nonce**: 24 bytes (vs 12 for ChaCha20) - better for long-term keys
- **Authentication tag**: Poly1305 MAC appended to ciphertext (prevents tampering)
- **Associated data**: Date is authenticated but not encrypted
- **No disk writes**: Encrypted bundle only in memory, passed via stdout

**Key Point:** The `ciphertext` field contains BOTH encrypted data AND the 16-byte Poly1305 authentication tag appended at the end.

---

### 3. **Decryption** (`decrypt()`)

```go
func decrypt(bundleInput, dekB64 string) {
    // Parse bundle JSON
    var bundle CipherBundle
    json.Unmarshal(bundleData, &bundle)

    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)

    // Create cipher
    aead, err := chacha20poly1305.NewX(dek)

    // Decode components
    nonce, _ := base64.StdEncoding.DecodeString(bundle.Nonce)
    ciphertext, _ := base64.StdEncoding.DecodeString(bundle.Ciphertext)

    // Decrypt and verify MAC
    ad := []byte(bundle.AssociatedData)
    plaintext, err := aead.Open(nil, nonce, ciphertext, ad)
    if err != nil {
        log.Fatal("Decryption failed (auth tag verification failed):", err)
    }

    fmt.Print(string(plaintext))
}
```

**What it does:**
1. Parses JSON bundle
2. Decodes all base64 components
3. Creates same cipher with reconstructed DEK
4. **Verifies authentication tag** (prevents tampering)
5. Decrypts if MAC verification succeeds
6. Outputs plaintext to stdout (**NOT to disk**)

**Security:**
- Authentication tag verified **before** decryption
- If data was tampered with, decryption fails with error
- Plaintext never written to disk - only to stdout for display

---

### 4. **Shamir's Secret Sharing - Split** (`split()`)

```go
func split(dekB64, kStr, nStr string) {
    k := parseInt(kStr)  // Threshold (2)
    n := parseInt(nStr)  // Total shares (2)

    dek, _ := base64.StdEncoding.DecodeString(dekB64)

    // Split using Shamir's Secret Sharing
    shares, err := shamir.Split(dek, n, k)

    // Output shares
    for i, share := range shares {
        fmt.Printf("share_%c:%s\n", 'A'+i, base64.StdEncoding.EncodeToString(share))
    }
}
```

**What it does:**
1. Decodes the 32-byte DEK
2. Uses HashiCorp Vault's Shamir implementation
3. Splits DEK into **n=2 shares** with **k=2 threshold**
4. Outputs: `share_A:...` and `share_B:...`

**Shamir's Secret Sharing (k=2, n=2):**
- **Threshold k=2**: Need **at least 2** shares to reconstruct
- **Total shares n=2**: Generate **exactly 2** shares
- Mathematical property: Any single share reveals **zero information** about the secret
- Only when combining both shares can you reconstruct the original DEK

**Security Implication:**
- Server A has Share A → Cannot reconstruct DEK
- Server B has Share B → Cannot reconstruct DEK
- **Both shares required** → Must compromise both servers

---

### 5. **Shamir's Secret Sharing - Combine** (`combineShares()`)

```go
func combineShares(shareContents []string) {
    var shares [][]byte

    for _, content := range shareContents {
        share, _ := base64.StdEncoding.DecodeString(content)
        shares = append(shares, share)
    }

    // Combine shares to reconstruct secret
    secret, err := shamir.Combine(shares)

    fmt.Print(base64.StdEncoding.EncodeToString(secret))
}
```

**What it does:**
1. Decodes base64 shares
2. Uses Shamir algorithm to reconstruct original secret
3. Outputs reconstructed DEK

**Security:** Only works if you have ≥k shares (in our case, exactly 2).

---

### 6. **Server Communication**

#### Store on Specific Server (`storeOnSpecificServer()`)

```go
func storeOnSpecificServer(server, filename, content string) {
    var serverURL string
    switch server {
    case "A", "serverA":
        serverURL = os.Getenv("STORAGE_SERVER_A_URL")
    case "B", "serverB":
        serverURL = os.Getenv("STORAGE_SERVER_B_URL")
    }

    req := StoreRequest{
        Filename: filename,
        Content:  content,
    }

    storeOnServer(serverURL, req)
}
```

**What it does:**
- Routes storage requests to **specific server** (A or B)
- Used for storing shares separately
- Prevents both shares from ending up on same server

**Critical for security:** Ensures Share A only goes to Server A, Share B only to Server B.

---

## Storage Server Code Analysis

### File: `storage-server/main.go`

This is a **simple HTTP file storage server** running on both Storage Server A and Storage Server B.

#### Key Features

### 1. **Store Endpoint** (`/store`)

```go
func handleStore(w http.ResponseWriter, r *http.Request) {
    var req StoreRequest
    json.Unmarshal(body, &req)

    // Security: prevent path traversal attacks
    filename := filepath.Base(req.Filename)
    filePath := filepath.Join(dataDir, filename)

    os.WriteFile(filePath, []byte(req.Content), 0644)

    log.Printf("Stored file: %s (%d bytes)", filename, len(req.Content))
}
```

**What it does:**
1. Receives JSON: `{filename: "...", content: "..."}`
2. Sanitizes filename with `filepath.Base()` (prevents `../../etc/passwd`)
3. Writes content to `/data/filename`
4. Returns success response

**Security:**
- **Path traversal protection**: `filepath.Base()` strips directory components
- **No authentication**: ⚠️ Any client with network access can store/retrieve
- **Plaintext storage**: Files stored as-is (but they're already encrypted)

---

### 2. **Retrieve Endpoint** (`/retrieve?filename=...`)

```go
func handleRetrieve(w http.ResponseWriter, r *http.Request) {
    filename := r.URL.Query().Get("filename")

    // Security: prevent path traversal
    filename = filepath.Base(filename)
    filePath := filepath.Join(dataDir, filename)

    content, err := os.ReadFile(filePath)

    json.NewEncoder(w).Encode(RetrieveResponse{
        Content: string(content),
        Found:   true,
    })
}
```

**What it does:**
1. Receives GET request with `filename` parameter
2. Sanitizes filename
3. Reads file from `/data/`
4. Returns JSON: `{content: "...", found: true/false}`

**Security:**
- Same path traversal protection
- No authentication ⚠️

---

### 3. **Health Check** (`/health`)

Simple endpoint returning `{"status": "healthy", "server_id": "A"}` for monitoring.

---

## Scripts Analysis

### 1. **Encryption Script** (`client-encrypt-daily.sh`)

```bash
#!/bin/bash
set -e  # Exit on any error

DATE=${1:-$(date +%Y-%m-%d)}
DAILY_FILE="/daily-files/attackers_${DATE}.json"

# Step 1: Health check
sss-crypto-tool health-check

# Step 2: Generate DEK
DEK=$(sss-crypto-tool generate-dek)

# Step 3: Encrypt data
BUNDLE=$(sss-crypto-tool encrypt "$DAILY_FILE" "$DEK" "$DATE")

# Step 4: Store bundle on BOTH servers
sss-crypto-tool store-on-servers "bundle_${DATE}.json" "$BUNDLE"

# Step 5: Split DEK (k=2, n=2)
SHARES=$(sss-crypto-tool split "$DEK" 2 2)
SHARE_A=$(echo "$SHARES" | grep "share_A:" | cut -d: -f2)
SHARE_B=$(echo "$SHARES" | grep "share_B:" | cut -d: -f2)

# Step 6: Store Share A on Server A ONLY
sss-crypto-tool store-on-server A "share_A_${DATE}.bin" "$SHARE_A"

# Step 7: Store Share B on Server B ONLY
sss-crypto-tool store-on-server B "share_B_${DATE}.bin" "$SHARE_B"

# Step 8: DELETE original plaintext file
rm "$DAILY_FILE"

# Step 9: Clear sensitive data from memory
unset DEK SHARES SHARE_A SHARE_B BUNDLE
```

**Security Analysis:**

✅ **Plaintext deleted** (line 54): `rm "$DAILY_FILE"`
✅ **Memory cleared** (line 66): `unset DEK SHARES SHARE_A SHARE_B BUNDLE`
✅ **Separate share storage**: Uses `store-on-server A/B` to ensure separation
✅ **Error handling**: `set -e` stops script on any error

**Critical Security Point:** Line 54 ensures original plaintext is deleted after successful encryption.

---

### 2. **Decryption Script** (`client-decrypt-view.sh`)

```bash
#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}

# Step 1: Health check
sss-crypto-tool health-check

# Step 2: Retrieve shares from BOTH servers
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin")
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_${DATE}.bin")

# Step 3: Combine shares to reconstruct DEK
RECONSTRUCTED_DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")

# Step 4: Retrieve encrypted bundle
BUNDLE=$(sss-crypto-tool retrieve-from-server A "bundle_${DATE}.json")

# Step 5: Decrypt
DECRYPTED=$(sss-crypto-tool decrypt "$BUNDLE" "$RECONSTRUCTED_DEK")

# Step 6: Display to stdout (NO FILE SAVED)
echo "$DECRYPTED" | jq '.'

# Security: NO plaintext files saved to disk (line 40 comment)

# Step 7: Clear sensitive data
unset SHARE_A SHARE_B RECONSTRUCTED_DEK DECRYPTED BUNDLE
```

**Security Analysis:**

✅ **No plaintext persistence**: Decrypted data only in variable `$DECRYPTED`
✅ **Display only**: Data piped to `jq` for pretty-printing to terminal
✅ **Memory cleared** (line 52): All sensitive variables unset
✅ **Requires both servers**: Must successfully retrieve from A AND B

**Critical Security Point:** Line 40 comment explicitly states "NO plaintext files saved to disk"

---

## Docker Configuration

### Client Dockerfile (`Dockerfile.client`)

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY crypto-tools/ .
RUN go build -o sss-crypto-tool main.go

FROM alpine:latest
RUN apk add --no-cache bash jq curl ca-certificates

COPY --from=builder /build/sss-crypto-tool /usr/local/bin/sss-crypto-tool
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

RUN mkdir -p /daily-files /processed

CMD tail -f /dev/null
```

**What it does:**
- Multi-stage build: Compile Go code in builder, copy binary to minimal Alpine
- Installs: bash (for scripts), jq (for JSON parsing), curl (for health checks)
- Creates `/daily-files` for incoming IP lists
- Keeps container running with `tail -f /dev/null`

---

### Storage Server Dockerfile (`Dockerfile.server`)

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY storage-server/ .
RUN go build -o sss-storage-server main.go

FROM alpine:latest
RUN apk add --no-cache ca-certificates wget

COPY --from=builder /build/sss-storage-server /usr/local/bin/sss-storage-server
EXPOSE 8080
CMD ["sss-storage-server"]
```

**What it does:**
- Compiles storage server
- Minimal runtime (Alpine + wget for healthchecks)
- Exposes port 8080
- Runs storage server as main process

---

### Client Compose (`docker-compose-client.yml`)

```yaml
services:
  sss-client:
    volumes:
      - ./daily-files:/daily-files
      - ./scripts:/scripts
    environment:
      - STORAGE_SERVER_A_URL=http://139.91.90.9:8080
      - STORAGE_SERVER_B_URL=http://139.91.90.156:8080
```

**Key Configuration:**
- Volume mounts for input files and scripts
- Environment variables pointing to storage servers
- Health check using `sss-crypto-tool health-check`

---

## Security Assessment

### ✅ Does the system accomplish its goals?

**Goal: "A tool that gets a list of IPs, splits it with SSS on 2 servers, and only the 3rd server (client) can access and compose it"**

**Answer: YES** ✅

1. **Input**: Client receives IP list in `/daily-files/attackers_YYYY-MM-DD.json`
2. **Encryption**: Client encrypts with randomly generated DEK
3. **Key Splitting**: DEK split into 2 shares using Shamir's Secret Sharing (k=2, n=2)
4. **Distribution**:
   - Encrypted bundle stored on **both** servers (redundancy)
   - Share A stored **only** on Server A
   - Share B stored **only** on Server B
5. **Decryption**: Only client can decrypt by:
   - Retrieving Share A from Server A
   - Retrieving Share B from Server B
   - Combining shares to reconstruct DEK
   - Decrypting bundle with DEK

---

## Plaintext Traces Analysis

### ❓ Does any trace of the original file get left anywhere?

**Answer: NO** ✅ (with caveats)

#### On Client Server:

**Deleted:**
- ✅ Original file: `rm "$DAILY_FILE"` (client-encrypt-daily.sh:54)
- ✅ Shell variables: `unset DEK SHARES SHARE_A SHARE_B BUNDLE` (line 66)

**Potential Traces:**
1. **Bash history**: Commands might be logged
   - Mitigation: Use `HISTCONTROL=ignorespace` or clear history
2. **Swap space**: If memory swapped to disk, DEK might persist
   - Mitigation: Disable swap or use encrypted swap
3. **Process memory**: Until process exits, data in RAM
   - Mitigation: Process exits quickly after unset
4. **Docker volumes**: `/daily-files` mount could retain deleted files
   - Check: `docker exec sss-client ls -la /daily-files/`
   - Should be empty after processing
5. **Filesystem journal**: ext4/XFS journals might cache deleted data temporarily
   - Mitigation: Use `shred` instead of `rm` for secure deletion

**Recommendation:** Change line 54 to:
```bash
shred -uvz "$DAILY_FILE"  # Overwrite, remove, zero
```

#### On Storage Servers:

**Stored (encrypted):**
- ✅ Encrypted bundles (ciphertext + nonce + MAC)
- ✅ SSS shares (Share A on Server A, Share B on Server B)

**NOT stored:**
- ✅ Plaintext data
- ✅ DEK (only shares)
- ✅ Decrypted content

**Assessment:** Storage servers only have encrypted data and partial key shares - **no plaintext traces**.

---

## Attack Scenarios

### Scenario 1: Attacker Compromises Storage Server A

**What attacker gets:**
- ✅ Share A (base64-encoded)
- ✅ All encrypted bundles

**What attacker CANNOT do:**
- ❌ Reconstruct DEK (needs Share B from Server B)
- ❌ Decrypt any data (needs complete DEK)
- ❌ Learn anything about plaintext from Share A alone

**Mathematical guarantee:** Shamir's Secret Sharing is information-theoretically secure. Having k-1 shares reveals **zero information** about the secret.

**Result:** ⚠️ **Partial compromise** - Data remains encrypted and secure.

---

### Scenario 2: Attacker Compromises Storage Server B

**Same as Scenario 1:**
- Has Share B + encrypted bundles
- Cannot reconstruct DEK
- Cannot decrypt data

**Result:** ⚠️ **Partial compromise** - Data remains encrypted and secure.

---

### Scenario 3: Attacker Compromises BOTH Storage Servers A and B

**What attacker gets:**
- ✅ Share A from Server A
- ✅ Share B from Server B
- ✅ All encrypted bundles

**What attacker CAN do:**
- ✅ Combine Share A + Share B → Reconstruct DEK
- ✅ Decrypt bundles using DEK
- ✅ Access all plaintext attacker IP lists

**Result:** 🚨 **FULL COMPROMISE** - All data decrypted.

**Mitigation:** This is the fundamental security model - we accept this risk because:
1. Compromising 2 separate servers is harder than 1
2. Requires coordinated attack or insider access
3. Can add monitoring to detect if both servers accessed by same entity
4. Could extend to k=2, n=3 (need any 2 of 3 servers) for better resilience

---

### Scenario 4: Someone from Server A or B Acts as Client

**Question:** "Could someone from server A or B get access to the other server and act as a client to decrypt the file?"

**Answer:** YES, but with constraints ⚠️

**Requirements to act as client:**
1. **Network access** to both storage servers (ports 8080)
2. **Knowledge** of:
   - Server URLs (http://139.91.90.9:8080, http://139.91.90.156:8080)
   - File naming convention (bundle_YYYY-MM-DD.json, share_A_YYYY-MM-DD.bin)
   - Date of files to decrypt
3. **Tools**: `sss-crypto-tool` binary (or implement the protocol)

**Attack Steps:**
```bash
# From Server A (has Share A):
# 1. Retrieve own Share A from local disk
SHARE_A=$(cat /data/share_A_2025-09-30.bin)

# 2. Retrieve Share B from Server B
SHARE_B=$(curl http://139.91.90.156:8080/retrieve?filename=share_B_2025-09-30.bin)

# 3. Combine shares
DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")

# 4. Retrieve bundle
BUNDLE=$(cat /data/bundle_2025-09-30.json)

# 5. Decrypt
PLAINTEXT=$(sss-crypto-tool decrypt "$BUNDLE" "$DEK")
```

**Result:** 🚨 **YES, possible** - Someone with shell access to Server A (or B) can act as a rogue client.

---

### Security Implications of Storage Server Access

**Current Protection Level:**

| Attacker Access | Can Decrypt? | Why |
|----------------|--------------|-----|
| Server A only | ❌ No | Missing Share B |
| Server B only | ❌ No | Missing Share A |
| Server A + Network to B | ✅ Yes | Can retrieve Share B via HTTP |
| Server B + Network to A | ✅ Yes | Can retrieve Share A via HTTP |
| Client only | ✅ Yes | Designed access |

**Critical Vulnerability:** Storage servers have **no authentication** on their HTTP APIs.

---

### Recommended Security Improvements

#### 1. **Add Authentication to Storage Servers**

```go
func handleRetrieve(w http.ResponseWriter, r *http.Request) {
    // Verify client certificate or API key
    if !authenticateClient(r) {
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }
    // ... rest of code
}
```

**Options:**
- **Mutual TLS (mTLS)**: Client presents certificate, servers verify
- **API Keys**: Client includes secret token in Authorization header
- **Network isolation**: Put storage servers on private network, client connects via VPN

---

#### 2. **Network Segmentation**

```
Client Server:     Can connect to both Storage A and B
Storage Server A:  CANNOT connect to Storage Server B
Storage Server B:  CANNOT connect to Storage Server A
```

**Firewall Rules:**
- Storage A: Allow incoming 8080 from Client IP only
- Storage B: Allow incoming 8080 from Client IP only
- Storage A/B: Block all outgoing connections (except updates)

**Result:** Even if attacker shells into Server A, cannot reach Server B over network.

---

#### 3. **Audit Logging**

Add to storage servers:
```go
log.Printf("RETRIEVE: %s from %s at %s", filename, r.RemoteAddr, time.Now())
```

Monitor for:
- Retrievals from unexpected IPs
- Same IP retrieving shares from both servers
- Unusual access patterns

---

#### 4. **Secure Deletion on Client**

Change `client-encrypt-daily.sh` line 54:
```bash
shred -uvz -n 3 "$DAILY_FILE"  # Overwrite 3 times, remove, zero
```

---

#### 5. **Extend SSS to k=2, n=3**

```bash
SHARES=$(sss-crypto-tool split "$DEK" 2 3)  # Need 2 of 3 shares
```

Add third storage server. Now:
- Attacker needs any 2 of 3 servers
- Loss of 1 server still allows decryption
- Better resilience and security

---

## Summary

### System Validation

✅ **Goal Accomplished:** System successfully encrypts IP lists, splits keys across 2 servers, and only client can decrypt.

✅ **No Plaintext Persistence:** Original files deleted, only encrypted data stored.

⚠️ **Security Boundary:** Trust model assumes storage servers are isolated. If attacker gains shell access to Server A **and** network access to Server B, they can act as a rogue client.

---

### Attack Surface

**Secure Against:**
1. ✅ Single server compromise (need both)
2. ✅ Network eavesdropping (data encrypted)
3. ✅ Tampered bundles (MAC verification)
4. ✅ Path traversal attacks (filepath.Base())

**Vulnerable To:**
1. ⚠️ Compromise of both storage servers
2. ⚠️ Rogue admin on storage server with network to other server
3. ⚠️ No authentication on storage APIs
4. ⚠️ Potential memory/swap/filesystem traces on client

---

### Recommended Actions

**High Priority:**
1. Add authentication to storage server APIs (mTLS or API keys)
2. Implement network segmentation (storage servers isolated from each other)
3. Use `shred` instead of `rm` for secure deletion

**Medium Priority:**
4. Add audit logging to all servers
5. Monitor for unusual access patterns
6. Consider extending to k=2, n=3 setup

**Low Priority:**
7. Disable swap or use encrypted swap on client
8. Review bash history settings
9. Add rate limiting to storage APIs

---

### Cryptographic Strength

**Algorithms Used:**
- **XChaCha20-Poly1305**: 256-bit key, military-grade AEAD cipher
- **Shamir's Secret Sharing**: Information-theoretically secure
- **Random number generation**: `crypto/rand` - cryptographically secure

**Assessment:** Cryptography is **strong and modern**. Primary risks are operational (access control, network isolation) not cryptographic.

---

## Conclusion

This system successfully implements a split-trust architecture where:
- Client encrypts sensitive data
- Two storage servers each hold one piece of the key
- Only the client can decrypt by retrieving both pieces

**The code accomplishes its stated goals.** However, the lack of authentication on storage servers means an attacker with access to one server + network connectivity to the other can decrypt data. This may be acceptable depending on your threat model, or may require additional controls (mTLS, network segmentation, audit logging).

The system provides good defense-in-depth against external attackers and makes single-server compromise non-critical, but assumes storage servers are trusted or isolated from each other.
