#!/bin/bash
# Quick Reference: Fix DAST Issue #1644 (ide.kushnir.cloud unreachable)
# SSH to Replica 2: ssh akushnir@192.168.168.42
# Then run this step-by-step

echo "=== DAST Issue #1644 Quick Fix Guide ==="
echo ""

# STEP 1: Check what's running
echo "STEP 1: Verify services are running..."
cd code-server-enterprise
docker-compose ps | grep -E "caddy|oauth2-proxy|code-server"
echo ""

# STEP 2: If Caddy is not running (status "stopped" or missing)
echo "STEP 2: Check Caddy status..."
docker-compose logs --tail 50 caddy
echo ""

# STEP 3: If logs show errors, restart Caddy
echo "STEP 3: Restart Caddy (if needed)..."
echo "Run: docker-compose restart caddy"
echo ""

# STEP 4: Verify health endpoint responds
echo "STEP 4: Test health endpoint..."
curl -v -k https://ide.kushnir.cloud/health
echo ""
# Expected: HTTP 200 with "OK"

# STEP 5: If still failing, check oauth2-proxy
echo "STEP 5: If health fails, check oauth2-proxy..."
docker-compose logs --tail 50 oauth2-proxy
echo ""

# STEP 6: Full restart as last resort
echo "STEP 6: Full service restart (if all else fails)..."
echo "Run: docker-compose down"
echo "Run: docker-compose up -d"
echo ""

# STEP 7: Verify deployment
echo "STEP 7: Verify services are healthy..."
docker-compose ps
echo ""

# STEP 8: Re-run DAST from CI
echo "STEP 8: After fix, re-run DAST in GitHub Actions..."
echo "Go to: https://github.com/kushin77/code-server/actions"
echo "Find: 'Security Scans' workflow"
echo "Click: 'Run workflow' on main branch"
echo ""

echo "=== Expected Success ==="
echo "✅ curl -k https://ide.kushnir.cloud/health returns HTTP 200"
echo "✅ DAST scan shows 'target reachable' with 200 OK"
echo "✅ Security gates pass in CI"
echo "✅ Production deployment can proceed"
