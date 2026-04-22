#!/usr/bin/env bash
# Verify Phase 2C deployment

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
echo "=== PHASE 2C DEPLOYMENT VERIFICATION ==="
echo ""
echo "Services running:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -15
echo ""
echo "HTTPS Health Check:"
curl -sk https://ide.kushnir.cloud/health && echo " ✓ OK"
echo ""
echo "=== Deployment Verification Complete ==="
EOF
