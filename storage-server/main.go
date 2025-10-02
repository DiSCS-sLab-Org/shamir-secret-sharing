package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type StoreRequest struct {
	Filename string `json:"filename"`
	Content  string `json:"content"`
}

type RetrieveResponse struct {
	Content string `json:"content"`
	Found   bool   `json:"found"`
}

type HealthResponse struct {
	Status   string `json:"status"`
	ServerID string `json:"server_id"`
}

const dataDir = "/data"

var (
	apiKeyHash string
	serverID   string
)

func main() {
	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatal("Failed to create data directory:", err)
	}

	serverID = os.Getenv("SERVER_ID")
	if serverID == "" {
		serverID = "unknown"
	}

	// Load API key hash (SHA256 of the actual API key)
	apiKeyHash = os.Getenv("API_KEY_HASH")
	if apiKeyHash == "" {
		log.Fatal("API_KEY_HASH environment variable is required")
	}

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(HealthResponse{
			Status:   "healthy",
			ServerID: serverID,
		})
	})

	http.HandleFunc("/store", authenticateRequest(handleStore))
	http.HandleFunc("/retrieve", authenticateRequest(handleRetrieve))

	log.Printf("Storage Server %s starting on port %s...", serverID, port)
	log.Printf("Data directory: %s", dataDir)
	log.Printf("Authentication: ENABLED (API key hash: %s...)", apiKeyHash[:16])

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("Server failed:", err)
	}
}

// authenticateRequest is a middleware that verifies the API key
func authenticateRequest(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Extract API key from Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			log.Printf("UNAUTHORIZED: Missing Authorization header from %s", r.RemoteAddr)
			http.Error(w, "Unauthorized: Missing API key", http.StatusUnauthorized)
			return
		}

		// Expected format: "Bearer <api-key>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			log.Printf("UNAUTHORIZED: Invalid Authorization format from %s", r.RemoteAddr)
			http.Error(w, "Unauthorized: Invalid API key format", http.StatusUnauthorized)
			return
		}

		providedKey := parts[1]

		// Hash the provided key
		hasher := sha256.New()
		hasher.Write([]byte(providedKey))
		providedHash := hex.EncodeToString(hasher.Sum(nil))

		// Constant-time comparison to prevent timing attacks
		if subtle.ConstantTimeCompare([]byte(providedHash), []byte(apiKeyHash)) != 1 {
			log.Printf("UNAUTHORIZED: Invalid API key from %s (hash: %s...)", r.RemoteAddr, providedHash[:16])
			http.Error(w, "Unauthorized: Invalid API key", http.StatusUnauthorized)
			return
		}

		// Log successful authentication
		log.Printf("AUTHENTICATED: Request from %s to %s", r.RemoteAddr, r.URL.Path)

		// Call the actual handler
		next(w, r)
	}
}

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

	if req.Filename == "" {
		http.Error(w, "Filename is required", http.StatusBadRequest)
		return
	}

	// Security: prevent path traversal
	filename := filepath.Base(req.Filename)
	filePath := filepath.Join(dataDir, filename)

	if err := os.WriteFile(filePath, []byte(req.Content), 0644); err != nil {
		log.Printf("Failed to write file %s: %v", filename, err)
		http.Error(w, "Failed to store file", http.StatusInternalServerError)
		return
	}

	log.Printf("Stored file: %s (%d bytes)", filename, len(req.Content))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": "File stored successfully",
	})
}

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

	log.Printf("Retrieved file: %s (%d bytes)", filename, len(content))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(RetrieveResponse{
		Content: string(content),
		Found:   true,
	})
}
