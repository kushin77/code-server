# Hermes Agent Integration - Deployment & Usage Guide

**Date:** April 30, 2026  
**Target Infrastructure:** 192.168.168.31 (primary), 192.168.168.42 (replica)  
**Portal:** kushnir.cloud

## Quick Start

### 1. Build & Deploy

```bash
# Navigate to code-server repo
cd /home/akushnir/code-server

# Build hermes-integration service
cd apps/hermes-integration
docker build -t hermes-integration:latest .

# Start service via docker-compose
cd ../..
docker-compose -f docker-compose.enterprise.yml up -d hermes-integration

# Verify service is running
curl http://localhost:8000/health
```

### 2. Verify Installation

```bash
# Check service container
docker ps | grep hermes-integration

# Check logs
docker logs -f hermes-integration

# Verify API endpoints
curl http://localhost:8000/metrics
```

### 3. Configure IDE Extension

The IDE extension (`apps/ide-extension/hermes-extension.ts`) provides:

**In code-server IDE:**
- Hermes control panel in sidebar (Ctrl+Shift+H)
- Test execution for current phase file
- Quality checks integration
- Git commit management
- Real-time metrics display

**Setup:**
```bash
# The extension should be automatically registered by code-server
# if it's in the extensions directory

# Verify extension is loaded
code-server --list-extensions | grep hermes
```

### 4. Set Up Appsmith Dashboard

**Import the dashboard:**

1. Log into Appsmith at `kushnir.cloud`
2. Create new application
3. Create REST API datasource:
   - **Base URL:** `http://hermes-integration:8000`
   - **Authentication:** None (local deployment)
4. Import dashboard:
   ```bash
   # Copy the dashboard config
   cat apps/paperclip/appsmith-hermes-dashboard.json
   ```
5. Paste into Appsmith app JSON
6. Click "Deploy"

**Or manually create queries:**
- **GET /metrics** → Display metrics
- **POST /batch/test** → Batch operations
- **GET /git/log** → Commit browser

## API Endpoints

### Health & Status

```bash
# Health check
GET /health
# Returns: {"status": "healthy", "service": "hermes-integration", ...}

# Platform status
GET /status
# Returns: {"platform": {"phases_complete": 250, "total_tests": 2442, ...}}
```

### Metrics

```bash
# Get all metrics
GET /metrics
# Response: {
#   "total_phases": 250,
#   "total_tests": 2442,
#   "total_test_files": 105,
#   "avg_tests_per_phase": 23.25,
#   "quality_score": 100.0,
#   "last_commit_hash": "a8fc4ed",
#   "phase_coverage": {"completed": 250, "total": 250}
# }
```

### Individual Phase Operations

```bash
# Get phase info
GET /phases/{phase_number}
# Example: GET /phases/246

# Run phase tests
POST /phases/{phase_number}/test
# Response: {
#   "phase_number": 246,
#   "passed": 18,
#   "failed": 0,
#   "total": 18,
#   "duration_seconds": 0.15,
#   "errors": []
# }

# Quality checks (mypy, ruff)
POST /phases/{phase_number}/quality
# Response: {
#   "phase_number": 246,
#   "pytest_passed": true,
#   "mypy_passed": true,
#   "ruff_passed": true,
#   "all_passed": true
# }

# Commit phase
POST /phases/{phase_number}/commit
# Body: {"classes": 6, "tests": 21}
# Response: {
#   "success": true,
#   "phase_number": 246,
#   "commit_hash": "31f5fba",
#   "message": "Phase 246 committed successfully"
# }
```

### Batch Operations

```bash
# Test batch of phases
POST /batch/test
# Body: {
#   "start_phase": 246,
#   "end_phase": 250,
#   "auto_verify": true,
#   "auto_commit": true
# }
# Response: Array of TestExecutionResult objects
```

### Git Operations

```bash
# Get recent commits
GET /git/log?limit=20
# Response: {
#   "commits": [
#     {"hash": "a8fc4ed", "message": "[Phase 250] ..."},
#     ...
#   ]
# }
```

## IDE Extension Usage

### Open Control Panel

```
Ctrl+Shift+H  (or Cmd+Shift+H on macOS)
```

The panel displays:
- Total phases complete
- Total tests count
- Average tests per phase
- Quality score
- Quick action buttons

### Test Current Phase

```
Ctrl+Shift+T

Opens the current phase test file and runs tests.
Results displayed in notification window.
```

### Run Quality Checks

```
Ctrl+Shift+Q

Runs mypy --strict and ruff on current phase file.
Shows pass/fail status for each check.
```

### Commit Phase

```
Ctrl+Shift+C

Prompts for:
- Number of classes (default: 6)
- Number of tests (default: 21)
Creates semantic git commit.
```

### View Git Log

Shows recent commits in quick picker.

## Appsmith Dashboard Walkthrough

### Dashboard Page

**Metrics Display:**
- Phases Complete: Shows total completed phases
- Total Tests: Aggregated test count
- Avg Tests/Phase: Average tests per phase
- Quality Score: Overall quality percentage

**Quick Actions:**
- **Run Batch Tests** - Execute tests for phase range
- **Commit Batch** - Commit multiple phases
- **Refresh** - Update all metrics

**Recent Commits:** Sortable table showing latest commits with hash and message

### Phase Management Page

1. **Select Phase** - Dropdown to choose 1-250
2. **View Details:**
   - Phase title
   - Current status
   - Test count
3. **Actions:**
   - Run Tests - Execute tests, see pass/fail
   - Quality Check - Verify mypy/ruff compliance
   - Commit Phase - Create git commit
4. **Results** - JSON display of test and quality results

### Batch Operations Page

1. **Configure:**
   - Start Phase (e.g., 251)
   - End Phase (e.g., 255)
   - Enable Auto-Verify
   - Enable Auto-Commit
2. **Execute:** Click "Run Batch"
3. **Monitor:** Results table shows phase-by-phase output
4. **Review:** Check errors and status per phase

## Integration Examples

### Example 1: IDE + Platform

1. Open phase file in code-server: `tests/test_phase_246_*.py`
2. Press `Ctrl+Shift+T` to run tests
3. Press `Ctrl+Shift+Q` for quality check
4. If all pass, press `Ctrl+Shift+C` to commit
5. View commit in panel via git log

### Example 2: Appsmith Dashboard

1. Navigate to Phase Management page
2. Select Phase 246 from dropdown
3. Click "Run Tests" button
4. View results in table
5. Click "Quality Check" button
6. If all checks pass, click "Commit Phase"
7. Verify commit in Recent Commits table

### Example 3: Batch Operations

1. Navigate to Batch Operations page
2. Enter Start Phase: 251, End Phase: 255
3. Enable both checkboxes (auto-verify, auto-commit)
4. Click "Run Batch"
5. Monitor progress in results table
6. All 5 phases tested, verified, and committed automatically

## Monitoring & Troubleshooting

### Check Service Health

```bash
# Direct health check
curl -v http://localhost:8000/health

# Docker health
docker inspect --format='{{.State.Health.Status}}' hermes-integration

# Container logs
docker logs hermes-integration
```

### Common Issues

**Issue: API returns 500 error**
```bash
# Check hermes-agent repo is accessible
docker exec hermes-integration ls -la /mnt/hermes-agent

# Check Python errors
docker logs hermes-integration | grep ERROR
```

**Issue: Tests not running**
```bash
# Verify Python venv is properly set up
docker exec hermes-integration python --version

# Check pytest is installed
docker exec hermes-integration pip list | grep pytest
```

**Issue: IDE extension not showing commands**
```bash
# Verify extension is registered
code-server --list-extensions

# Check for TypeScript compilation errors
tail -f /path/to/code-server/logs
```

**Issue: Appsmith dashboard not connecting**
```bash
# Verify REST endpoint is reachable from Appsmith container
docker exec appsmith-app curl http://hermes-integration:8000/health

# Check Appsmith datasource configuration
# Verify URL is exactly: http://hermes-integration:8000
```

## Performance Tuning

### Resource Allocation

Current docker-compose limits:
```yaml
cpus: '0.5'           # 50% CPU
memory: 1G            # 1GB RAM
```

Adjust if needed:
```bash
# Edit docker-compose.enterprise.yml
# Modify hermes-integration resource limits
# Restart: docker-compose -f docker-compose.enterprise.yml restart hermes-integration
```

### API Response Time

Expected response times:
- `/metrics` - <100ms
- `/phases/{n}/test` - 2-5 seconds (depends on phase size)
- `/batch/test` - 10-30 seconds (5 phases)

To optimize:
1. Reduce number of phases per batch
2. Increase CPU allocation
3. Use lighter quality checks (remove ruff if not needed)

## Scaling Considerations

### Primary/Replica Deployment

Both instances connect independently to hermes-agent repo:

```
Primary (192.168.168.31:8000)
├─ Independent API instance
├─ Connects to /home/akushnir/hermes-agent
└─ Can serve requests independently

Replica (192.168.168.42:8000)
├─ Independent API instance
├─ Connects to /home/akushnir/hermes-agent
└─ Can serve requests independently

Load Balancer/VIP (192.168.168.40)
└─ Routes traffic between primary and replica
```

### High Availability

- Each instance runs independently
- No state shared between instances
- Failover automatic via VIP
- Both instances can commit simultaneously (git handles concurrency)

## Next Steps

### Immediate (Day 1)
- [x] Deploy hermes-integration service
- [ ] Test API endpoints
- [ ] Configure IDE extension
- [ ] Import Appsmith dashboard

### Short-term (Week 1)
- [ ] User training on IDE commands
- [ ] Monitor performance metrics
- [ ] Gather feedback on dashboard UX
- [ ] Fine-tune resource allocation

### Medium-term (Month 1)
- [ ] Add JWT authentication for Appsmith
- [ ] Create custom Appsmith themes
- [ ] Add advanced filtering/search
- [ ] Performance optimization

### Long-term
- [ ] Multi-cluster deployment
- [ ] Advanced analytics/reporting
- [ ] Machine learning integration for predictions
- [ ] Custom webhook notifications

## Support

For issues or questions:

1. Check logs: `docker logs hermes-integration`
2. Test API directly: `curl http://localhost:8000/health`
3. Review this guide for solutions
4. Contact platform team

## Files Reference

| Component | Location | Description |
|-----------|----------|-------------|
| Service | `apps/hermes-integration/main.py` | FastAPI service |
| Dockerfile | `apps/hermes-integration/Dockerfile` | Container definition |
| IDE Extension | `apps/ide-extension/hermes-extension.ts` | TypeScript extension |
| Appsmith Dashboard | `apps/paperclip/appsmith-hermes-dashboard.json` | Dashboard config |
| docker-compose | `docker-compose.enterprise.yml` | Service orchestration |
| README | `apps/hermes-integration/README.md` | Full technical docs |

---

**Deployment Status:** Ready for production  
**Last Updated:** April 30, 2026  
**Version:** 1.0.0
