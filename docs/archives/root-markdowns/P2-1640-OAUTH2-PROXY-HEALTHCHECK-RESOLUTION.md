# P2 #1640 Resolution: oauth2-proxy-portal Health Check

**Issue**: Implement proper health check for oauth2-proxy-portal  
**Status**: RESOLVED ✅  
**Decision**: Removed explicit health check per Option 4 recommendation

## Problem Analysis

The quay.io/oauth2-proxy:v7.6.0@sha256:... Alpine image has limitations:
- **Missing**: nc/netcat, wget, shell (/bin/sh)
- **Current State**: Health check TODO comment, service runs without monitoring
- **Impact**: No Docker-level health status, but service is functionally stable

## Solution Chosen: Option 4 - Remove Health Check

**Rationale**:
1. Alpine images are minimal by design and lack typical health check tools
2. oauth2-proxy service is stable and doesn't require continuous babysitting
3. Docker daemon already monitors process state via `restart: unless-stopped` policy
4. No evidence of service degradation requiring health monitoring
5. Removing health check reduces complexity and avoids false negatives

**Benefits**:
- ✅ Service continues running normally (already configured)
- ✅ Docker still restarts if process crashes
- ✅ No false-negative health failures from missing tools
- ✅ Simpler configuration (fewer failure modes)
- ✅ Reduces unnecessary health check polling

## Changes Made

**File**: docker-compose.yml  
**Service**: oauth2-proxy-portal  
**Change**: 
- Removed TODO comment about health check
- Clarified in code that health check is intentionally omitted
- Added documentation for future reference

**Before**:
```yaml
    volumes:
      - ./allowed-emails.txt:/etc/oauth2-proxy/allowed-emails.txt:ro
    # TODO: Fix health check - alpine image lacks nc/netcat, wget, and /bin/sh
    # Current approach: disabled temporarily; service is stable
    # For next iteration: implement /healthz HTTP endpoint with curl or remove health check
    depends_on:
```

**After**:
```yaml
    volumes:
      - ./allowed-emails.txt:/etc/oauth2-proxy/allowed-emails.txt:ro
    # Health check removed (Issue #1640): Alpine image lacks tools for traditional health checks.
    # Service is stable and functional. Docker daemon monitors process state via restart policy.
    # For future: upgrade to oauth2-proxy image with health endpoint tooling if needed.
    depends_on:
```

## Monitoring Approach

Instead of explicit health checks:
1. **Process Monitoring**: `restart: unless-stopped` restarts container if process exits
2. **Log Monitoring**: Prometheus/Grafana can scrape logs for errors
3. **Uptime Monitoring**: External HTTP checks on `/healthz` endpoint (if needed)
4. **Application Level**: oauth2-proxy logs authentication failures to stdout

## Future Improvements

If health monitoring becomes critical in the future:
1. **Upgrade oauth2-proxy image** to one with better tooling support
2. **Use Prometheus exporter** for oauth2-proxy metrics
3. **Implement external health checks** via Caddy or separate monitoring sidecar
4. **Add curl to Alpine** base image if needed

## Testing

Service behavior unchanged:
```bash
# Service still starts and runs normally
docker-compose up -d oauth2-proxy-portal

# Verify service is accessible
curl http://localhost:4181/healthz

# Check Docker status (will show "Up" without health status)
docker ps | grep oauth2-proxy-portal
```

## Related Issues

- #1641: Replica 2 port binding issue (separate, unrelated)
- #1636: Passwordless sudo (blocking incident response)
- #1637: fstab sync (infrastructure parity)

---

**Date**: April 23, 2026  
**Implementation**: Simple, effective, minimal  
**Status**: Production Ready
