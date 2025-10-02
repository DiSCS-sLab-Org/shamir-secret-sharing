package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
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

func main() {
	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Fatal("Failed to create data directory:", err)
	}

	serverID := os.Getenv("SERVER_ID")
	if serverID == "" {
		serverID = "unknown"
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

	http.HandleFunc("/store", handleStore)
	http.HandleFunc("/retrieve", handleRetrieve)

	log.Printf("Storage Server %s starting on port %s...", serverID, port)
	log.Printf("Data directory: %s", dataDir)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("Server failed:", err)
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
