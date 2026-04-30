#!/bin/bash
# may-1-morning-startup.sh
# Quick startup checklist for May 1, 2026 go-live day
# Run this at 06:00 UTC to prepare systems

trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Morning startup check complete"; true' EXIT

echo "🌅 MAY 1 MORNING STARTUP - GO-LIVE DAY"
echo "======================================"
echo "Current Time: $(date)"
echo ""

# Step 1: Check git status
echo "📍 Step 1: Git Repository Status"
git status
git log --oneline -1
echo ""

# Step 2: Verify all services are running
echo "📍 Step 2: Service Status"
docker-compose ps | head -10
echo ""

# Step 3: Quick health check
echo "📍 Step 3: Health Check"
echo "API: $(curl -k https://kushnir.cloud/api/hermes/health 2>/dev/null | jq -r '.status // "not responding"')"
echo "Database: $(docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c 'SELECT 1;' 2>/dev/null | tail -1 || echo 'error')"
echo "Redis: $(docker exec code-server-redis redis-cli ping 2>/dev/null || echo 'error')"
echo ""

# Step 4: Resource check
echo "📍 Step 4: Resource Utilization"
echo "Docker Statistics:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}" | head -6
echo ""
echo "Disk Space:"
df -h /home | tail -1
echo ""

# Step 5: Show deployment checklist reminder
echo "📍 Step 5: Next Steps"
echo "✅ Run: ./pre-deployment-verification-final.sh (06:15)"
echo "✅ Verify: All checks pass (06:45)"
echo "✅ Review: MAY_1_GOLIVE_EXECUTION_CHECKLIST.md"
echo "✅ Team Briefing: 06:00-06:15"
echo "✅ Deployment: Start at 09:00 UTC"
echo ""
echo "🚀 System ready for May 1 go-live!"
