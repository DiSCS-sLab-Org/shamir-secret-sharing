# SSS System - Complete Code Explanation

## Table of Contents
1. [System Architecture Overview](#system-architecture-overview)
2. [Storage Server (`storage-server/main.go`)](#storage-server)
3. [Crypto Tools (`crypto-tools/main.go`)](#crypto-tools)
4. [Client Scripts](#client-scripts)
5. [Docker Configuration](#docker-configuration)
6. [Data Flow Walkthrough](#data-flow-walkthrough)
7. [Security Mechanisms](#security-mechanisms)

---

## System Architecture Overview

### The Three Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client Server                            │
│                      (139.91.90.11)                              │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Docker Container: sss-client                              │   │
│  │                                                           │   │
│  │  • crypto-tools binary (Go)                              │   │
│  │    - Encryption (XChaCha20-Poly1305)                     │   │
│  │    - Key splitting (Shamir's Secret Sharing)             │   │
│  │    - HTTP client with API key authentication             │   │
│  │                                                           │   │
│  │  • Bash scripts                                          │   │
│  │    - client-encrypt-daily.sh                             │   │
│  │    - client-decrypt-view.sh                              │   │
│  │                                                           │   │
│  │  • Environment variables                                 │   │
│  │    - API_KEY_A (plaintext, for Server A)                │   │
│  │    - API_KEY_B (plaintext, for Server B)                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ HTTP requests with API keys
                               │
              ┌────────────────┴──────────────────┐
              │                                   │
              ▼                                   ▼
┌──────────────────────────┐        ┌──────────────────────────┐
│   Storage Server A       │        │   Storage Server B       │
│   (139.91.90.9:8080)     │        │   (139.91.90.156:8080)   │
│                          │        │                          │
│  ┌────────────────────┐  │        │  ┌────────────────────┐  │
│  │ storage-server     │  │        │  │ storage-server     │  │
│  │                    │  │        │  │                    │  │
│  │ • HTTP server      │  │        │  │ • HTTP server      │  │
│  │ • API key verify   │  │        │  │ • API key verify   │  │
│  │ • File storage     │  │        │  │ • File storage     │  │
│  │                    │  │        │  │                    │  │
│  │ Has:               │  │        │  │ Has:               │  │
│  │ • HASH(API_KEY_A)  │  │        │  │ • HASH(API_KEY_B)  │  │
│  │ • Share A          │  │        │  │ • Share B          │  │
│  │ • Encrypted bundle │  │        │  │ • Encrypted bundle │  │
│  └────────────────────┘  │        │  └────────────────────┘  │
└──────────────────────────┘        └──────────────────────────┘
```

### Key Principle: Split Trust

**No single server has enough information to decrypt data:**
- Server A: Has Share A + encrypted data (missing Share B)
- Server B: Has Share B + encrypted data (missing Share A)
- Client: Has API keys for both servers (authorized to retrieve both shares)

---

## Storage Server

**File:** `storage-server/main.go`
**Purpose:** Simple HTTP file storage with API key authentication
**Runs on:** Storage Server A (139.91.90.9) and Storage Server B (139.91.90.156)

### Main Components

#### 1. Data Structures

```go
type StoreRequest struct {
    Filename string `json:"filename"`
    Content  string `json:"content"`
}
```
**Used for:** Client sends files to server
**Example:**
```json
{
  "filename": "share_A_2025-10-02.bin",
  "content": "base64encodedshare..."
}
```

```go
type RetrieveResponse struct {
    Content string `json:"content"`
    Found   bool   `json:"found"`
}
```
**Used for:** Server returns files to client
**Example:**
```json
{
  "content": "base64encodedshare...",
  "found": true
}
```

```go
type HealthResponse struct {
    Status   string `json:"status"`
    ServerID string `json:"server_id"`
}
```
**Used for:** Health checks
**Example:**
```json
{
  "status": "healthy",
  "server_id": "A"
}
```

---

#### 2. Initialization (`main()`)

```go
func main() {
    // Ensure data directory exists
    if err := os.MkdirAll(dataDir, 0755); err != nil {
        log.Fatal("Failed to create data directory:", err)
    }
```
**What it does:** Creates `/data` directory if it doesn't exist
**Why:** All stored files go here (shares, bundles)

```go
    serverID = os.Getenv("SERVER_ID")
    if serverID == "" {
        serverID = "unknown"
    }
```
**What it does:** Reads `SERVER_ID` from environment
**Value:** "A" for Server A, "B" for Server B
**Used for:** Logging and health check responses

```go
    apiKeyHash = os.Getenv("API_KEY_HASH")
    if apiKeyHash == "" {
        log.Fatal("API_KEY_HASH environment variable is required")
    }
```
**What it does:** Reads SHA256 hash of the API key
**Critical:** Server NEVER knows the actual API key, only its hash
**Example:**
- Server A has: `API_KEY_HASH=7f8a9b0c1d2e...` (hash of API_KEY_A)
- Server B has: `API_KEY_HASH=3e4d5c6b7a8f...` (hash of API_KEY_B)

```go
    port := os.Getenv("SERVER_PORT")
    if port == "" {
        port = "8080"
    }
```
**Default port:** 8080

---

#### 3. HTTP Endpoints

```go
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(HealthResponse{
            Status:   "healthy",
            ServerID: serverID,
        })
    })
```
**Endpoint:** `GET /health`
**Purpose:** Check if server is running
**Authentication:** None (public endpoint)
**Example:**
```bash
curl http://139.91.90.9:8080/health
# Returns: {"status":"healthy","server_id":"A"}
```

```go
    http.HandleFunc("/store", authenticateRequest(handleStore))
    http.HandleFunc("/retrieve", authenticateRequest(handleRetrieve))
```
**Endpoints:**
- `POST /store` - Store a file
- `GET /retrieve?filename=<name>` - Retrieve a file

**Notice:** Both wrapped with `authenticateRequest()` middleware
**Meaning:** Both require valid API key

---

#### 4. Authentication Middleware (`authenticateRequest()`)

**Purpose:** Verify API key before allowing access to `/store` or `/retrieve`

```go
func authenticateRequest(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        // Extract API key from Authorization header
        authHeader := r.Header.Get("Authorization")
        if authHeader == "" {
            log.Printf("UNAUTHORIZED: Missing Authorization header from %s", r.RemoteAddr)
            http.Error(w, "Unauthorized: Missing API key", http.StatusUnauthorized)
            return
        }
```
**Step 1:** Check if `Authorization` header exists
**Expected format:** `Authorization: Bearer <api-key>`
**If missing:** Return 401 Unauthorized

```go
        // Expected format: "Bearer <api-key>"
        parts := strings.SplitN(authHeader, " ", 2)
        if len(parts) != 2 || parts[0] != "Bearer" {
            log.Printf("UNAUTHORIZED: Invalid Authorization format from %s", r.RemoteAddr)
            http.Error(w, "Unauthorized: Invalid API key format", http.StatusUnauthorized)
            return
        }

        providedKey := parts[1]
```
**Step 2:** Parse header to extract API key
**Example:**
- Header: `Authorization: Bearer abc123def456...`
- `parts[0]` = "Bearer"
- `parts[1]` = "abc123def456..." (the actual API key)

```go
        // Hash the provided key
        hasher := sha256.New()
        hasher.Write([]byte(providedKey))
        providedHash := hex.EncodeToString(hasher.Sum(nil))
```
**Step 3:** Hash the provided key using SHA256
**Why hash?** Server only stores hash, not plaintext key
**Example:**
- Client sends: `abc123def456...` (64 hex characters)
- Server computes: SHA256(`abc123def456...`) = `7f8a9b0c1d2e...`

```go
        // Constant-time comparison to prevent timing attacks
        if subtle.ConstantTimeCompare([]byte(providedHash), []byte(apiKeyHash)) != 1 {
            log.Printf("UNAUTHORIZED: Invalid API key from %s (hash: %s...)", r.RemoteAddr, providedHash[:16])
            http.Error(w, "Unauthorized: Invalid API key", http.StatusUnauthorized)
            return
        }
```
**Step 4:** Compare computed hash with stored hash
**Important:** Uses `subtle.ConstantTimeCompare()` to prevent timing attacks
**Timing attack:** Attacker measures response time to guess hash byte-by-byte
**Constant-time:** All comparisons take same time regardless of match/mismatch

**If hashes match:** ✅ Client authenticated
**If hashes don't match:** ❌ Return 401 Unauthorized

```go
        // Log successful authentication
        log.Printf("AUTHENTICATED: Request from %s to %s", r.RemoteAddr, r.URL.Path)

        // Call the actual handler
        next(w, r)
    }
}
```
**Step 5:** Log successful auth and call the actual handler
**Example log:** `AUTHENTICATED: Request from 139.91.90.11 to /store`

---

#### 5. Store Handler (`handleStore()`)

```go
func handleStore(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    body, err := io.ReadAll(r.Body)
    if err != nil {
        http.Error(w, "Failed to read request body", http.StatusBadRequest)
        return
    }

    var req StoreRequest
    if err := json.Unmarshal(body, &req); err != nil {
        http.Error(w, "Invalid JSON", http.StatusBadRequest)
        return
    }
```
**Step 1:** Validate request method (must be POST)
**Step 2:** Read request body
**Step 3:** Parse JSON into StoreRequest struct

```go
    if req.Filename == "" {
        http.Error(w, "Filename is required", http.StatusBadRequest)
        return
    }

    // Security: prevent path traversal
    filename := filepath.Base(req.Filename)
    filePath := filepath.Join(dataDir, filename)
```
**Step 4:** Security check - prevent path traversal attacks
**Example attack:** Client sends `filename: "../../etc/passwd"`
**Defense:** `filepath.Base()` strips directory parts
**Result:**
- Input: `../../etc/passwd`
- After `Base()`: `passwd`
- Final path: `/data/passwd` ✅ Safe

```go
    if err := os.WriteFile(filePath, []byte(req.Content), 0644); err != nil {
        log.Printf("Failed to write file %s: %v", filename, err)
        http.Error(w, "Failed to store file", http.StatusInternalServerError)
        return
    }

    log.Printf("Stored file: %s (%d bytes)", filename, len(req.Content))
```
**Step 5:** Write file to `/data/<filename>`
**Permissions:** `0644` (readable by all, writable by owner)
**Log:** Records filename and size

```go
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "status":  "success",
        "message": "File stored successfully",
    })
}
```
**Step 6:** Return success response

**Complete Flow Example:**
```
Client → POST /store
Header: Authorization: Bearer abc123def456...
Body: {"filename": "share_A_2025-10-02.bin", "content": "YWJjZGVm..."}

Server:
1. ✅ Authenticate (hash matches)
2. ✅ Parse JSON
3. ✅ Sanitize filename
4. ✅ Write to /data/share_A_2025-10-02.bin
5. ✅ Return {"status": "success"}
```

---

#### 6. Retrieve Handler (`handleRetrieve()`)

```go
func handleRetrieve(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    filename := r.URL.Query().Get("filename")
    if filename == "" {
        http.Error(w, "Filename parameter is required", http.StatusBadRequest)
        return
    }

    // Security: prevent path traversal
    filename = filepath.Base(filename)
    filePath := filepath.Join(dataDir, filename)
```
**Step 1:** Validate GET request
**Step 2:** Extract filename from query parameter
**Step 3:** Sanitize filename (same path traversal protection)

```go
    content, err := os.ReadFile(filePath)
    if err != nil {
        if os.IsNotExist(err) {
            w.Header().Set("Content-Type", "application/json")
            json.NewEncoder(w).Encode(RetrieveResponse{
                Content: "",
                Found:   false,
            })
            return
        }
        log.Printf("Failed to read file %s: %v", filename, err)
        http.Error(w, "Failed to retrieve file", http.StatusInternalServerError)
        return
    }
```
**Step 4:** Read file from disk
**If not found:** Return `{"found": false}` (not an error)
**If other error:** Return 500

```go
    log.Printf("Retrieved file: %s (%d bytes)", filename, len(content))

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(RetrieveResponse{
        Content: string(content),
        Found:   true,
    })
}
```
**Step 5:** Return file contents as JSON

**Complete Flow Example:**
```
Client → GET /retrieve?filename=share_A_2025-10-02.bin
Header: Authorization: Bearer abc123def456...

Server:
1. ✅ Authenticate (hash matches)
2. ✅ Sanitize filename
3. ✅ Read /data/share_A_2025-10-02.bin
4. ✅ Return {"content": "YWJjZGVm...", "found": true}
```

---

## Crypto Tools

**File:** `crypto-tools/main.go`
**Purpose:** Client-side cryptographic operations and server communication
**Runs on:** Client Server (139.91.90.11) inside Docker container

### Architecture

This is a **command-line tool** (not a server). It has multiple subcommands:

```bash
sss-crypto-tool generate-dek
sss-crypto-tool encrypt <file> <dek> <date>
sss-crypto-tool decrypt <bundle> <dek>
sss-crypto-tool split <dek> <k> <n>
sss-crypto-tool combine <share1> <share2>
sss-crypto-tool store-on-servers <filename> <content>
sss-crypto-tool store-on-server <server> <filename> <content>
sss-crypto-tool retrieve-from-server <server> <filename>
sss-crypto-tool health-check
```

### Command Router

```go
func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: crypto-tool <command> [args...]")
        // ... print help ...
        os.Exit(1)
    }

    command := os.Args[1]

    switch command {
    case "generate-dek":
        generateDEK()
    case "encrypt":
        encrypt(os.Args[2], os.Args[3], os.Args[4])
    // ... other cases ...
    }
}
```

**How it works:**
1. Read first argument (command name)
2. Route to appropriate function
3. Pass remaining args to that function

---

### 1. Key Generation (`generateDEK()`)

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
1. Create 32-byte (256-bit) array
2. Fill with cryptographically secure random bytes from `crypto/rand`
3. Encode as base64
4. Print to stdout

**Usage:**
```bash
DEK=$(sss-crypto-tool generate-dek)
echo $DEK
# Output: Ql0QOWyJw97PuuWQZr3XyN... (44 characters base64)
```

**Why base64?** Binary data doesn't work well in shell variables and HTTP
**Security:** Uses `crypto/rand` which reads from `/dev/urandom` (cryptographically secure)

---

### 2. Encryption (`encrypt()`)

```go
func encrypt(plaintextFile, dekB64, date string) {
    // Read plaintext
    plaintext, err := os.ReadFile(plaintextFile)
    if err != nil {
        log.Fatal("Failed to read plaintext:", err)
    }
```
**Step 1:** Read input file (the attacker IP list JSON)

```go
    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)
    if err != nil {
        log.Fatal("Failed to decode DEK:", err)
    }
```
**Step 2:** Decode base64 DEK back to binary (32 bytes)

```go
    // Create cipher
    aead, err := chacha20poly1305.NewX(dek)
    if err != nil {
        log.Fatal("Failed to create cipher:", err)
    }
```
**Step 3:** Create XChaCha20-Poly1305 AEAD cipher
**AEAD:** Authenticated Encryption with Associated Data
**XChaCha20:** Stream cipher (fast, secure)
**Poly1305:** Authentication tag (prevents tampering)
**NewX:** Extended nonce version (24 bytes instead of 12)

```go
    // Generate nonce
    nonce := make([]byte, aead.NonceSize())
    if _, err := rand.Read(nonce); err != nil {
        log.Fatal("Failed to generate nonce:", err)
    }
```
**Step 4:** Generate random nonce (24 bytes for XChaCha20)
**Nonce:** Number used once - must be unique for each encryption
**Why random?** No need to track sequence numbers, just use random

```go
    // Associated data (date)
    ad := []byte(date)
```
**Step 5:** Prepare associated data (authenticated but not encrypted)
**Example:** Date "2025-10-02" is authenticated
**Meaning:** If someone changes the date, decryption will fail
**But:** Date is stored in plaintext in the bundle

```go
    // Encrypt
    ciphertext := aead.Seal(nil, nonce, plaintext, ad)
```
**Step 6:** Encrypt!
**`aead.Seal()` does:**
1. Encrypt `plaintext` with ChaCha20 using `dek` and `nonce`
2. Compute Poly1305 MAC over ciphertext + associated data
3. Append 16-byte MAC to ciphertext
4. Return: `[encrypted_data || 16_byte_MAC]`

**Result:** `ciphertext` contains BOTH encrypted data AND authentication tag

```go
    // Create bundle
    bundle := CipherBundle{
        Algorithm:      "XChaCha20-Poly1305",
        Nonce:         base64.StdEncoding.EncodeToString(nonce),
        Ciphertext:    base64.StdEncoding.EncodeToString(ciphertext),
        AssociatedData: date,
        Date:          date,
    }

    // Output bundle as JSON
    bundleJSON, err := json.MarshalIndent(bundle, "", "  ")
    if err != nil {
        log.Fatal("Failed to marshal bundle:", err)
    }

    fmt.Print(string(bundleJSON))
}
```
**Step 7:** Package everything as JSON and print to stdout

**Complete Example:**

```bash
# Input file
cat /daily-files/attackers_2025-10-02.json
["192.168.1.100", "10.0.0.5"]

# Encrypt
DEK=Ql0QOWyJw97PuuWQ...
BUNDLE=$(sss-crypto-tool encrypt /daily-files/attackers_2025-10-02.json $DEK 2025-10-02)

# Output
echo $BUNDLE
{
  "algorithm": "XChaCha20-Poly1305",
  "nonce": "ZXhhbXBsZW5vbmNlMTIzNDU2Nzg5MDEyMzQ1",
  "ciphertext": "aDj3kL9mN...veryLongBase64String...",
  "associated_data": "2025-10-02",
  "date": "2025-10-02"
}
```

---

### 3. Decryption (`decrypt()`)

```go
func decrypt(bundleInput, dekB64 string) {
    var bundleData []byte
    var err error

    // Try to read as file first, then treat as direct content
    if bundleData, err = os.ReadFile(bundleInput); err != nil {
        bundleData = []byte(bundleInput)
    }
```
**Step 1:** Smart input handling
**Tries:** Read as filename first
**If fails:** Treat as direct JSON content
**Why?** Script can pass JSON as string or point to file

```go
    var bundle CipherBundle
    if err := json.Unmarshal(bundleData, &bundle); err != nil {
        log.Fatal("Failed to parse bundle:", err)
    }
```
**Step 2:** Parse JSON into struct

```go
    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)
    if err != nil {
        log.Fatal("Failed to decode DEK:", err)
    }

    // Create cipher
    aead, err := chacha20poly1305.NewX(dek)
    if err != nil {
        log.Fatal("Failed to create cipher:", err)
    }
```
**Step 3:** Recreate the same cipher with the DEK

```go
    // Decode components
    nonce, err := base64.StdEncoding.DecodeString(bundle.Nonce)
    if err != nil {
        log.Fatal("Failed to decode nonce:", err)
    }

    ciphertext, err := base64.StdEncoding.DecodeString(bundle.Ciphertext)
    if err != nil {
        log.Fatal("Failed to decode ciphertext:", err)
    }
```
**Step 4:** Decode base64 components back to binary

```go
    // Decrypt
    ad := []byte(bundle.AssociatedData)
    plaintext, err := aead.Open(nil, nonce, ciphertext, ad)
    if err != nil {
        log.Fatal("Decryption failed (auth tag verification failed):", err)
    }
```
**Step 5:** Decrypt and verify!
**`aead.Open()` does:**
1. Extract last 16 bytes (the Poly1305 MAC)
2. Verify MAC against ciphertext + associated data
3. **If MAC invalid:** Return error (tampering detected!)
4. **If MAC valid:** Decrypt ciphertext with ChaCha20
5. Return plaintext

**Critical:** Authentication happens BEFORE decryption
**Why?** Don't waste time decrypting tampered data

```go
    fmt.Print(string(plaintext))
}
```
**Step 6:** Print plaintext to stdout

**Complete Example:**

```bash
BUNDLE='{"algorithm":"XChaCha20-Poly1305","nonce":"...","ciphertext":"...","date":"2025-10-02"}'
DEK=Ql0QOWyJw97PuuWQ...

PLAINTEXT=$(sss-crypto-tool decrypt "$BUNDLE" "$DEK")
echo $PLAINTEXT
["192.168.1.100", "10.0.0.5"]
```

---

### 4. Shamir Secret Sharing - Split (`split()`)

```go
func split(dekB64, kStr, nStr string) {
    // Parse parameters
    k := parseInt(kStr)
    n := parseInt(nStr)
```
**Parameters:**
- `k`: Threshold - minimum shares needed to reconstruct
- `n`: Total shares to generate

**Our values:** k=2, n=2 (need both shares)

```go
    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)
    if err != nil {
        log.Fatal("Failed to decode DEK:", err)
    }
```
**Step 1:** Decode DEK (32 bytes)

```go
    // Split with Shamir's Secret Sharing
    shares, err := shamir.Split(dek, n, k)
    if err != nil {
        log.Fatal("Failed to split secret:", err)
    }
```
**Step 2:** Use HashiCorp Vault's Shamir implementation
**Math:** Shamir's Secret Sharing uses polynomial interpolation
**Key property:** Any k shares can reconstruct the secret, but k-1 shares reveal NOTHING

**How it works mathematically:**
1. Secret = coefficient a₀ of polynomial
2. Generate random coefficients a₁, a₂, ..., a_{k-1}
3. Polynomial: f(x) = a₀ + a₁x + a₂x² + ... + a_{k-1}x^{k-1}
4. Compute n points: (1, f(1)), (2, f(2)), ..., (n, f(n))
5. Each point is a share
6. Need k points to reconstruct polynomial via Lagrange interpolation
7. Extract a₀ (the secret)

**Example (simplified):**
- Secret: 42
- k=2 (need 2 shares)
- Polynomial: f(x) = 42 + 7x (random coefficient: 7)
- Share 1: f(1) = 42 + 7(1) = 49
- Share 2: f(2) = 42 + 7(2) = 56
- From shares 49 and 56, can solve for secret 42
- With only share 49, infinite possibilities for secret

```go
    // Output shares as base64, one per line
    for i, share := range shares {
        fmt.Printf("share_%c:%s\n", 'A'+i, base64.StdEncoding.EncodeToString(share))
    }
}
```
**Step 3:** Print shares in format: `share_A:<base64>` and `share_B:<base64>`

**Complete Example:**

```bash
DEK=Ql0QOWyJw97PuuWQ...
SHARES=$(sss-crypto-tool split $DEK 2 2)

echo "$SHARES"
share_A:bXlzaGFyZUFkYXRh...
share_B:bXlzaGFyZUJkYXRh...
```

---

### 5. Shamir Secret Sharing - Combine (`combineShares()`)

```go
func combineShares(shareContents []string) {
    var shares [][]byte

    for _, content := range shareContents {
        // Decode base64 share
        share, err := base64.StdEncoding.DecodeString(content)
        if err != nil {
            log.Fatal("Failed to decode share:", err)
        }

        shares = append(shares, share)
    }
```
**Step 1:** Decode all provided shares from base64

```go
    // Combine shares
    secret, err := shamir.Combine(shares)
    if err != nil {
        log.Fatal("Failed to combine shares:", err)
    }
```
**Step 2:** Use Shamir's algorithm to reconstruct secret
**Math:** Lagrange interpolation to find polynomial, then extract constant term

**If k=2:**
- Need exactly 2 points (shares) to define a line
- Find where line crosses y-axis (that's the secret)

```go
    fmt.Print(base64.StdEncoding.EncodeToString(secret))
}
```
**Step 3:** Print reconstructed DEK

**Complete Example:**

```bash
SHARE_A=bXlzaGFyZUFkYXRh...
SHARE_B=bXlzaGFyZUJkYXRh...

RECONSTRUCTED_DEK=$(sss-crypto-tool combine $SHARE_A $SHARE_B)
echo $RECONSTRUCTED_DEK
Ql0QOWyJw97PuuWQ...  # Same as original DEK!
```

---

### 6. Server Communication

#### Store on Both Servers (`storeOnServers()`)

```go
func storeOnServers(filename, content string) {
    serverA := os.Getenv("STORAGE_SERVER_A_URL")
    serverB := os.Getenv("STORAGE_SERVER_B_URL")
```
**Reads URLs from environment:**
- `STORAGE_SERVER_A_URL=http://139.91.90.9:8080`
- `STORAGE_SERVER_B_URL=http://139.91.90.156:8080`

```go
    req := StoreRequest{
        Filename: filename,
        Content:  content,
    }

    // Store on Server A
    if err := storeOnServer(serverA, req); err != nil {
        log.Fatal("Failed to store on Server A:", err)
    }
    fmt.Printf("✅ Stored %s on Server A\n", filename)

    // Store on Server B
    if err := storeOnServer(serverB, req); err != nil {
        log.Fatal("Failed to store on Server B:", err)
    }
    fmt.Printf("✅ Stored %s on Server B\n", filename)
}
```
**What it does:** Store the same file on BOTH servers (redundancy)
**Used for:** Encrypted bundles (both servers get same bundle)

---

#### Store on Specific Server (`storeOnSpecificServer()`)

```go
func storeOnSpecificServer(server, filename, content string) {
    var serverURL string
    switch server {
    case "A", "serverA":
        serverURL = os.Getenv("STORAGE_SERVER_A_URL")
    case "B", "serverB":
        serverURL = os.Getenv("STORAGE_SERVER_B_URL")
    default:
        log.Fatal("Server must be 'A' or 'B'")
    }
```
**What it does:** Store file on ONE specific server
**Used for:** Shares (Share A only on Server A, Share B only on Server B)

---

#### HTTP Store Request with Authentication (`storeOnServer()`)

```go
func storeOnServer(serverURL string, req StoreRequest) error {
    jsonData, err := json.Marshal(req)
    if err != nil {
        return err
    }

    httpReq, err := http.NewRequest("POST", serverURL+"/store", bytes.NewBuffer(jsonData))
    if err != nil {
        return err
    }
    httpReq.Header.Set("Content-Type", "application/json")
```
**Step 1:** Create HTTP POST request with JSON body

```go
    // Add API key for authentication
    apiKey := getAPIKeyForServer(serverURL)
    if apiKey != "" {
        httpReq.Header.Set("Authorization", "Bearer "+apiKey)
    }
```
**Step 2:** Add API key to Authorization header
**`getAPIKeyForServer()`** determines which API key to use based on URL:
- If URL is Server A → use `STORAGE_SERVER_A_API_KEY`
- If URL is Server B → use `STORAGE_SERVER_B_API_KEY`

```go
    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(httpReq)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(resp.Body)
        return fmt.Errorf("server returned %d: %s", resp.StatusCode, string(body))
    }

    return nil
}
```
**Step 3:** Send request with 10-second timeout
**Step 4:** Check response status (200 = success, 401 = unauthorized)

---

#### API Key Selection (`getAPIKeyForServer()`)

```go
func getAPIKeyForServer(serverURL string) string {
    serverAURL := os.Getenv("STORAGE_SERVER_A_URL")
    serverBURL := os.Getenv("STORAGE_SERVER_B_URL")

    if serverURL == serverAURL {
        return os.Getenv("STORAGE_SERVER_A_API_KEY")
    } else if serverURL == serverBURL {
        return os.Getenv("STORAGE_SERVER_B_API_KEY")
    }

    return ""
}
```

**How it works:**
1. Compare requested URL with known server URLs
2. Return appropriate API key
3. Each server gets its own key

**Example:**
```bash
# Environment has:
STORAGE_SERVER_A_URL=http://139.91.90.9:8080
STORAGE_SERVER_A_API_KEY=abc123def456...

STORAGE_SERVER_B_URL=http://139.91.90.156:8080
STORAGE_SERVER_B_API_KEY=xyz789ghi012...

# When storing on Server A:
getAPIKeyForServer("http://139.91.90.9:8080")
# Returns: abc123def456...

# When storing on Server B:
getAPIKeyForServer("http://139.91.90.156:8080")
# Returns: xyz789ghi012...
```

---

#### Retrieve from Server (`retrieveFromServer()`)

```go
func retrieveFromServer(server, filename string) {
    var serverURL string
    switch server {
    case "A", "serverA":
        serverURL = os.Getenv("STORAGE_SERVER_A_URL")
    case "B", "serverB":
        serverURL = os.Getenv("STORAGE_SERVER_B_URL")
    default:
        log.Fatal("Server must be 'A' or 'B'")
    }
```
**Step 1:** Determine which server to query

```go
    httpReq, err := http.NewRequest("GET", fmt.Sprintf("%s/retrieve?filename=%s", serverURL, filename), nil)
    if err != nil {
        log.Fatal("Failed to create request:", err)
    }

    // Add API key for authentication
    apiKey := getAPIKeyForServer(serverURL)
    if apiKey != "" {
        httpReq.Header.Set("Authorization", "Bearer "+apiKey)
    }
```
**Step 2:** Create GET request with API key

```go
    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(httpReq)
    if err != nil {
        log.Fatal("Failed to retrieve from server:", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode == http.StatusUnauthorized {
        log.Fatal("Authentication failed: Invalid or missing API key")
    }

    var result RetrieveResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        log.Fatal("Failed to decode response:", err)
    }

    if !result.Found {
        log.Fatal("File not found on server")
    }

    fmt.Print(result.Content)
}
```
**Step 3:** Send request, check auth, parse response, print content

---

#### Health Check (`healthCheck()`)

```go
func healthCheck() {
    serverA := os.Getenv("STORAGE_SERVER_A_URL")
    serverB := os.Getenv("STORAGE_SERVER_B_URL")

    fmt.Println("=== Storage Server Health Check ===")

    if err := checkServer("A", serverA); err != nil {
        fmt.Printf("❌ Server A (%s): %v\n", serverA, err)
    } else {
        fmt.Printf("✅ Server A (%s): healthy\n", serverA)
    }

    if err := checkServer("B", serverB); err != nil {
        fmt.Printf("❌ Server B (%s): %v\n", serverB, err)
    } else {
        fmt.Printf("✅ Server B (%s): healthy\n", serverB)
    }
}

func checkServer(name, url string) error {
    if url == "" {
        return fmt.Errorf("URL not configured")
    }

    client := &http.Client{Timeout: 5 * time.Second}
    resp, err := client.Get(url + "/health")
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("returned status %d", resp.StatusCode)
    }

    return nil
}
```

**What it does:** Check if both servers are reachable
**Note:** Health endpoint doesn't require authentication
**Used by:** Scripts before processing to ensure servers are up

---

## Client Scripts

### Encryption Script (`client-encrypt-daily.sh`)

**Purpose:** Complete workflow to encrypt and distribute daily IP list

```bash
#!/bin/bash
set -e
```
**`set -e`:** Exit immediately if any command fails
**Why?** Don't want to continue if encryption fails

```bash
DATE=${1:-$(date +%Y-%m-%d)}
DAILY_FILE="/daily-files/attackers_${DATE}.json"
```
**Parameters:**
- Takes date as argument, defaults to today
- Constructs filename: `attackers_2025-10-02.json`

```bash
if [ ! -f "$DAILY_FILE" ]; then
    echo "❌ Daily file not found: $DAILY_FILE"
    exit 1
fi
```
**Check:** File exists before processing

```bash
echo "🔍 Checking storage server connectivity..."
if ! sss-crypto-tool health-check; then
    echo "❌ Storage servers not accessible"
    exit 1
fi
```
**Pre-flight check:** Ensure both servers are up
**Prevents:** Starting encryption if can't store results

```bash
echo "🔑 Generating DEK..."
DEK=$(sss-crypto-tool generate-dek)
echo "DEK generated: ${DEK:0:16}... (truncated for display)"
```
**Step 1:** Generate random 256-bit key
**Stored in:** Shell variable `$DEK`
**Security:** Only in memory, never written to disk

```bash
echo "🔒 Encrypting attacker IP data..."
BUNDLE=$(sss-crypto-tool encrypt "$DAILY_FILE" "$DEK" "$DATE")
```
**Step 2:** Encrypt file with XChaCha20-Poly1305
**Result:** JSON bundle in `$BUNDLE` variable

```bash
echo "📤 Storing encrypted bundle on both storage servers..."
sss-crypto-tool store-on-servers "bundle_${DATE}.json" "$BUNDLE"
```
**Step 3:** Send encrypted bundle to BOTH servers
**Why both?** Redundancy - if one server dies, still have the data
**Filename:** `bundle_2025-10-02.json`

```bash
echo "✂️  Splitting DEK with Shamir's Secret Sharing (k=2, n=2)..."
SHARES=$(sss-crypto-tool split "$DEK" 2 2)
```
**Step 4:** Split DEK into 2 shares
**Output:**
```
share_A:bXlzaGFyZUFkYXRh...
share_B:bXlzaGFyZUJkYXRh...
```

```bash
SHARE_A=$(echo "$SHARES" | grep "share_A:" | cut -d: -f2)
SHARE_B=$(echo "$SHARES" | grep "share_B:" | cut -d: -f2)
```
**Step 5:** Parse out individual shares
**`grep "share_A:"`** finds line with Share A
**`cut -d: -f2`** extracts everything after the colon

```bash
echo "📤 Storing share A on Storage Server A..."
sss-crypto-tool store-on-server A "share_A_${DATE}.bin" "$SHARE_A"

echo "📤 Storing share B on Storage Server B..."
sss-crypto-tool store-on-server B "share_B_${DATE}.bin" "$SHARE_B"
```
**Step 6:** Store shares on SEPARATE servers
**Critical:** Share A ONLY on Server A, Share B ONLY on Server B
**Filenames:** `share_A_2025-10-02.bin`, `share_B_2025-10-02.bin`

```bash
echo "🗑️  Deleting processed file..."
rm "$DAILY_FILE"
```
**Step 7:** **DELETE ORIGINAL FILE**
**Security:** Remove plaintext from disk
**Why?** Original data no longer needed, everything is encrypted

```bash
unset DEK SHARES SHARE_A SHARE_B BUNDLE
```
**Step 8:** Clear sensitive variables from memory
**Defense in depth:** Minimize time secrets exist in memory

**Complete Flow Visualization:**

```
Input: /daily-files/attackers_2025-10-02.json (plaintext)
         ↓
      [Generate DEK]
         ↓
      [Encrypt with DEK] → Bundle (encrypted)
         ↓
      [Store bundle on A & B]
         ↓
      [Split DEK] → Share A + Share B
         ↓
      [Store Share A on A only]
      [Store Share B on B only]
         ↓
      [DELETE original file]
         ↓
      [Clear memory]

Result:
- Server A has: Bundle + Share A
- Server B has: Bundle + Share B
- Original file: DELETED ✅
- Memory: CLEARED ✅
```

---

### Decryption Script (`client-decrypt-view.sh`)

**Purpose:** Retrieve shares, reconstruct key, decrypt data, display to stdout

```bash
#!/bin/bash
set -e

DATE=${1:-$(date +%Y-%m-%d)}
```
**Parameter:** Date to decrypt (defaults to today)

```bash
echo "🔍 Checking storage server connectivity..."
if ! sss-crypto-tool health-check; then
    echo "❌ Storage servers not accessible"
    exit 1
fi
```
**Pre-flight check:** Ensure servers are reachable

```bash
echo "📥 Retrieving share A from Storage Server A..."
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_${DATE}.bin")

echo "📥 Retrieving share B from Storage Server B..."
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_${DATE}.bin")
```
**Step 1:** Retrieve BOTH shares
**Requires:** Valid API keys for both servers (client has them)
**Network:** Two separate HTTP requests with authentication

```bash
echo "🔑 Combining shares to reconstruct DEK..."
RECONSTRUCTED_DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")
echo "DEK reconstructed successfully"
```
**Step 2:** Use Shamir's algorithm to reconstruct original DEK
**Math:** Lagrange interpolation on 2 points

```bash
echo "📥 Retrieving encrypted bundle from Storage Server A..."
BUNDLE=$(sss-crypto-tool retrieve-from-server A "bundle_${DATE}.json")
```
**Step 3:** Retrieve encrypted data (could use Server B, doesn't matter)

```bash
echo "🔓 Decrypting bundle..."
DECRYPTED=$(sss-crypto-tool decrypt "$BUNDLE" "$RECONSTRUCTED_DEK")
```
**Step 4:** Decrypt with reconstructed key
**Includes:** Poly1305 authentication tag verification

```bash
echo ""
echo "🎯 Attacker IP addresses for $DATE:"
echo "==============================================="
echo "$DECRYPTED" | jq '.'
```
**Step 5:** Pretty-print JSON with `jq`
**Critical:** Data only displayed to stdout, NEVER saved to disk

```bash
if command -v jq >/dev/null 2>&1; then
    IP_COUNT=$(echo "$DECRYPTED" | jq '. | length' 2>/dev/null || echo "unknown")
    echo "📊 Total attacker IPs: $IP_COUNT"
fi
```
**Step 6:** Show statistics (count of IPs)

```bash
unset SHARE_A SHARE_B RECONSTRUCTED_DEK DECRYPTED BUNDLE
```
**Step 7:** Clear all sensitive data from memory

**Complete Flow Visualization:**

```
[Retrieve Share A from Server A] ←─ HTTP + API_KEY_A
        +
[Retrieve Share B from Server B] ←─ HTTP + API_KEY_B
        ↓
    [Combine shares] → DEK (reconstructed)
        ↓
[Retrieve Bundle from Server A or B]
        ↓
    [Decrypt with DEK]
        ↓
    [Verify MAC] → If valid, plaintext
        ↓
    [Display to stdout] (NO FILE WRITTEN!)
        ↓
    [Clear memory]

Security:
- Plaintext NEVER touches disk ✅
- Only exists briefly in memory ✅
- Memory cleared after display ✅
```

---

## Docker Configuration

### Client Dockerfile (`Dockerfile.client`)

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /build
COPY crypto-tools/ .
RUN go mod tidy
RUN go mod download
RUN go build -o sss-crypto-tool main.go
```
**Stage 1 - Builder:**
- Base: Go 1.21 on Alpine Linux (small)
- Copy crypto-tools source
- Download dependencies
- Compile binary

```dockerfile
FROM alpine:latest
RUN apk add --no-cache bash jq curl ca-certificates
```
**Stage 2 - Runtime:**
- Base: Alpine Linux (tiny, 5MB)
- Install runtime dependencies:
  - `bash` - For running scripts
  - `jq` - For JSON parsing
  - `curl` - For health checks
  - `ca-certificates` - For HTTPS (if added later)

```dockerfile
COPY --from=builder /build/sss-crypto-tool /usr/local/bin/sss-crypto-tool
```
**Copy compiled binary** from builder stage
**Result:** Final image has binary but not source code or build tools

```dockerfile
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh
```
**Copy and make scripts executable**

```dockerfile
RUN mkdir -p /daily-files /processed
```
**Create directories:**
- `/daily-files` - Input directory (mounted volume)
- `/processed` - Future use

```dockerfile
WORKDIR /app
CMD tail -f /dev/null
```
**Default command:** Keep container running
**Why `tail -f /dev/null`?** Container needs a running process or it exits

---

### Client Compose (`docker-compose-client.yml`)

```yaml
version: '3.8'

services:
  sss-client:
    build:
      context: .
      dockerfile: Dockerfile.client
    image: sss-client:latest
    container_name: sss-client
```
**Service definition:** Build from Dockerfile.client

```yaml
    volumes:
      - ./daily-files:/daily-files
      - ./scripts:/scripts
```
**Volumes:**
- Host `./daily-files` → Container `/daily-files` (input files)
- Host `./scripts` → Container `/scripts` (allows script updates without rebuild)

```yaml
    environment:
      - STORAGE_SERVER_A_URL=http://139.91.90.9:8080
      - STORAGE_SERVER_B_URL=http://139.91.90.156:8080
      - STORAGE_SERVER_A_API_KEY=${SERVER_A_API_KEY}
      - STORAGE_SERVER_B_API_KEY=${SERVER_B_API_KEY}
      - DAILY_FILES_DIR=/daily-files
```
**Environment variables:**
- Server URLs (hardcoded IPs)
- API keys (from `.env` file via `${...}` syntax)

**When started with `--env-file client.env`:**
```bash
# client.env contains:
SERVER_A_API_KEY=abc123def456...
SERVER_B_API_KEY=xyz789ghi012...

# Gets substituted into:
STORAGE_SERVER_A_API_KEY=abc123def456...
STORAGE_SERVER_B_API_KEY=xyz789ghi012...
```

```yaml
    restart: unless-stopped
```
**Restart policy:** Auto-restart if crashes (but not if manually stopped)

```yaml
    healthcheck:
      test: ["CMD", "sss-crypto-tool", "health-check"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```
**Health check:**
- Command: `sss-crypto-tool health-check`
- Run every 30 seconds
- Timeout after 10 seconds
- Retry 3 times before marking unhealthy
- Wait 30 seconds after start before checking

---

### Storage Server Dockerfile (`Dockerfile.server`)

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /build
COPY storage-server/ .
RUN go mod tidy
RUN go mod download
RUN go build -o sss-storage-server main.go
```
**Stage 1:** Compile storage server

```dockerfile
FROM alpine:latest
RUN apk add --no-cache ca-certificates wget
COPY --from=builder /build/sss-storage-server /usr/local/bin/sss-storage-server
EXPOSE 8080
CMD ["sss-storage-server"]
```
**Stage 2:**
- Install `wget` for healthcheck
- Copy binary
- Expose port 8080
- Run server

---

### Storage Server Compose (`docker-compose-server-a.yml`)

```yaml
version: '3.8'

services:
  storage-server-a:
    build:
      context: .
      dockerfile: Dockerfile.server
    image: sss-storage-server:latest
    container_name: sss-storage-server-a
```
**Service definition**

```yaml
    volumes:
      - ./data:/data
```
**Volume:** Host `./data` → Container `/data` (persistent storage)
**Result:** Stored files survive container restarts

```yaml
    ports:
      - "8080:8080"
```
**Port mapping:** Host 8080 → Container 8080

```yaml
    environment:
      - SERVER_ID=A
      - SERVER_PORT=8080
      - API_KEY_HASH=${SERVER_A_API_KEY_HASH}
```
**Environment:**
- `SERVER_ID=A` (for logging)
- `SERVER_PORT=8080`
- `API_KEY_HASH` from `.env` file

**When started with `--env-file server-a.env`:**
```bash
# server-a.env contains:
SERVER_A_API_KEY_HASH=7f8a9b0c1d2e...

# Gets substituted into:
API_KEY_HASH=7f8a9b0c1d2e...
```

```yaml
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```
**Health check:** Uses `wget` to test `/health` endpoint

**`docker-compose-server-b.yml` is identical except:**
- `container_name: sss-storage-server-b`
- `SERVER_ID=B`
- `API_KEY_HASH=${SERVER_B_API_KEY_HASH}`

---

## Data Flow Walkthrough

### Complete Encryption Flow

**Step-by-step with actual data:**

```bash
# 1. User places file
echo '["192.168.1.100", "10.0.0.5"]' > /tmp/sss-client/daily-files/attackers_2025-10-02.json

# 2. User runs encryption
docker exec sss-client /scripts/client-encrypt-daily.sh 2025-10-02
```

**Inside the script:**

```bash
# 3. Generate DEK (256-bit random key)
DEK=$(sss-crypto-tool generate-dek)
# DEK = "Ql0QOWyJw97PuuWQ..." (44 char base64)
```

```bash
# 4. Encrypt file
BUNDLE=$(sss-crypto-tool encrypt /daily-files/attackers_2025-10-02.json $DEK 2025-10-02)
# BUNDLE = {
#   "algorithm": "XChaCha20-Poly1305",
#   "nonce": "ZXhhbXBsZW5vbmNl...",
#   "ciphertext": "aDj3kL9mN...",
#   "date": "2025-10-02"
# }
```

```bash
# 5. Store bundle on BOTH servers
sss-crypto-tool store-on-servers "bundle_2025-10-02.json" "$BUNDLE"
```

**What happens:**
```
Client → POST http://139.91.90.9:8080/store
  Header: Authorization: Bearer abc123def456...
  Body: {"filename":"bundle_2025-10-02.json","content":"{...}"}

Server A:
  1. Extract key: abc123def456...
  2. Hash: SHA256(abc123def456...) = 7f8a9b0c1d2e...
  3. Compare with stored hash: MATCH ✅
  4. Write to /data/bundle_2025-10-02.json
  5. Return {"status":"success"}

Client → POST http://139.91.90.156:8080/store
  Header: Authorization: Bearer xyz789ghi012...
  Body: {"filename":"bundle_2025-10-02.json","content":"{...}"}

Server B:
  1. Extract key: xyz789ghi012...
  2. Hash: SHA256(xyz789ghi012...) = 3e4d5c6b7a8f...
  3. Compare with stored hash: MATCH ✅
  4. Write to /data/bundle_2025-10-02.json
  5. Return {"status":"success"}
```

```bash
# 6. Split DEK
SHARES=$(sss-crypto-tool split "$DEK" 2 2)
# SHARES = share_A:bXlzaGFyZUFkYXRh...
#          share_B:bXlzaGFyZUJkYXRh...

SHARE_A=bXlzaGFyZUFkYXRh...
SHARE_B=bXlzaGFyZUJkYXRh...
```

```bash
# 7. Store Share A on Server A ONLY
sss-crypto-tool store-on-server A "share_A_2025-10-02.bin" "$SHARE_A"
```

**What happens:**
```
Client → POST http://139.91.90.9:8080/store
  Header: Authorization: Bearer abc123def456...
  Body: {"filename":"share_A_2025-10-02.bin","content":"bXlzaGFy..."}

Server A:
  1. Authenticate ✅
  2. Write to /data/share_A_2025-10-02.bin
  3. Return success
```

```bash
# 8. Store Share B on Server B ONLY
sss-crypto-tool store-on-server B "share_B_2025-10-02.bin" "$SHARE_B"
```

**What happens:**
```
Client → POST http://139.91.90.156:8080/store
  Header: Authorization: Bearer xyz789ghi012...
  Body: {"filename":"share_B_2025-10-02.bin","content":"bXlzaGFy..."}

Server B:
  1. Authenticate ✅
  2. Write to /data/share_B_2025-10-02.bin
  3. Return success
```

```bash
# 9. DELETE original file
rm /daily-files/attackers_2025-10-02.json
```

**Result:**
```
Server A has:
  /data/bundle_2025-10-02.json (encrypted)
  /data/share_A_2025-10-02.bin

Server B has:
  /data/bundle_2025-10-02.json (encrypted)
  /data/share_B_2025-10-02.bin

Client has:
  Nothing on disk ✅
  (Original file deleted)
```

---

### Complete Decryption Flow

```bash
# 1. User runs decryption
docker exec sss-client /scripts/client-decrypt-view.sh 2025-10-02
```

**Inside the script:**

```bash
# 2. Retrieve Share A from Server A
SHARE_A=$(sss-crypto-tool retrieve-from-server A "share_A_2025-10-02.bin")
```

**What happens:**
```
Client → GET http://139.91.90.9:8080/retrieve?filename=share_A_2025-10-02.bin
  Header: Authorization: Bearer abc123def456...

Server A:
  1. Authenticate ✅
  2. Read /data/share_A_2025-10-02.bin
  3. Return {"content":"bXlzaGFy...","found":true}

Client receives: bXlzaGFy...
```

```bash
# 3. Retrieve Share B from Server B
SHARE_B=$(sss-crypto-tool retrieve-from-server B "share_B_2025-10-02.bin")
```

**What happens:**
```
Client → GET http://139.91.90.156:8080/retrieve?filename=share_B_2025-10-02.bin
  Header: Authorization: Bearer xyz789ghi012...

Server B:
  1. Authenticate ✅
  2. Read /data/share_B_2025-10-02.bin
  3. Return {"content":"bXlzaGFy...","found":true}

Client receives: bXlzaGFy...
```

```bash
# 4. Combine shares to reconstruct DEK
RECONSTRUCTED_DEK=$(sss-crypto-tool combine "$SHARE_A" "$SHARE_B")
```

**Math:**
```
Share A and Share B are points on a polynomial
Lagrange interpolation finds the polynomial
Extract constant term = original DEK
RECONSTRUCTED_DEK = Ql0QOWyJw97PuuWQ... (same as step 3 of encryption!)
```

```bash
# 5. Retrieve bundle
BUNDLE=$(sss-crypto-tool retrieve-from-server A "bundle_2025-10-02.json")
```

**Could retrieve from A or B (both have it):**
```
Client → GET http://139.91.90.9:8080/retrieve?filename=bundle_2025-10-02.json
  Header: Authorization: Bearer abc123def456...

Server A:
  1. Authenticate ✅
  2. Read /data/bundle_2025-10-02.json
  3. Return {"content":"{algorithm:...}","found":true}

Client receives: {algorithm:XChaCha20-Poly1305,...}
```

```bash
# 6. Decrypt
DECRYPTED=$(sss-crypto-tool decrypt "$BUNDLE" "$RECONSTRUCTED_DEK")
```

**Decryption process:**
```
1. Parse bundle JSON
2. Decode nonce from base64
3. Decode ciphertext+MAC from base64
4. Create XChaCha20-Poly1305 cipher with DEK
5. Extract last 16 bytes of ciphertext (the MAC)
6. Compute MAC over ciphertext + associated data
7. Compare MACs in constant time
8. If match: Decrypt ciphertext with XChaCha20
9. Return: ["192.168.1.100", "10.0.0.5"]
```

```bash
# 7. Display (NO FILE WRITTEN!)
echo "$DECRYPTED" | jq '.'
[
  "192.168.1.100",
  "10.0.0.5"
]
```

**Key point:** Plaintext only in shell variable `$DECRYPTED`, displayed to stdout, then cleared

```bash
# 8. Clear memory
unset SHARE_A SHARE_B RECONSTRUCTED_DEK DECRYPTED BUNDLE
```

---

## Security Mechanisms

### 1. Encryption: XChaCha20-Poly1305

**Components:**
- **XChaCha20:** Stream cipher (encrypts data)
- **Poly1305:** MAC (authenticates data)
- **Extended nonce:** 24 bytes (vs 12 for standard ChaCha20)

**Why XChaCha20-Poly1305?**
- Fast (stream cipher, not block)
- Secure (modern, audited)
- AEAD (encryption + authentication in one operation)
- Large nonce (can use random without collision risk)

**Security properties:**
- Confidentiality: Ciphertext reveals nothing about plaintext
- Authenticity: Any modification detected by MAC
- Associated data: Date is authenticated (can't be changed)

---

### 2. Key Splitting: Shamir's Secret Sharing

**Parameters:** k=2, n=2
- Need ALL shares to reconstruct
- Each share alone reveals ZERO information

**Math (simplified):**
```
Secret S = 42
Random coefficient R = 7
Polynomial: f(x) = 42 + 7x

Share 1: f(1) = 49
Share 2: f(2) = 56

To reconstruct:
Two points define a line
Find y-intercept = 42 ✅
```

**Information theory:**
- With 1 share: Infinite possible secrets (uniformly distributed)
- With 2 shares: Unique secret determined

---

### 3. Authentication: API Key + Hash

**Design:**
- Client has plaintext keys
- Servers have SHA256 hashes
- Client sends key in `Authorization` header
- Server hashes received key and compares

**Why hash on server?**
```
If Server A compromised:
  Attacker gets: HASH(API_KEY_A)
  Attacker wants: API_KEY_A
  Problem: Cannot reverse SHA256
  Result: Cannot impersonate client ✅
```

**Why separate keys?**
```
If Server A compromised:
  Attacker gets: HASH(API_KEY_A)
  To query Server B: Need API_KEY_B
  Server A doesn't have API_KEY_B ✅
  Result: Cannot retrieve Share B ✅
```

---

### 4. No Plaintext Persistence

**Encryption script:**
- Line 54: `rm "$DAILY_FILE"` - Delete original
- Line 66: `unset DEK SHARES SHARE_A SHARE_B BUNDLE` - Clear memory

**Decryption script:**
- Line 40: Comment explicitly states "NO plaintext files saved to disk"
- Line 38: `echo "$DECRYPTED" | jq '.'` - Display only, no write
- Line 52: `unset SHARE_A SHARE_B RECONSTRUCTED_DEK DECRYPTED BUNDLE` - Clear memory

**Result:**
- Plaintext exists only during encryption/decryption
- Never written to disk after encryption
- Memory cleared immediately after use

---

### 5. Defense Against Common Attacks

**Path Traversal:**
```go
filename := filepath.Base(req.Filename)
```
- Strips `../../` attempts
- Filename: `../../etc/passwd` → `passwd`

**Timing Attacks:**
```go
subtle.ConstantTimeCompare([]byte(providedHash), []byte(apiKeyHash))
```
- All comparisons take same time
- Prevents guessing hash byte-by-byte

**Tampering:**
```go
plaintext, err := aead.Open(nil, nonce, ciphertext, ad)
if err != nil {
    log.Fatal("Decryption failed (auth tag verification failed):", err)
}
```
- Poly1305 MAC verification
- Any byte changed → MAC mismatch → Decryption fails

**Replay Attacks:**
- Not explicitly prevented (future enhancement: add timestamps)
- Mitigated by: Each date has unique files, old requests are harmless

---

## Summary

**This system implements:**

✅ **End-to-end encryption** - Data encrypted before leaving client
✅ **Split trust** - No single server can decrypt
✅ **Authentication** - API keys prevent unauthorized access
✅ **No plaintext persistence** - Original files deleted
✅ **Tamper detection** - Poly1305 MAC verifies integrity
✅ **Secure key splitting** - Shamir's Secret Sharing (information-theoretic security)
✅ **Defense in depth** - Multiple layers (encryption, splitting, auth, deletion)

**Key insight:** The security comes from combining multiple techniques:
1. Encryption protects confidentiality
2. Shamir splitting prevents single-point compromise
3. Authentication prevents unauthorized access
4. Deletion prevents plaintext leakage
5. MAC prevents tampering

No single technique would be sufficient alone, but together they create a robust system.
