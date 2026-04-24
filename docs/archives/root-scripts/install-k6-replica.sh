#!/bin/bash
set -euo pipefail
HOST=$1
SSH_KEY="$HOME/.ssh/id_rsa_onprem"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[*] Installing k6 on $HOST..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Remote installation script
REMOTE_SCRIPT='
set -euo pipefail
mkdir -p ~/.local/bin
cd /tmp
rm -rf k6-tmp-$$
# Create temporary directory (idempotent: use -p or unique name)
mkdir -p k6-tmp-$$
cd k6-tmp-$$

echo "[*] Downloading k6 v0.50.0..."
curl -sSL "https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz" | tar xz

if [ -d k6-v0.50.0-linux-amd64 ]; then
  echo "[*] Installing to ~/.local/bin..."
  mv k6-v0.50.0-linux-amd64/k6 ~/.local/bin/k6
  chmod +x ~/.local/bin/k6
  
  echo "[*] Verifying installation..."
  export PATH=~/.local/bin:$PATH
  ~/.local/bin/k6 version
  
  echo "[✓] k6 installed successfully"
else
  echo "[ERROR] Failed to extract k6"
  exit 1
fi

cd /tmp
rm -rf k6-tmp-$$

echo "[*] To use k6 from anywhere, add to ~/.bashrc:"
echo "export PATH=\$HOME/.local/bin:\$PATH"
'

ssh -i "$SSH_KEY" akushnir@$HOST bash << EOF
$REMOTE_SCRIPT
EOF

echo "[✓✓] Installation complete on $HOST"
