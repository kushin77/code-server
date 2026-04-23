#!/bin/bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_rsa_onprem"
echo "[*] Installing k6 on production replicas using SSH key: $SSH_KEY"
echo ""

# Replica 1
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[*] Installing k6 on 192.168.168.31..."
ssh -i "$SSH_KEY" akushnir@192.168.168.31 'bash -c "
set -euo pipefail
if command -v k6 &> /dev/null; then
  echo \"[✓] k6 already installed: $(k6 version)\"; exit 0
fi
TEMP_DIR=\$(mktemp -d); trap \"rm -rf \$TEMP_DIR\" EXIT; cd \"\$TEMP_DIR\"
curl -sSL \"https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz\" | tar xz
if [ -d k6-v0.50.0-linux-amd64 ]; then
  if [ -w /usr/local/bin ]; then
    mv k6-v0.50.0-linux-amd64/k6 /usr/local/bin/k6
  else
    sudo mv k6-v0.50.0-linux-amd64/k6 /usr/local/bin/k6
  fi
  chmod +x /usr/local/bin/k6 || sudo chmod +x /usr/local/bin/k6
  echo \"[✓] k6 installed: \$(k6 version)\"
else
  echo \"[ERROR] Failed to extract k6\"; exit 1
fi
"'

echo "[✓] Replica 1 ready"
echo ""

# Replica 2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[*] Installing k6 on 192.168.168.42..."
ssh -i "$SSH_KEY" akushnir@192.168.168.42 'bash -c "
set -euo pipefail
if command -v k6 &> /dev/null; then
  echo \"[✓] k6 already installed: $(k6 version)\"; exit 0
fi
TEMP_DIR=\$(mktemp -d); trap \"rm -rf \$TEMP_DIR\" EXIT; cd \"\$TEMP_DIR\"
curl -sSL \"https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz\" | tar xz
if [ -d k6-v0.50.0-linux-amd64 ]; then
  if [ -w /usr/local/bin ]; then
    mv k6-v0.50.0-linux-amd64/k6 /usr/local/bin/k6
  else
    sudo mv k6-v0.50.0-linux-amd64/k6 /usr/local/bin/k6
  fi
  chmod +x /usr/local/bin/k6 || sudo chmod +x /usr/local/bin/k6
  echo \"[✓] k6 installed: \$(k6 version)\"
else
  echo \"[ERROR] Failed to extract k6\"; exit 1
fi
"'

echo "[✓] Replica 2 ready"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[✓✓✓] ALL REPLICAS READY FOR LOAD TESTING"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
