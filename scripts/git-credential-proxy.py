#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# Git Credential Helper for Read-Only Access (Layer 4)
# P1 Issue #187 - Read-Only IDE Access Control
#
# This script intercepts git credential requests and proxies them through
# the home server's SSH keys, preventing developers from accessing SSH keys
# while still enabling git push/pull operations.
#
# Installation:
#   chmod +x scripts/git-credential-proxy.py
#   git config --global credential.helper $(pwd)/scripts/git-credential-proxy.py
#
# How it works:
#   1. Developer runs: git push origin main
#   2. Git calls: git credential-proxy get (for SSH credentials)
#   3. This script sends HTTP request to git-proxy.dev.yourdomain.com
#   4. Proxy server performs git push with real SSH key
#   5. Developer never sees the SSH key
#
# ═══════════════════════════════════════════════════════════════════════════════

import sys
import os
import json
import urllib.request
import urllib.error
import base64
import logging
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

PROXY_SERVER = os.getenv('GIT_PROXY_SERVER', 'git-proxy.ide.kushnir.cloud')
PROXY_PORT = os.getenv('GIT_PROXY_PORT', '443')
LOG_FILE = Path.home() / '.config/code-server/git-proxy.log'
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logger = logging.getLogger('git-credential-proxy')
logger.addHandler(logging.FileHandler(LOG_FILE))
logger.setLevel(logging.DEBUG)

# ─────────────────────────────────────────────────────────────────────────────
# Credential Helper Protocol Handler
# ─────────────────────────────────────────────────────────────────────────────

def parse_credential_input():
    """
    Parse credential helper protocol input from git.
    Format:
      protocol=https
      host=github.com
      username=<optional>
      password=<optional>
    """
    credentials = {}
    while True:
        line = sys.stdin.readline().rstrip('\n')
        if not line:
            break
        if '=' in line:
            key, value = line.split('=', 1)
            credentials[key] = value
    return credentials

def output_credentials(protocol, host, username, password):
    """
    Output credentials in the credential helper protocol format.
    """
    print(f'protocol={protocol}')
    print(f'host={host}')
    print(f'username={username}')
    print(f'password={password}')

def get_proxy_token():
    """
    Get authentication token for the git proxy.
    Tokens are stored in ~/.config/code-server/proxy-token
    """
    token_file = Path.home() / '.config/code-server/proxy-token'
    if token_file.exists():
        return token_file.read_text().strip()
    return None

# ─────────────────────────────────────────────────────────────────────────────
# Proxy Communication
# ─────────────────────────────────────────────────────────────────────────────

def request_credentials_from_proxy(host, operation='pull'):
    """
    Send credential request to proxy server.
    
    Request:
      POST /api/v1/git-credentials
      Authorization: Bearer <token>
      {
        "host": "github.com",
        "operation": "pull",
        "developer_id": "user@example.com"
      }
    
    Response:
      {
        "protocol": "https",
        "host": "github.com",
        "username": "git",
        "password": "<ephemeral-ssh-key-or-token>"
      }
    """
    token = get_proxy_token()
    if not token:
        logger.warning(f'No proxy token found - git operations may fail')
        return None
    
    url = f'https://{PROXY_SERVER}:{PROXY_PORT}/api/v1/git-credentials'
    
    payload = json.dumps({
        'host': host,
        'operation': operation,
        'developer_id': os.getenv('USER', 'unknown'),
        'session_id': os.getenv('SESSION_ID', 'unknown')
    }).encode('utf-8')
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json',
        'X-Developer': os.getenv('USER'),
        'X-Session': os.getenv('SESSION_ID', ''),
    }
    
    req = urllib.request.Request(url, data=payload, headers=headers)
    req.get_method = lambda: 'POST'
    
    try:
        logger.debug(f'Contacting proxy: {url}')
        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.loads(response.read())
            logger.info(f'Proxy returned credentials for {host}')
            return result
    except urllib.error.HTTPError as e:
        logger.error(f'Proxy HTTP error: {e.code} {e.reason}')
        return None
    except urllib.error.URLError as e:
        logger.error(f'Proxy connection error: {e.reason}')
        return None
    except Exception as e:
        logger.error(f'Unexpected proxy error: {e}')
        return None

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

def main():
    """
    Main credential helper entry point.
    Operations: get, store, erase
    """
    if len(sys.argv) < 2:
        logger.error('No operation specified')
        sys.exit(1)
    
    operation = sys.argv[1]
    
    if operation == 'get':
        # Developer is asking for credentials to perform a git operation
        credentials = parse_credential_input()
        host = credentials.get('host', '')
        protocol = credentials.get('protocol', 'https')
        
        if not host:
            logger.error('No host specified in credential request')
            sys.exit(1)
        
        # Request credentials from proxy
        result = request_credentials_from_proxy(host, operation='pull')
        
        if result:
            output_credentials(
                result.get('protocol', protocol),
                result.get('host', host),
                result.get('username', 'git'),
                result.get('password', '')
            )
        else:
            # Fallback: allow git to prompt for password (not ideal, but safe)
            logger.warning(f'Proxy unavailable - developer may be prompted for password')
            sys.exit(1)
    
    elif operation == 'store':
        # Developer tried to save credentials - reject this
        # (developers should not be storing credentials locally)
        credentials = parse_credential_input()
        logger.info(f'Rejected credential store attempt for {credentials.get("host", "unknown")}')
        sys.exit(1)
    
    elif operation == 'erase':
        # Erase credentials
        credentials = parse_credential_input()
        logger.info(f'Credential erase request for {credentials.get("host", "unknown")}')
        # Let git erase what it wants
        sys.exit(0)

if __name__ == '__main__':
    main()
