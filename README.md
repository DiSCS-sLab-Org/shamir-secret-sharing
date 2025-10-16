# Shamir's Secret Sharing Docker Lab

A distributed cryptographic system implementing Shamir's Secret Sharing (SSS) for secure data encryption and storage across multiple servers. This lab demonstrates a practical implementation of threshold cryptography with authenticated API access.

## Overview

This project encrypts sensitive data and stores it on two independent storage servers, while splitting the encryption key using Shamir's Secret Sharing algorithm. The system ensures that:
- Encrypted data is stored on both servers
- The encryption key is split into shares, with each server holding one share
- No single server can decrypt the data independently
- Both servers must be available to reconstruct the encryption key and decrypt the data
- Each server authenticates clients using unique API keys
- Servers cannot impersonate the client (hash-based authentication)

## Architecture

```
┌─────────────────┐
│  Client Server  │
│   (Encryption)  │
│                 │
│  - Generates    │
│    DEK          │
│  - Encrypts     │
│    data         │
│  - Splits DEK   │
│  - Stores       │
│    shares       │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│Server │ │Server │
│   A   │ │   B   │
│       │ │       │
│ Data  │ │ Data  │
│Share_A│ │Share_B│
└───────┘ └───────┘
```

## Key Components

### 1. Storage Server (Go)
- **Location**: `storage-server/main.go`
- **Purpose**: HTTP API for storing and retrieving encrypted data and key shares
- **Features**:
  - API key authentication (SHA256 hash verification)
  - RESTful endpoints (`/store`, `/retrieve`, `/health`)
  - Path traversal protection
  - Request logging

### 2. Crypto Tools Client (Go)
- **Location**: `crypto-tools/main.go`
- **Purpose**: Command-line tool for encryption operations
- **Capabilities**:
  - DEK generation (32-byte random keys)
  - XChaCha20-Poly1305 encryption/decryption
  - Shamir's Secret Sharing (split/combine)
  - Authenticated server communication
  - Health checks

### 3. Deployment Script

#### `deploy-with-auth.sh`
Complete automated deployment script that:
- **Generates fresh API keys internally** (using OpenSSL)
- Uploads code to remote servers via SSH
- Deploys Docker containers
- Runs authentication tests

**Usage**:
```bash
./deploy-with-auth.sh tmp   # Deploy to /tmp (testing)
./deploy-with-auth.sh prod  # Deploy to ~/ (production)
```

**Note**: This script handles all key generation internally. There is no need for a separate key generation script.

## Technologies Used

### Programming Languages
- **Go 1.x**: Core implementation language
- **Bash**: Deployment automation

### Cryptographic Libraries
- **XChaCha20-Poly1305**: Authenticated encryption (`golang.org/x/crypto/chacha20poly1305`)
- **Shamir's Secret Sharing**: Key splitting (`github.com/hashicorp/vault/shamir`)
- **SHA256**: API key hashing (`crypto/sha256`)

### Infrastructure
- **Docker**: Containerization
- **Docker Compose**: Multi-container orchestration
- **HTTP/REST**: Server communication protocol

### Key Dependencies
```
golang.org/x/crypto/chacha20poly1305
github.com/hashicorp/vault/shamir
```

## Security Features

1. **Hash-Based Authentication**
   - Servers store only SHA256 hashes of API keys
   - Constant-time comparison to prevent timing attacks
   - Per-server unique keys

2. **Zero-Knowledge Architecture**
   - Server A cannot authenticate to Server B
   - Servers store encrypted data but cannot decrypt it independently
   - Requires threshold (k) shares to reconstruct the encryption key

3. **Cryptographic Strength**
   - 32-byte (256-bit) encryption keys
   - XChaCha20-Poly1305 AEAD encryption
   - Authenticated encryption with associated data (AEAD)

## Quick Start

### Prerequisites
- Docker and Docker Compose
- SSH access to target servers (for deployment)
- OpenSSL (for key generation)

### Local Testing
```bash
# Build and run storage server A
cd docker
docker-compose -f docker-compose-server-a.yml --env-file ../server-a.env up --build

# Build and run client (in another terminal)
docker-compose -f docker-compose-client.yml --env-file ../client.env up --build
```

### Remote Deployment
```bash
# Deploy to test environment (/tmp)
./deploy-with-auth.sh tmp

# Deploy to production (home directory)
./deploy-with-auth.sh prod
```

The deployment script will:
1. Generate API keys automatically
2. Create `.env` files for each server
3. Upload all necessary files via SSH
4. Build and start Docker containers
5. Test authentication

## Usage

### Encrypt Data
```bash
docker exec sss-client /scripts/client-encrypt-daily.sh [YYYY-MM-DD]
```

This script:
- Reads data from `/data/attackers_YYYY-MM-DD.json`
- Encrypts using XChaCha20-Poly1305
- Splits encryption key using Shamir's Secret Sharing
- Stores encrypted bundle on both storage servers
- Stores key shares separately (Share A on Server A, Share B on Server B)
- Deletes original file

### Decrypt Data
```bash
docker exec sss-client /scripts/client-decrypt-view.sh [YYYY-MM-DD]
```

This script:
- Retrieves key shares from both storage servers
- Reconstructs encryption key using Shamir's Secret Sharing
- Retrieves encrypted data bundle from storage server
- Decrypts data using reconstructed key
- Saves decrypted file to `/data/attackers_YYYY-MM-DD.json`

## Project Structure

```
sss-docker-lab/
├── storage-server/       # Go HTTP server for share storage
│   ├── main.go          # Server implementation with auth
│   └── go.mod           # Go module definition
├── crypto-tools/         # Go CLI tool for crypto operations
│   ├── main.go          # Encryption/SSS implementation
│   ├── go.mod
│   └── go.sum
├── docker/              # Container definitions
│   ├── Dockerfile.server      # Storage server image
│   ├── Dockerfile.client      # Client tools image
│   ├── docker-compose-server-a.yml
│   ├── docker-compose-server-b.yml
│   └── docker-compose-client.yml
├── scripts/             # Automation scripts
│   ├── client-encrypt-daily.sh      # Encryption workflow
│   ├── client-decrypt-view.sh       # Decryption workflow
│   └── *.sh                         # Additional utilities
├── deploy-with-auth.sh  # Full deployment automation (includes key generation)
├── LICENSE              # MIT License
├── NOTICE              # Third-party software attributions
└── README.md           # This file
```

## API Endpoints

### Storage Server

#### POST /store
Store encrypted data or key share on server.
```json
{
  "filename": "share_A.bin",
  "content": "base64_encoded_data"
}
```
**Authentication**: Required (Bearer token)

#### GET /retrieve?filename=share_A.bin
Retrieve encrypted data or key share.
**Response**:
```json
{
  "content": "base64_encoded_data",
  "found": true
}
```
**Authentication**: Required (Bearer token)

#### GET /health
Health check endpoint (no authentication required).
```json
{
  "status": "healthy",
  "server_id": "A"
}
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Copyright (c) 2024 FORTH - Foundation for Research and Technology Hellas**

### Third-Party Software

This project uses third-party libraries. See the [NOTICE](NOTICE) file for detailed attribution and license information for:
- Shamir's Secret Sharing implementation (HashiCorp Vault - MPL-2.0)
- XChaCha20-Poly1305 cryptography (Go Authors - BSD-3-Clause)

## Security Considerations

- **Store `client.env` securely** - contains plaintext API keys
- **Rotate API keys regularly** by re-running `deploy-with-auth.sh`
- **Use HTTPS/TLS** in production environments
- **Implement network segmentation** between servers
- **Monitor authentication logs** for suspicious activity
- **Back up encrypted shares** separately from the client
- **Delete local `.env` files** after successful deployment
