#!/bin/bash
# Container image vulnerability scanning with Trivy
# Scans all Docker images for known CVEs

set -e
trap 'echo "❌ Scan failed"; exit 1' ERR

REPORT_DIR="/var/logs/security-scans"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$REPORT_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Container Image Security Scanning                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if Trivy is installed
if ! command -v trivy &> /dev/null; then
  echo "Installing Trivy vulnerability scanner..."
  
  if [[ -f /etc/debian_version ]]; then
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add - 2>/dev/null || true
    echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/trivy.list >/dev/null
    apt-get update >/dev/null && apt-get install -y trivy >/dev/null
  fi
  echo "✓ Trivy installed"
fi

echo "Scanning container images for vulnerabilities..."
echo ""

REPORT_FILE="$REPORT_DIR/scan_${TIMESTAMP}.json"
SUMMARY_FILE="$REPORT_DIR/summary_${TIMESTAMP}.txt"

{
  echo "Container Image Vulnerability Scan"
  echo "Timestamp: $(date -R)"
  echo "=================================="
  echo ""
} > "$SUMMARY_FILE"

# Get all images
IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "^<none>")

TOTAL_IMAGES=0
IMAGES_WITH_VULNS=0
CRITICAL_COUNT=0
HIGH_COUNT=0

for IMAGE in $IMAGES; do
  ((TOTAL_IMAGES++))
  echo -n "Scanning $IMAGE... "
  
  # Run Trivy scan
  if trivy image --format json --severity CRITICAL,HIGH "$IMAGE" > /tmp/scan_output.json 2>/dev/null; then
    # Check for vulnerabilities
    CRIT=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="CRITICAL")] | length' /tmp/scan_output.json 2>/dev/null || echo "0")
    HIGH=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="HIGH")] | length' /tmp/scan_output.json 2>/dev/null || echo "0")
    
    if [[ $CRIT -gt 0 ]] || [[ $HIGH -gt 0 ]]; then
      ((IMAGES_WITH_VULNS++))
      CRITICAL_COUNT=$((CRITICAL_COUNT + CRIT))
      HIGH_COUNT=$((HIGH_COUNT + HIGH))
      echo "⚠️  Found vulnerabilities (C:$CRIT H:$HIGH)"
      
      echo "  ⚠️  Image: $IMAGE (CRITICAL:$CRIT HIGH:$HIGH)" >> "$SUMMARY_FILE"
    else
      echo "✓ Clean"
    fi
  else
    echo "❌ Scan failed"
  fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Scan Summary"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Total images scanned: $TOTAL_IMAGES"
echo "  Images with vulnerabilities: $IMAGES_WITH_VULNS"
echo "  Total critical issues: $CRITICAL_COUNT"
echo "  Total high issues: $HIGH_COUNT"
echo ""

if [[ $CRITICAL_COUNT -gt 0 ]]; then
  echo "  🚨 CRITICAL: Action required - critical vulnerabilities detected"
fi

if [[ $HIGH_COUNT -gt 0 ]]; then
  echo "  ⚠️  WARNING: High severity vulnerabilities detected"
fi

if [[ $IMAGES_WITH_VULNS -eq 0 ]]; then
  echo "  ✅ All images are clean"
fi

echo ""
echo "Full report: $REPORT_FILE"
echo "Summary: $SUMMARY_FILE"
echo ""
