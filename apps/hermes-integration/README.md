# Hermes Agent Integration for code-server

Complete REST API integration of the Hermes Agent platform with code-server IDE and Appsmith portal.

## Overview

This integration provides:

- **REST API Service** - Full programmatic access to hermes-agent capabilities
- **IDE Integration** - code-server extension with side panel control, phase testing, and git management
- **Appsmith Dashboard** - Real-time metrics, phase management UI, batch operations, and quality visualization
- **Container Deployment** - Docker-based deployment to 192.168.168.31/192.168.168.42

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     code-server Deployment                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │  code-server IDE │      │  Appsmith Portal │                 │
│  │  (TypeScript Ext)│      │  (Dashboard)     │                 │
│  └────────┬─────────┘      └────────┬─────────┘                 │
│           │                         │                            │
│           └──────────────┬──────────┘                            │
│                          │                                       │
│                    ┌─────▼────────────┐                         │
│                    │ Hermes Integration│                        │
│                    │  REST API Service  │                       │
│                    │  (Python FastAPI)  │                       │
│                    └─────┬────────────┘                         │
│                          │                                       │
│                    ┌─────▼────────────┐                         │
│                    │  hermes-agent     │                        │
│                    │  Platform (250+   │                        │
│                    │  phases)          │                        │
│                    └───────────────────┘                        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Service Components

### 1. Hermes Integration Service

**Location:** `apps/hermes-integration/`

REST API providing full access to:
- Platform metrics
- Phase information and status
- Test execution
- Quality checks (mypy, ruff)
- Git commits
- Batch operations

**API Endpoints:**

```
GET  /health                          - Health check
GET  /metrics                         - Platform metrics
GET  /phases/{phase_number}           - Phase info
POST /phases/{phase_number}/test      - Run phase tests
POST /phases/{phase_number}/quality   - Quality checks
POST /phases/{phase_number}/commit    - Commit phase
POST /batch/test                      - Batch test execution
GET  /status                          - Overall status
GET  /git/log                         - Git log
```

### 2. IDE Extension

**Location:** `apps/ide-extension/hermes-extension.ts`

Features:
- Hermes control panel in IDE sidebar
- One-click test execution
- Quality check integration
- Phase commit management
- Git log browsing
- Real-time metrics display

### 3. Appsmith Dashboard

**Location:** `apps/paperclip/appsmith-hermes-dashboard.json`

Pages:
- **Dashboard**: Platform metrics, quick actions, recent commits
- **Phase Management**: Individual phase control and testing
- **Batch Operations**: Multi-phase batch execution

## Deployment

### Prerequisites

- Docker & docker-compose
- code-server running on 192.168.168.31 (primary) / 192.168.168.42 (replica)
- Appsmith instance accessible at kushnir.cloud
- hermes-agent repository accessible

### Docker Setup

Build the image:

```bash
cd /home/akushnir/code-server/apps/hermes-integration
docker build -t hermes-integration:latest .
```

### docker-compose Configuration

Add to `docker-compose.enterprise.yml`:

```yaml
hermes-integration:
  image: hermes-integration:latest
  container_name: hermes-integration
  ports:
    - "8000:8000"
  environment:
    - HERMES_REPO_PATH=/mnt/hermes-agent
  volumes:
    - /home/akushnir/hermes-agent:/mnt/hermes-agent:ro
    - /home/akushnir/code-server/apps/hermes-integration:/app
  networks:
    - code-server-network
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
    timeout: 10s
    retries: 3
  restart: unless-stopped
```

### IDE Extension Installation

1. Copy `apps/ide-extension/hermes-extension.ts` to code-server extensions directory
2. Register in code-server's extension manifest
3. Reload code-server

### Appsmith Integration

1. Create new Appsmith datasource: REST API pointing to `http://hermes-integration:8000`
2. Import `apps/paperclip/appsmith-hermes-dashboard.json` as new app
3. Set `HERMES_API_URL` environment variable to service endpoint
4. Deploy to kushnir.cloud

## Configuration

### Environment Variables

```env
# Service
HERMES_REPO_PATH=/home/akushnir/hermes-agent     # Path to hermes-agent repo
HERMES_API_PORT=8000                              # API port
HERMES_API_HOST=0.0.0.0                           # API host

# IDE Extension
HERMES_API_URL=http://localhost:8000              # IDE → API connection

# Appsmith
HERMES_API_URL=http://hermes-integration:8000    # Appsmith → API connection
```

## API Usage Examples

### Get Platform Metrics

```bash
curl http://hermes-integration:8000/metrics
```

Response:
```json
{
  "total_phases": 250,
  "total_tests": 2442,
  "total_test_files": 105,
  "avg_tests_per_phase": 23.25,
  "quality_score": 100.0,
  "last_commit_hash": "a8fc4ed",
  "phase_coverage": {"completed": 250, "total": 250}
}
```

### Run Phase Tests

```bash
curl -X POST http://hermes-integration:8000/phases/246/test
```

Response:
```json
{
  "phase_number": 246,
  "passed": 18,
  "failed": 0,
  "total": 18,
  "duration_seconds": 0.15,
  "errors": []
}
```

### Quality Check

```bash
curl -X POST http://hermes-integration:8000/phases/246/quality
```

Response:
```json
{
  "phase_number": 246,
  "pytest_passed": true,
  "mypy_passed": true,
  "ruff_passed": true,
  "all_passed": true
}
```

### Batch Operations

```bash
curl -X POST http://hermes-integration:8000/batch/test \
  -H "Content-Type: application/json" \
  -d '{
    "start_phase": 251,
    "end_phase": 255,
    "auto_verify": true,
    "auto_commit": true
  }'
```

## IDE Extension Commands

| Command | Binding | Description |
|---------|---------|-------------|
| `hermes.openPanel` | Ctrl+Shift+H | Open Hermes control panel |
| `hermes.getMetrics` | - | Display platform metrics |
| `hermes.testPhase` | Ctrl+Shift+T | Run tests for current phase file |
| `hermes.qualityCheck` | Ctrl+Shift+Q | Run quality checks |
| `hermes.commitPhase` | Ctrl+Shift+C | Commit current phase |
| `hermes.gitLog` | - | Show recent commits |

## Appsmith Dashboard Usage

### Dashboard Page
- View real-time metrics (phases, tests, quality score)
- One-click batch testing
- Recent commits browser
- Platform health status

### Phase Management Page
- Select individual phase
- View phase details and test count
- Run tests, quality checks, commits for single phase
- Review test and quality results

### Batch Operations Page
- Define phase range (start, end)
- Enable/disable auto-verify and auto-commit
- Execute batch operations
- View results table with pass/fail details

## Monitoring & Health

### Health Checks

```bash
# Check service health
curl http://hermes-integration:8000/health

# Check via docker
docker logs hermes-integration
```

### Metrics

```bash
# Get comprehensive status
curl http://hermes-integration:8000/status

# Get git history
curl http://hermes-integration:8000/git/log?limit=20
```

## Integration Points

### code-server IDE
- **Sidebar Panel**: Real-time metrics, quick actions
- **Commands**: Context menu + keyboard shortcuts
- **Editor**: Phase file detection, inline testing

### Appsmith Portal
- **Dashboard**: Metrics aggregation and visualization
- **Phase Management**: CRUD operations on phases
- **Batch Executor**: Multi-phase orchestration
- **Git Browser**: Commit history tracking

### hermes-agent Platform
- **Direct Access**: Mounted repository read-only access
- **subprocess Execution**: Tests, type checks, linting
- **Git Operations**: Commit creation with semantic messages

## Security Considerations

1. **Read-Only Access**: hermes-agent mounted as read-only in container
2. **API Authentication**: Add JWT/OAuth for production (Appsmith integration)
3. **Network Isolation**: Service accessible only within code-server network
4. **Container Limits**: CPU/memory limits applied
5. **Logging**: All operations logged and auditable

## Troubleshooting

### Service won't start

```bash
# Check logs
docker logs hermes-integration

# Verify repo access
docker exec hermes-integration ls -la /mnt/hermes-agent

# Check API port
netstat -tlnp | grep 8000
```

### IDE extension not working

```bash
# Verify extension is loaded
code-server --list-extensions | grep hermes

# Check IDE console for errors
```

### Appsmith connector failing

```bash
# Verify API endpoint is reachable
curl http://hermes-integration:8000/health

# Check Appsmith application logs
```

## Development

### Local Testing

```bash
# Start service locally
cd apps/hermes-integration
pip install -r requirements.txt
python main.py

# Test endpoints
curl http://localhost:8000/metrics
```

### Extension Development

```bash
# Rebuild IDE extension
cd apps/ide-extension
npm install
npm run build
```

### Dashboard Development

```bash
# Edit dashboard
# Edit apps/paperclip/appsmith-hermes-dashboard.json
# Re-import into Appsmith
```

## Production Deployment

### Infrastructure

The service is deployed as part of the code-server cluster:

```
Primary (192.168.168.31):
└─ hermes-integration:8000 (primary instance)
  └─ Connected to hermes-agent repo

Replica (192.168.168.42):
└─ hermes-integration:8000 (replica instance)
  └─ Connected to hermes-agent repo
```

### Failover

Both primary and replica instances maintain independent connections to the hermes-agent repository. Failover is automatic via load balancer/VIP at 192.168.168.40.

## Support & Documentation

- API Documentation: Available at `/docs` when service is running (Swagger UI)
- IDE Extension: Inline help via `hermes.openPanel` command
- Appsmith: Built-in dashboard help panels
- Logs: Available via `docker logs hermes-integration`
