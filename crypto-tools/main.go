package main

import (
    "bytes"
    "crypto/rand"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "net/http"
    "os"
    "time"

    "github.com/hashicorp/vault/shamir"
    "golang.org/x/crypto/chacha20poly1305"
)

type CipherBundle struct {
    Algorithm      string `json:"algorithm"`
    Nonce         string `json:"nonce"`         // base64
    Ciphertext    string `json:"ciphertext"`    // base64  
    AuthTag       string `json:"auth_tag"`      // base64 (if separate)
    AssociatedData string `json:"associated_data,omitempty"`
    Date          string `json:"date"`
}

type StoreRequest struct {
    Filename string `json:"filename"`
    Content  string `json:"content"`
}

type RetrieveResponse struct {
    Content string `json:"content"`
    Found   bool   `json:"found"`
}

func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: crypto-tool <command> [args...]")
        fmt.Println("Commands:")
        fmt.Println("  generate-dek                         - Generate 32-byte DEK")
        fmt.Println("  encrypt <plaintext> <dek> <date>     - Encrypt with XChaCha20-Poly1305")
        fmt.Println("  decrypt <bundle> <dek>               - Decrypt bundle")
        fmt.Println("  split <dek> <k> <n>                  - Split DEK with SSS")
        fmt.Println("  combine <share1> <share2> [shareN...] - Combine shares")
        fmt.Println("  store-on-servers <filename> <content> - Store content on both servers")
        fmt.Println("  retrieve-from-server <server> <filename> - Retrieve from specific server")
        fmt.Println("  health-check                         - Check server connectivity")
        os.Exit(1)
    }

    command := os.Args[1]
    
    switch command {
    case "generate-dek":
        generateDEK()
    case "encrypt":
        if len(os.Args) != 5 {
            log.Fatal("Usage: encrypt <plaintext_file> <dek_b64> <date>")
        }
        encrypt(os.Args[2], os.Args[3], os.Args[4])
    case "decrypt":
        if len(os.Args) != 4 {
            log.Fatal("Usage: decrypt <bundle_file_or_content> <dek_b64>")
        }
        decrypt(os.Args[2], os.Args[3])
    case "split":
        if len(os.Args) != 5 {
            log.Fatal("Usage: split <dek_b64> <k> <n>")
        }
        split(os.Args[2], os.Args[3], os.Args[4])
    case "combine":
        if len(os.Args) < 4 {
            log.Fatal("Usage: combine <share1_content> <share2_content> [shareN_content...]")
        }
        combineShares(os.Args[2:])
    case "store-on-servers":
        if len(os.Args) != 4 {
            log.Fatal("Usage: store-on-servers <filename> <content>")
        }
        storeOnServers(os.Args[2], os.Args[3])
    case "store-on-server":
        if len(os.Args) != 5 {
            log.Fatal("Usage: store-on-server <server> <filename> <content>")
        }
        storeOnSpecificServer(os.Args[2], os.Args[3], os.Args[4])
    case "retrieve-from-server":
        if len(os.Args) != 4 {
            log.Fatal("Usage: retrieve-from-server <server> <filename>")
        }
        retrieveFromServer(os.Args[2], os.Args[3])
    case "health-check":
        healthCheck()
    default:
        log.Fatal("Unknown command:", command)
    }
}

func storeOnServers(filename, content string) {
    serverA := os.Getenv("STORAGE_SERVER_A_URL")
    serverB := os.Getenv("STORAGE_SERVER_B_URL")

    // Fallback to old environment variable names for backward compatibility
    if serverA == "" {
        serverA = os.Getenv("SERVER_A_URL")
    }
    if serverB == "" {
        serverB = os.Getenv("SERVER_B_URL")
    }

    if serverA == "" || serverB == "" {
        log.Fatal("STORAGE_SERVER_A_URL and STORAGE_SERVER_B_URL environment variables required")
    }

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

func storeOnServer(serverURL string, req StoreRequest) error {
    jsonData, err := json.Marshal(req)
    if err != nil {
        return err
    }

    resp, err := http.Post(serverURL+"/store", "application/json", bytes.NewBuffer(jsonData))
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

func storeOnSpecificServer(server, filename, content string) {
    var serverURL string
    switch server {
    case "A", "serverA":
        serverURL = os.Getenv("STORAGE_SERVER_A_URL")
        if serverURL == "" {
            serverURL = os.Getenv("SERVER_A_URL") // Fallback
        }
    case "B", "serverB":
        serverURL = os.Getenv("STORAGE_SERVER_B_URL")
        if serverURL == "" {
            serverURL = os.Getenv("SERVER_B_URL") // Fallback
        }
    default:
        log.Fatal("Server must be 'A' or 'B'")
    }

    if serverURL == "" {
        log.Fatal("Server URL not configured")
    }

    req := StoreRequest{
        Filename: filename,
        Content:  content,
    }

    if err := storeOnServer(serverURL, req); err != nil {
        log.Fatalf("Failed to store on Server %s: %v", server, err)
    }
    fmt.Printf("✅ Stored %s on Server %s\n", filename, server)
}

func retrieveFromServer(server, filename string) {
    var serverURL string
    switch server {
    case "A", "serverA":
        serverURL = os.Getenv("STORAGE_SERVER_A_URL")
        if serverURL == "" {
            serverURL = os.Getenv("SERVER_A_URL") // Fallback
        }
    case "B", "serverB":
        serverURL = os.Getenv("STORAGE_SERVER_B_URL")
        if serverURL == "" {
            serverURL = os.Getenv("SERVER_B_URL") // Fallback
        }
    default:
        log.Fatal("Server must be 'A' or 'B'")
    }

    if serverURL == "" {
        log.Fatal("Server URL not configured")
    }

    resp, err := http.Get(fmt.Sprintf("%s/retrieve?filename=%s", serverURL, filename))
    if err != nil {
        log.Fatal("Failed to retrieve from server:", err)
    }
    defer resp.Body.Close()

    var result RetrieveResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        log.Fatal("Failed to decode response:", err)
    }

    if !result.Found {
        log.Fatal("File not found on server")
    }

    fmt.Print(result.Content)
}

func healthCheck() {
    serverA := os.Getenv("STORAGE_SERVER_A_URL")
    serverB := os.Getenv("STORAGE_SERVER_B_URL")

    // Fallback to old environment variable names
    if serverA == "" {
        serverA = os.Getenv("SERVER_A_URL")
    }
    if serverB == "" {
        serverB = os.Getenv("SERVER_B_URL")
    }

    fmt.Println("=== Storage Server Health Check ===")
    
    // Check Server A
    if err := checkServer("A", serverA); err != nil {
        fmt.Printf("❌ Server A (%s): %v\n", serverA, err)
    } else {
        fmt.Printf("✅ Server A (%s): healthy\n", serverA)
    }
    
    // Check Server B
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

func generateDEK() {
    key := make([]byte, 32)
    if _, err := rand.Read(key); err != nil {
        log.Fatal("Failed to generate DEK:", err)
    }
    fmt.Print(base64.StdEncoding.EncodeToString(key))
}

func encrypt(plaintextFile, dekB64, date string) {
    // Read plaintext
    plaintext, err := os.ReadFile(plaintextFile)
    if err != nil {
        log.Fatal("Failed to read plaintext:", err)
    }
    
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
    
    // Generate nonce
    nonce := make([]byte, aead.NonceSize())
    if _, err := rand.Read(nonce); err != nil {
        log.Fatal("Failed to generate nonce:", err)
    }
    
    // Associated data (date)
    ad := []byte(date)
    
    // Encrypt
    ciphertext := aead.Seal(nil, nonce, plaintext, ad)
    
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

func decrypt(bundleInput, dekB64 string) {
    var bundleData []byte
    var err error

    // Try to read as file first, then treat as direct content
    if bundleData, err = os.ReadFile(bundleInput); err != nil {
        bundleData = []byte(bundleInput)
    }
    
    var bundle CipherBundle
    if err := json.Unmarshal(bundleData, &bundle); err != nil {
        log.Fatal("Failed to parse bundle:", err)
    }
    
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
    
    // Decode components
    nonce, err := base64.StdEncoding.DecodeString(bundle.Nonce)
    if err != nil {
        log.Fatal("Failed to decode nonce:", err)
    }
    
    ciphertext, err := base64.StdEncoding.DecodeString(bundle.Ciphertext)
    if err != nil {
        log.Fatal("Failed to decode ciphertext:", err)
    }
    
    // Decrypt
    ad := []byte(bundle.AssociatedData)
    plaintext, err := aead.Open(nil, nonce, ciphertext, ad)
    if err != nil {
        log.Fatal("Decryption failed (auth tag verification failed):", err)
    }
    
    fmt.Print(string(plaintext))
}

func split(dekB64, kStr, nStr string) {
    // Parse parameters
    k := parseInt(kStr)
    n := parseInt(nStr)
    
    // Decode DEK
    dek, err := base64.StdEncoding.DecodeString(dekB64)
    if err != nil {
        log.Fatal("Failed to decode DEK:", err)
    }
    
    // Split with Shamir's Secret Sharing
    shares, err := shamir.Split(dek, n, k)
    if err != nil {
        log.Fatal("Failed to split secret:", err)
    }
    
    // Output shares as base64, one per line
    for i, share := range shares {
        fmt.Printf("share_%c:%s\n", 'A'+i, base64.StdEncoding.EncodeToString(share))
    }
}

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
    
    // Combine shares
    secret, err := shamir.Combine(shares)
    if err != nil {
        log.Fatal("Failed to combine shares:", err)
    }
    
    fmt.Print(base64.StdEncoding.EncodeToString(secret))
}

func parseInt(s string) int {
    var i int
    fmt.Sscanf(s, "%d", &i)
    return i
}
