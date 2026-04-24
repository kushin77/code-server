# Troubleshooting Guide

## Common Issues

### 1. OPA Service Not Responding
**Symptom:** Tests fail with "OPA not responding at http://localhost:8181".
**Solution:** 
- Ensure Docker Desktop is running.
- Run `docker compose up -d opa` to start the policy engine.
- Verify logs with `docker compose logs opa`.

### 2. Kafka Event Bus Connection Refused
**Symptom:** Activity feed or backend cannot connect to Redpanda.
**Solution:**
- Check Redpanda status: `docker compose ps redpanda`.
- Verify internal network aliases in `docker-compose.yml`.
- Ensure `KAFKA_BOOTSTRAP_SERVERS` is set to `redpanda:9092`.

### 3. Git Dirty State in Production Check
**Symptom:** `production-readiness-check.sh` fails with "Uncommitted changes".
**Solution:**
- Run `git status --short` to find untracked files.
- Common culprits: `__pycache__`, `.pytest_cache`, or generated JSON reports.
- Use `git clean -fd` for a fresh start (caution: deletes untracked files).

### 4. WSL/Windows Path Issues
**Symptom:** Scripts fail to find files in `/mnt/c/`.
**Solution:**
- Ensure the workspace is correctly mounted in WSL.
- Use `wsl path/to/script.sh` instead of calling bash directly on Windows paths if permissions issues occur.

## Health Check Commands
- **Full Infrastructure:** `wsl bash scripts/ops/infrastructure-health-check.sh`
- **OPA Policies:** `wsl bash scripts/ops/test-opa-policies.sh`
- **Production Audit:** `wsl bash scripts/ops/production-readiness-check.sh`
