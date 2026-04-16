#!/usr/bin/env python3
"""
Git Credential Helper - Cloudflare Proxy Integration

Intercepts git credential requests and proxies to remote git-credential-proxy
running on the home server. This allows developers to use git push/pull without
access to SSH keys.

Installation:
  1. Place this script in /usr/local/bin/git-credential-cloudflare-proxy
  2. chmod +x /usr/local/bin/git-credential-cloudflare-proxy
  3. Configure git: git config --global credential.helper cloudflare-proxy

Usage:
  git pull
  → requests credentials
  → reads from proxy
  → proxies to home server via HTTPS
  → home server returns SSH-authenticated response
  → git operation succeeds

Audit:
  - All requests logged to /var/log/git-proxy-audit.log
  - Developer identity passed via CLOUDFLARE_USER header
  - Session ID tracked for compliance
"""

import sys
import json
import hashlib
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

# Configuration
PROXY_HOST = os.environ.get('GIT_PROXY_HOST', 'git-proxy.on.code-server.dev')
PROXY_PORT = os.environ.get('GIT_PROXY_PORT', '443')
PROXY_URL = f"https://{PROXY_HOST}:{PROXY_PORT}"
AUDIT_LOG = Path("/var/log/git-proxy-audit.log")
SESSION_ID = os.environ.get('SESSION_ID', f"{os.getpid()}_{ int(datetime.now().timestamp())}")
DEVELOPER = os.environ.get('USER', 'unknown')

# ─────────────────────────────────────────────────────────────────────────────
# AUDIT LOGGING
# ─────────────────────────────────────────────────────────────────────────────

def log_request(operation: str, host: str, path: str, status: str):
    """Log all git credential requests for audit"""
    AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.utcnow().isoformat() + 'Z'
    
    log_entry = {
        "timestamp": timestamp,
        "session_id": SESSION_ID,
        "developer": DEVELOPER,
        "operation": operation,
        "host": host,
        "path": path,
        "status": status,
    }
    
    try:
        with open(AUDIT_LOG, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')
    except Exception as e:
        print(f"⚠️  Failed to log to audit trail: {e}", file=sys.stderr)

# ─────────────────────────────────────────────────────────────────────────────
# GIT CREDENTIAL PROTOCOL
# ─────────────────────────────────────────────────────────────────────────────

def parse_credentials() -> Dict[str, str]:
    """Parse git credential protocol input"""
    credentials = {}
    for line in sys.stdin:
        line = line.strip()
        if '=' in line:
            key, value = line.split('=', 1)
            credentials[key] = value
    
    return credentials

def output_credentials(username: str, password: str, host: str, path: str):
    """Output credentials in git credential protocol format"""
    sys.stdout.write(f"username={username}\n")
    sys.stdout.write(f"password={password}\n")
    sys.stdout.flush()

# ─────────────────────────────────────────────────────────────────────────────
# PROXY COMMUNICATION
# ─────────────────────────────────────────────────────────────────────────────

def get_credentials_from_proxy(host: str, path: str, protocol: str = "https") -> Optional[Dict]:
    """Request credentials from remote proxy server"""
    try:
        import urllib.request
        import urllib.error
        
        request_body = json.dumps({
            "host": host,
            "path": path,
            "protocol": protocol,
            "developer": DEVELOPER,
            "session_id": SESSION_ID,
        }).encode()
        
        req = urllib.request.Request(
            f"{PROXY_URL}/credential/get",
            data=request_body,
            headers={
                "Content-Type": "application/json",
                "X-Developer-ID": DEVELOPER,
                "X-Session-ID": SESSION_ID,
                "X-Git-Repo": f"{protocol}://{host}/{path}",
            }
        )
        
        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.loads(response.read())
            log_request("get", host, path, "SUCCESS")
            return result
            
    except Exception as e:
        log_request("get", host, path, f"FAILED:{str(e)}")
        print(f"❌ Failed to retrieve credentials from proxy: {e}", file=sys.stderr)
        return None

# ─────────────────────────────────────────────────────────────────────────────
# OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

def operation_get():
    """git credential fill (request credentials)"""
    creds = parse_credentials()
    host = creds.get('host')
    path = creds.get('path')
    protocol = creds.get('protocol', 'https')
    
    if not host:
        print("❌ Missing 'host' in credential request", file=sys.stderr)
        return
    
    # Request from proxy
    proxy_creds = get_credentials_from_proxy(host, path or '', protocol)
    
    if proxy_creds:
        output_credentials(
            username=proxy_creds.get('username', 'git'),
            password=proxy_creds.get('password', ''),
            host=host,
            path=path or '',
        )
    else:
        log_request("get", host, path or '', "REJECTED")
        print("❌ No credentials available via proxy", file=sys.stderr)
        sys.exit(1)

def operation_approved():
    """git credential approve (cache successful credentials)"""
    creds = parse_credentials()
    host = creds.get('host')
    path = creds.get('path', '')
    
    # Proxy stores successful credentials for caching
    # We don't store locally (read-only policy)
    log_request("approve", host, path, "CACHED_ON_PROXY")

def operation_reject():
    """git credential reject (clear cached credentials)"""
    creds = parse_credentials()
    host = creds.get('host')
    path = creds.get('path', '')
    
    log_request("reject", host, path, "REJECTED")

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: git-credential-cloudflare-proxy <operation>", file=sys.stderr)
        print("Operations: get, store, erase, approve, reject", file=sys.stderr)
        sys.exit(1)
    
    operation = sys.argv[1]
    
    try:
        if operation == "get":
            operation_get()
        elif operation in ("store", "erase"):
            # Read-only policy: don't cache locally
            pass
        elif operation == "approve":
            operation_approved()
        elif operation == "reject":
            operation_reject()
        else:
            print(f"❌ Unknown operation: {operation}", file=sys.stderr)
            sys.exit(1)
    
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:
        print(f"❌ Credential helper error: {e}", file=sys.stderr)
        log_request(operation, "unknown", "", f"ERROR:{str(e)}")
        sys.exit(1)
