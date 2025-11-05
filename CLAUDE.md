# ArangoDB AI Memory Store

## Overview

ArangoDB deployment configured as an AI memory/context store with OAuth2/Keycloak authentication. This provides persistent, queryable storage for AI conversation history, knowledge graphs, and semantic memory.

**Project Type:** Database Service (AI Memory Store)
**Deployment Date:** 2025-10-14
**Status:** Production
**Primary DNS:** https://arangodb.ai-servicers.com

## Architecture

### Components

1. **ArangoDB 3.11** - Multi-model database (document, graph, key-value)
   - Container: `arangodb`
   - Internal port: 8529
   - Network: `arangodb-net` (isolated)
   - Data: `/home/administrator/projects/data/arangodb`

2. **OAuth2 Proxy (latest)** - Authentication gateway
   - Container: `arangodb-auth-proxy`
   - External port: 4180
   - Networks: `traefik-net`, `keycloak-net`, `arangodb-net`
   - Keycloak integration with hybrid URL strategy

### Network Isolation

```
Internet → Traefik (traefik-net)
              ↓
         OAuth2 Proxy (traefik-net + keycloak-net + arangodb-net)
              ↓
         ArangoDB (arangodb-net only - isolated)
```

The backend database is **not** directly accessible from `traefik-net`, ensuring security through the authentication proxy.

### Databases

- `_system` - Default ArangoDB system database
- `ai_memory` - Main database for AI context/memory storage

## Configuration

### Environment Variables

Location: `$HOME/projects/secrets/arangodb.env`

**ArangoDB Settings:**
- `ARANGO_ROOT_PASSWORD` - Root user password (44 chars base64)

**OAuth2 Proxy Settings (Hybrid URL Strategy):**
- `OAUTH2_PROXY_CLIENT_ID=arangodb`
- `OAUTH2_PROXY_CLIENT_SECRET` - Keycloak client secret
- `OAUTH2_PROXY_COOKIE_SECRET` - 32-byte session cookie encryption key
- `OAUTH2_PROXY_COOKIE_NAME=_arangodb_oauth2_proxy`
- `OAUTH2_PROXY_PROVIDER=keycloak-oidc`
- `OAUTH2_PROXY_OIDC_ISSUER_URL=https://keycloak.ai-servicers.com/realms/master` - External HTTPS for token validation
- `OAUTH2_PROXY_LOGIN_URL=https://keycloak.ai-servicers.com/realms/master/protocol/openid-connect/auth` - Browser uses external
- `OAUTH2_PROXY_REDEEM_URL=http://keycloak:8080/realms/master/protocol/openid-connect/token` - Backend uses internal
- `OAUTH2_PROXY_OIDC_JWKS_URL=http://keycloak:8080/realms/master/protocol/openid-connect/certs` - Backend uses internal
- `OAUTH2_PROXY_SKIP_OIDC_DISCOVERY=true` - Required for hybrid URL approach
- `OAUTH2_PROXY_REDIRECT_URL=https://arangodb.ai-servicers.com/oauth2/callback`
- `OAUTH2_PROXY_ALLOWED_GROUPS=/administrators` - Full path required
- `OAUTH2_PROXY_UPSTREAMS=http://arangodb:8529`

### Keycloak Client

**Client ID:** `arangodb`
**Client Type:** Confidential (client authentication ON)
**Valid Redirect URIs:**
- `https://arangodb.ai-servicers.com/*`
- `https://arangodb.ai-servicers.com/oauth2/callback`

**Valid Post Logout Redirect URIs:**
- `https://arangodb.ai-servicers.com/*`

**Web Origins:**
- `https://arangodb.ai-servicers.com`

**Access Control:** `administrators` group

**Client Scopes:**
- `arangodb-dedicated` - Has only **groups** mapper (NO audience mapper)
- Mapper configuration:
  - Name: `groups`
  - Token Claim Name: `groups`
  - Full group path: ON
  - Add to ID token: ON
  - Add to access token: ON
  - Add to userinfo: ON

## Deployment

### Initial Deployment

```bash
cd /home/administrator/projects/arangodb
./deploy.sh
```

The deployment script:
1. Validates environment file exists
2. Verifies required secrets are set
3. Creates Docker networks (`arangodb-net`, `traefik-net`, `keycloak-net`)
4. Creates data directories with backup folder
5. Deploys containers via docker-compose
6. Waits for ArangoDB health check (up to 60 seconds)
7. Verifies both containers are running

### Manual Operations

**Restart services:**
```bash
cd /home/administrator/projects/arangodb
docker compose restart
```

**View logs:**
```bash
docker logs -f arangodb
docker logs -f arangodb-auth-proxy
```

**Access ArangoDB shell:**
```bash
docker exec -it arangodb arangosh \
  --server.endpoint tcp://127.0.0.1:8529 \
  --server.username root \
  --server.password="<password_from_env_file>"
```

**Access via API:**
```bash
curl -u root:<password> http://<container_ip>:8529/_api/version
```

### Database Management

**Create a database:**
```bash
curl -X POST "http://<container_ip>:8529/_api/database" \
  -H "Content-Type: application/json" \
  -u "root:<password>" \
  -d '{"name":"database_name"}'
```

**List databases:**
```bash
curl -u root:<password> http://<container_ip>:8529/_api/database
```

## Access

### Web Interface

**URL:** https://arangodb.ai-servicers.com
**Authentication:** OAuth2 via Keycloak (administrators group)
**Features:**
- Web UI for database management
- Query editor (AQL - ArangoDB Query Language)
- Graph visualization
- Collection/document management

### API Access

**Internal (from Docker containers):**
- Endpoint: `http://arangodb:8529`
- Auth: Basic auth with root credentials
- Network: Must be on `arangodb-net`

**External (via OAuth2 proxy):**
- Endpoint: `https://arangodb.ai-servicers.com`
- Auth: OAuth2/Keycloak session

## Data Persistence

### Volume Mounts

```
/home/administrator/projects/data/arangodb → /var/lib/arangodb3
/home/administrator/projects/data/arangodb-apps → /var/lib/arangodb3-apps
```

### Backups

**Backup directory:** `/home/administrator/projects/data/arangodb/backups`

**Manual backup (recommended method):**
```bash
# Using arangodump
docker exec arangodb arangodump \
  --server.username root \
  --server.password="<password>" \
  --server.database ai_memory \
  --output-directory /var/lib/arangodb3/backups/ai_memory_$(date +%Y%m%d_%H%M%S)
```

**Restore from backup:**
```bash
docker exec arangodb arangorestore \
  --server.username root \
  --server.password="<password>" \
  --server.database ai_memory \
  --input-directory /var/lib/arangodb3/backups/ai_memory_YYYYMMDD_HHMMSS
```

## Troubleshooting

### OAuth2 Proxy Issues

**Issue:** "audience claims [aud] do not exist in claims" (500 Internal Server Error)
```
Error creating session during OAuth2 callback:
audience claims [aud] do not exist in claims
```

**Root Cause:** OAuth2 proxy v7.6.0 has stricter JWT validation that requires `aud` claim. Keycloak doesn't include this by default, and adding an audience mapper in Keycloak is unreliable/buggy.

**Solution:**
1. **Upgrade to latest OAuth2 proxy** - Handles missing `aud` claim gracefully
2. **DO NOT add audience mapper** in Keycloak - causes more problems than it solves
3. **Only use groups mapper** in client scope

See `/home/administrator/projects/AINotes/security.md` for comprehensive troubleshooting details.

**Issue:** OIDC issuer mismatch error
```
oidc: issuer did not match the issuer returned by provider,
expected "http://keycloak:8080/realms/master"
got "https://keycloak.ai-servicers.com/realms/master"
```

**Solution:** Use hybrid URL strategy - issuer URL must match what Keycloak returns (external HTTPS), but backend URLs (REDEEM, JWKS) use internal HTTP. Set `OAUTH2_PROXY_SKIP_OIDC_DISCOVERY=true` and configure URLs explicitly.

**Issue:** Cookie secret length error
```
cookie_secret must be 16, 24, or 32 bytes
```

**Solution:** Generate secret with exactly 32 bytes:
```python
import secrets
cookie_secret = secrets.token_urlsafe(32)[:32]
```

### ArangoDB Authentication

**Issue:** 401 Unauthorized when connecting to ArangoDB

**Causes:**
1. Password not set in container environment
2. Data directory from previous deployment with different password

**Solution:**
```bash
# Stop containers
docker compose down

# Clear data directories
docker run --rm -v $HOME/projects/data/arangodb:/data alpine rm -rf /data/*
docker run --rm -v $HOME/projects/data/arangodb-apps:/data alpine rm -rf /data/*

# Redeploy
./deploy.sh
```

### Health Check Warnings

**Issue:** Container shows "unhealthy" status

**Cause:** Health check uses `curl` which isn't installed in the ArangoDB container

**Impact:** None - ArangoDB runs normally, health check just fails

**Workaround:** Check logs instead:
```bash
docker logs arangodb 2>&1 | grep "ready for business"
```

### Container Connectivity

**Issue:** Cannot connect to ArangoDB from another container

**Solution:** Ensure the client container is on `arangodb-net`:
```yaml
networks:
  - arangodb-net
```

## Naming Convention Compliance

All resources use the name **arangodb**:
- ✓ Container names: `arangodb`, `arangodb-auth-proxy`
- ✓ Project directory: `/home/administrator/projects/arangodb`
- ✓ Component network: `arangodb-net`
- ✓ Environment file: `arangodb.env`
- ✓ Keycloak client: `arangodb`
- ✓ DNS: `arangodb.ai-servicers.com`
- ✓ Traefik router: `arangodb`

## Security

### Authentication Layers

1. **Web Access:** OAuth2 proxy → Keycloak SSO → Group membership check (`administrators`)
2. **API Access (internal):** HTTP Basic Auth with root credentials
3. **Network Isolation:** Backend on separate network, not directly on `traefik-net`

### Secret Management

- All secrets stored in `$HOME/projects/secrets/arangodb.env`
- File permissions: 600 (readable only by owner)
- Symlink: `$HOME/secrets/arangodb.env` → `$HOME/projects/secrets/arangodb.env`
- **Never commit** secrets to git (.gitignore configured)

### Password Security

- Root password: 44-character base64-encoded random string
- Cookie secret: 32-byte URL-safe random string
- Client secret: Provided by Keycloak during client creation

## Version Information

**ArangoDB:** 3.11 (pinned to major.minor for stability)
**OAuth2 Proxy:** latest (required for Keycloak compatibility - v7.6.0 has bugs)
**Docker Compose:** 3.8 syntax

**Note on OAuth2 Proxy versioning:** We use `latest` instead of pinning because v7.6.0 has a bug with Keycloak JWT validation. The latest version handles missing `aud` claims gracefully.

## Phase 2: MCP Server Integration - ✅ COMPLETE (2025-10-14)

### MCP Server Deployment

Successfully deployed ArangoDB MCP server integration:

1. **Implementation** - Standard `arango-server` v0.4.0 package
   - Location: Integrated via `/home/administrator/projects/mcp/proxy`
   - Integration: MCP Proxy (stdio transport, no separate container)
   - Network: MCP proxy on `arangodb-net` for database access
   - Tools: 7 ArangoDB operations (query, insert, update, remove, list/create collections, backup)

2. **Integration Points**
   - Database: `ai_memory`
   - Endpoint: `http://localhost:9090/arangodb/mcp` (via MCP Proxy)
   - Authentication: root user (environment variables in proxy config)
   - Total MCP Infrastructure: 9 servers, 64 tools

3. **Available Use Cases**
   - Document storage for AI conversation history
   - Collection management for organized data
   - AQL queries for complex data operations
   - JSON backup functionality for data persistence
   - Multi-model database capabilities (document, graph, key-value)

**Status:** ✅ Fully operational and integrated with Open WebUI, Kilo Code, Claude Code CLI

## References

### Internal Documentation

- System Overview: `/home/administrator/projects/AINotes/SYSTEM-OVERVIEW.md`
- Network Architecture: `/home/administrator/projects/AINotes/network.md`
- Security Policies: `/home/administrator/projects/AINotes/security.md`
- Coding Standards: `/home/administrator/projects/AINotes/codingstandards.md`
- Deployment Plan: `/home/administrator/projects/AINotes/arangodb.md`

### External Documentation

- ArangoDB Docs: https://docs.arangodb.com/stable/
- AQL Reference: https://docs.arangodb.com/stable/aql/
- OAuth2 Proxy: https://oauth2-proxy.github.io/oauth2-proxy/
- Traefik: https://doc.traefik.io/traefik/

## Changelog

### 2025-10-14 - Initial Deployment & Complete Resolution

**Completed:**
- [x] Keycloak client creation and configuration
- [x] Environment file with all required secrets
- [x] Docker Compose configuration with network isolation
- [x] Deployment automation script with validation
- [x] OAuth2 authentication via Keycloak (administrators group)
- [x] Traefik integration with Let's Encrypt SSL
- [x] Created `ai_memory` database
- [x] Project documentation (this file)
- [x] Added to Dashy dashboard under Home > Data Tools
- [x] Full OAuth2 proxy + Keycloak + Traefik integration working

**Issues Resolved:**
1. Cookie secret size (fixed to 32 bytes)
2. OAuth2 scope quoting (required quotes around multi-word value)
3. OIDC issuer mismatch (implemented hybrid URL strategy)
4. ArangoDB password not loaded (changed to `env_file` in docker-compose)
5. **Audience claim error** (upgraded OAuth2 proxy to `latest`, removed audience mapper)
6. **Group authorization failing** (used full path `/administrators`, removed buggy audience mapper)
7. **ArangoDB JWT authentication** - Works correctly through OAuth2 proxy (no special configuration needed)
8. **Traefik routing** - OAuth2 proxy container has Traefik labels (not ArangoDB container)

**Critical Discovery:**
- OAuth2 proxy v7.6.0 has JWT validation bug with Keycloak tokens
- Keycloak's audience mapper is unreliable and causes authentication failures
- **Correct solution**: Use latest OAuth2 proxy + groups mapper only (NO audience mapper)
- OAuth2 proxy does NOT interfere with ArangoDB's internal JWT authentication (initial concern was unfounded)
- Architecture: Traefik → OAuth2 Proxy (has Traefik labels) → ArangoDB (isolated on arangodb-net)
- Documented comprehensive solution in `/home/administrator/projects/AINotes/security.md`

**Working Configuration:**
- Access: https://arangodb.ai-servicers.com
- Two-layer authentication:
  1. Keycloak SSO (OAuth2 proxy validates, requires /administrators group)
  2. ArangoDB login (username: root, password in env file)
- Both authentication layers work correctly without conflicts

**Completed:**
- [x] Update SYSTEM-OVERVIEW.md with ArangoDB entry
- [x] Phase 2: MCP server deployment and middleware integration

---

*Document created: 2025-10-14*
*Last updated: 2025-10-14 (Phase 2 MCP integration complete)*
*Maintained by: Claude Code*
