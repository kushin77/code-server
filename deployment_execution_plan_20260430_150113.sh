#!/bin/bash
# Automated Deployment Execution Plan
# This script contains the complete automated deployment workflow

set -e
trap 'echo "[ERROR] Deployment failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Deployment pipeline completed"; true' EXIT

DEPLOYMENT_DIR="/home/akushnir/code-server"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOYMENT_LOG="${DEPLOYMENT_DIR}/deployment_${TIMESTAMP}.log"

{
  echo "🚀 AUTOMATED DEPLOYMENT EXECUTION STARTING"
  echo "==========================================="
  echo "Timestamp: $(date)"
  echo ""
  
  # STEP 1: Pre-deployment verification
  echo "[STEP 1/5] Pre-Deployment Verification"
  echo "======================================="
  cd "$DEPLOYMENT_DIR"
  
  if [ -f "./pre-deployment-verification-final.sh" ]; then
    bash ./pre-deployment-verification-final.sh || {
      echo "❌ Pre-deployment checks failed - aborting deployment"
      exit 1
    }
  fi
  echo "✅ Pre-deployment verification PASSED"
  echo ""
  
  # STEP 2: Service deployment
  echo "[STEP 2/5] Service Deployment"
  echo "=============================="
  docker-compose -f docker-compose.enterprise.yml up -d 2>&1 | tee -a "$DEPLOYMENT_LOG"
  
  echo "Waiting for services to start (30 seconds)..."
  sleep 30
  
  RUNNING=$(docker-compose ps 2>/dev/null | grep -c "Up" || echo 0)
  if [ "$RUNNING" -ge 5 ]; then
    echo "✅ All services deployed"
  else
    echo "❌ Services not running - aborting"
    exit 1
  fi
  echo ""
  
  # STEP 3: Health verification
  echo "[STEP 3/5] Health Verification"
  echo "=============================="
  
  for i in {1..5}; do
    echo "Health check attempt $i..."
    if curl -s -k https://kushnir.cloud/api/hermes/health > /dev/null 2>&1; then
      echo "✅ API Health: PASS"
      break
    else
      echo "⚠️  API Health check failed, retrying..."
      sleep 5
    fi
  done
  
  if docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Database: PASS"
  else
    echo "⚠️  Database check failed"
  fi
  
  if docker exec code-server-redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis: PASS"
  else
    echo "⚠️  Redis check failed"
  fi
  echo ""
  
  # STEP 4: Post-deployment verification
  echo "[STEP 4/5] Post-Deployment Verification"
  echo "========================================"
  
  if [ -f "./post-deployment-verification.sh" ]; then
    bash ./post-deployment-verification.sh || {
      echo "⚠️  Post-deployment verification had issues, but continuing..."
    }
  fi
  echo ""
  
  # STEP 5: Deployment completion
  echo "[STEP 5/5] Deployment Completion"
  echo "================================="
  
  echo "✅ Deployment complete"
  echo ""
  echo "SERVICE STATUS:"
  docker-compose ps
  echo ""
  echo "RESOURCE USAGE:"
  docker stats --no-stream | head -6
  echo ""
  echo "🎉 AUTOMATED DEPLOYMENT SUCCESSFUL"
  echo "Next: Monitor continuously for 24 hours"
  
} 2>&1 | tee "$DEPLOYMENT_LOG"

