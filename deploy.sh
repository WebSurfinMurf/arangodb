#!/bin/bash
set -e

PROJECT_NAME="arangodb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying ArangoDB AI Memory Store ==="

# Verify environment file exists
if [ ! -f "$HOME/projects/secrets/${PROJECT_NAME}.env" ]; then
    echo "Error: Environment file not found at $HOME/projects/secrets/${PROJECT_NAME}.env"
    exit 1
fi

# Load environment
source "$HOME/projects/secrets/${PROJECT_NAME}.env"

# Verify required secrets
if [ -z "$ARANGO_ROOT_PASSWORD" ]; then
    echo "Error: ARANGO_ROOT_PASSWORD not set in environment file"
    exit 1
fi

if [ -z "$OAUTH2_PROXY_CLIENT_SECRET" ]; then
    echo "Error: OAUTH2_PROXY_CLIENT_SECRET not set in environment file"
    exit 1
fi

# Create networks
echo "Creating Docker networks..."
docker network create arangodb-net 2>/dev/null || echo "Network arangodb-net already exists"
docker network inspect traefik-net >/dev/null 2>&1 || docker network create traefik-net
docker network inspect keycloak-net >/dev/null 2>&1 || docker network create keycloak-net

# Create data directories
echo "Creating data directories..."
mkdir -p "$HOME/projects/data/arangodb"
mkdir -p "$HOME/projects/data/arangodb-apps"
mkdir -p "$HOME/projects/data/arangodb/backups"

# Deploy using docker compose
echo "Deploying containers..."
cd "$SCRIPT_DIR"
docker compose down
docker compose up -d

# Wait for ArangoDB to start
echo "Waiting for ArangoDB to become healthy..."
for i in {1..30}; do
    if docker exec arangodb curl -f http://localhost:8529/_api/version >/dev/null 2>&1; then
        echo "✅ ArangoDB is healthy"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Verify deployment
echo ""
echo "=== Deployment Verification ==="
echo "ArangoDB container: $(docker ps --filter name=arangodb --format '{{.Status}}')"
echo "Auth proxy container: $(docker ps --filter name=arangodb-auth-proxy --format '{{.Status}}')"
echo ""
echo "Access: https://arangodb.ai-servicers.com (OAuth2 protected)"
echo "Root user: root"
echo "Root password: <see $HOME/projects/secrets/arangodb.env>"
echo ""
echo "=== Deployment Complete ==="
