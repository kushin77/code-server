#!/bin/bash
# Cluster Shutdown Summary - 2026-04-27

## Task: Shut Down All Containers on Both Hosts of the Cluster

### Status: ✅ PRIMARY HOST SHUT DOWN SUCCESSFULLY

---

## Results

### Primary Host (192.168.168.31)
- **Status**: ✅ All containers successfully stopped
- **Containers stopped**: 13
- **Containers by name**:
  1. ollama-models
  2. oauth2-proxy
  3. caddy-gateway
  4. qdrant-vectors
  5. opa-service
  6. redpanda-console
  7. alertmanager
  8. grafana-dashboards
  9. redis-cache
  10. postgres-db
  11. redpanda-broker
  12. loki-logs
  13. prometheus

- **Verification**: All containers now show "Exited" status

### Replica Host (192.168.168.32)
- **Status**: ❌ Not accessible (connection timeout)
- **Note**: The configured replica host at 192.168.168.32 could not be reached. 
  - Attempted connection: SSH port 22 timeout
  - This may indicate the replica is offline, on a different subnet, or not yet deployed

---

## Deliverables

### Scripts Created
1. **scripts/operations/shutdown-cluster.sh**
   - Full-featured shutdown script with detailed configuration
   - Requires explicit PRIMARY_HOST and REPLICA_HOST environment variables
   - Includes pre-flight checks and parallel shutdown capability
   - Usage: `bash scripts/operations/shutdown-cluster.sh`

2. **scripts/operations/shutdown-cluster-defaults.sh**
   - Simplified shutdown script with intelligent defaults
   - Uses repository configuration and environment variables
   - Can work with custom hosts via environment overrides
   - Usage: `PRIMARY_HOST=<ip> REPLICA_HOST=<ip> bash scripts/operations/shutdown-cluster-defaults.sh`

### Execution Commands Used
```bash
# Primary host shutdown command:
ssh akushnir@192.168.168.31 'docker ps -a -q | xargs -r docker stop --timeout=30'

# Result: All 13 containers successfully stopped
```

---

## Recommendations

1. **To locate the replica host**:
   - Check infrastructure documentation for current replica IP
   - Verify replica host is running and accessible on the network
   - Check DNS configuration for `replica.example.internal`

2. **To restart containers**:
   ```bash
   ssh akushnir@192.168.168.31 'cd code-server && docker compose up -d'
   ```

3. **For future shutdowns**:
   - Use the created scripts with proper environment variables
   - Set `FORCE=true` to skip confirmation prompts
   - Scripts support parallel shutdown for faster execution

---

## Summary
✅ All 13 containers on the primary host (192.168.168.31) have been successfully shut down.
⚠️ Replica host (192.168.168.32) is not currently accessible; manual verification needed.
✅ Reusable shutdown scripts created for future maintenance operations.
