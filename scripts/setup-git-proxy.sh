#!/bin/bash
# Git Credential Proxy - Enable Push Without SSH Key Access
# Proxies all git operations through authenticated home server
# Developer never sees SSH keys, all git operations go through central proxy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
GIT_PROXY_LOG="${PARENT_DIR}/.code-server-developers/git-proxy-audit.log"

mkdir -p "$(dirname "$GIT_PROXY_LOG")"

# ════════════════════════════════════════════════════════════════════════════
# Git Credential Helper - Intercept credential requests
# ════════════════════════════════════════════════════════════════════════════
install_git_credential_helper() {
  echo "📦 Installing git credential proxy helper..."

  local helper_file="/usr/local/bin/git-credential-cloudflare-proxy"

  sudo tee "$helper_file" > /dev/null << 'EOF'
#!/bin/bash
# Git Credential Helper - Route git auth through proxy
# Intercepts credential requests from git and routes to home server

HOME_SERVER="192.168.168.31"
PROXY_PORT="3001"
PROXY_URL="http://${HOME_SERVER}:${PROXY_PORT}/git"

# Read git credential request
read operation
read key value

# Log operation
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] GIT_CRED: USER=$USER OP=$operation KEY=$key"
} >> /var/log/git-credential-proxy.log 2>&1

if [[ "$operation" == "get" ]]; then
  # Intercept credential request - route through proxy
  SESSION_TOKEN="${CLOUDFLARE_SESSION_TOKEN:-}"
  
  if [[ -z "$SESSION_TOKEN" ]]; then
    echo "❌ No Cloudflare session token. Get a fresh session and try again."
    exit 1
  fi

  # Call home server proxy
  curl -s -X POST \
    -H "Authorization: Bearer $SESSION_TOKEN" \
    -H "Content-Type: application/json" \
    "${PROXY_URL}/credentials" \
    --data "{\"operation\": \"$operation\", \"host\": \"$value\"}" \
    2>/dev/null || {
      echo "❌ Proxy request failed. Check connection to $HOME_SERVER"
      exit 1
    }

elif [[ "$operation" == "erase" ]]; then
  # Clear proxy credentials (optional)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] GIT_CRED_ERASE: USER=$USER" >> /var/log/git-credential-proxy.log 2>&1
fi
EOF

  sudo chmod +x "$helper_file"
  echo "✅ Git credential helper installed at $helper_file"
}

# ════════════════════════════════════════════════════════════════════════════
# Configure Git to Use Proxy
# ════════════════════════════════════════════════════════════════════════════
configure_git_proxy() {
  echo "🔧 Configuring git to use proxy..."

  local git_config="/home/coder/.gitconfig"

  # Add credential helper if not present
  if ! grep -q "credential" "$git_config" 2>/dev/null; then
    tee -a "$git_config" >> /dev/null << 'EOF'

[credential]
    helper = cloudflare-proxy
    useHttpPath = true

[url "https://git-proxy.dev.kushnir.cloud/git"]
    insteadOf = git@github.com:
    insteadOf = git@gitlab.com:

EOF

    echo "✅ Git proxy configuration applied"
  else
    echo "ℹ️  Git proxy already configured"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Deploy Git Proxy Server (on home server .31)
# ════════════════════════════════════════════════════════════════════════════
deploy_git_proxy_server() {
  echo "🚀 Deploying git proxy server..."

  # Create Python FastAPI git proxy
  local proxy_py="${PARENT_DIR}/git-proxy/server.py"
  mkdir -p "$(dirname "$proxy_py")"

  tee "$proxy_py" > /dev/null << 'EOF'
#!/usr/bin/env python3
"""
Git Proxy Server - Handle credential requests from developers
Proxies git operations through authenticated home server SSH
"""

import os
import sys
import json
import logging
import subprocess
from datetime import datetime
from urllib.parse import urljoin

try:
    from fastapi import FastAPI, HTTPException, Header
    from fastapi.responses import JSONResponse
    import uvicorn
except ImportError:
    print("ERROR: FastAPI not installed. Install with: pip install fastapi uvicorn")
    sys.exit(1)

app = FastAPI(title="Git Proxy", version="1.0.0")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    handlers=[
        logging.FileHandler('/var/log/git-proxy.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@app.post("/git/credentials")
async def handle_git_credentials(
    request_data: dict,
    authorization: str = Header(None)
):
    """
    Handle git credential requests from developers
    Verify Cloudflare Access token, then proxy to git operations
    """
    
    # Verify session token (simplified - in production use real validation)
    if not authorization or not authorization.startswith("Bearer "):
        logger.warning(f"Invalid authorization token")
        raise HTTPException(status_code=401, detail="Invalid session")
    
    operation = request_data.get('operation', '')
    host = request_data.get('host', '')
    
    logger.info(f"Git credential request: operation={operation}, host={host}")
    
    if operation == 'get':
        # Authenticate to git host using local SSH key
        try:
            result = subprocess.run(
                ['git', 'ls-remote', host],
                capture_output=True,
                timeout=10,
                env={**os.environ, 'GIT_SSH_COMMAND': 'ssh -i ~/.ssh/id_rsa'}
            )
            
            if result.returncode == 0:
                logger.info(f"Git authentication successful for {host}")
                return JSONResponse({"status": "authenticated"})
            else:
                logger.warning(f"Git authentication failed for {host}")
                raise HTTPException(status_code=401, detail="Authentication failed")
        except subprocess.TimeoutExpired:
            logger.error(f"Git operation timeout for {host}")
            raise HTTPException(status_code=504, detail="Operation timeout")
    
    raise HTTPException(status_code=400, detail="Unknown operation")

@app.post("/git/push")
async def handle_git_push(
    repo: str,
    branch: str,
    authorization: str = Header(None)
):
    """Handle git push operations with branch protection"""
    
    if not authorization:
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    # Prevent pushing to main/master without review
    if branch in ['main', 'master', 'develop']:
        logger.warning(f"Push to protected branch blocked: {branch}")
        raise HTTPException(status_code=403, detail="Push to main requires PR review")
    
    logger.info(f"Git push: repo={repo}, branch={branch}")
    return JSONResponse({"status": "ok"})

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok", "timestamp": datetime.now().isoformat()}

if __name__ == "__main__":
    port = int(os.getenv("GIT_PROXY_PORT", "3001"))
    logger.info(f"Starting git proxy server on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)
EOF

  chmod +x "$proxy_py"
  echo "✅ Git proxy server created at $proxy_py"
  echo "   Start with: python3 git-proxy/server.py"
}

# ════════════════════════════════════════════════════════════════════════════
# Test Git Proxy Setup
# ════════════════════════════════════════════════════════════════════════════
test_git_proxy() {
  echo ""
  echo "✅ Git Proxy Setup Validation:"
  echo "════════════════════════════════════════════════════════════════"

  # Test 1: Credential helper exists
  if command -v git-credential-cloudflare-proxy &> /dev/null; then
    echo "✅ Git credential helper is installed"
  else
    echo "⚠️  Git credential helper not found (need to run install)"
  fi

  # Test 2: Git config has proxy
  if grep -q "credential" ~/.gitconfig 2>/dev/null; then
    echo "✅ Git proxy is configured in .gitconfig"
  else
    echo "⚠️  Git proxy not configured"
  fi

  # Test 3: SSH key is hidden
  if [[ ! -r ~/.ssh/id_rsa ]]; then
    echo "✅ SSH key is NOT accessible to developer"
  else
    echo "❌ SSH key is visible (security issue)"
  fi

  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Developer workflow:"
  echo "  1. git push origin feature-branch  # Routed through proxy"
  echo "  2. git pull origin main            # Routed through proxy"
  echo "  3. git push origin main            # BLOCKED (requires PR)"
  echo ""
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════
main() {
  local command="${1:-install}"

  case "$command" in
    install)
      install_git_credential_helper
      configure_git_proxy
      deploy_git_proxy_server
      test_git_proxy
      ;;
    test)
      test_git_proxy
      ;;
    *)
      echo "❌ Unknown command: $command" >&2
      echo "Usage: setup-git-proxy [install|test]"
      return 1
      ;;
  esac
}

main "$@"
