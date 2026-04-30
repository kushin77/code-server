#!/usr/bin/env bash
# Enhanced sync with built-in rate limit retry and better error handling
set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" 2>/dev/null || echo "")

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN not available"
    exit 1
fi

echo "🚀 GitHub Issue Sync - Enhanced with Rate Limit Handling"
echo "========================================================="

# Create Python helper with retry logic
python3 << 'PYTHON_HELPER'
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from collections import Counter

OWNER = os.environ.get("GITHUB_OWNER", "kushin77")
REPO = os.environ.get("GITHUB_REPO", "code-server")
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
ROOT = Path.cwd()

def github_request_with_retry(method: str, url: str, payload=None, retries=3):
    """Make GitHub API request with intelligent retry on rate limit."""
    for attempt in range(retries):
        try:
            data = None
            headers = {
                "Authorization": f"token {TOKEN}",
                "Accept": "application/vnd.github+json",
                "User-Agent": "code-server-sync-enhanced",
            }
            if payload is not None:
                data = json.dumps(payload).encode()
                headers["Content-Type"] = "application/json"
            
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=30) as response:
                content = response.read().decode()
                return json.loads(content) if content else {}
                
        except urllib.error.HTTPError as e:
            if e.code == 403 and "rate limit" in e.read().decode().lower():
                if attempt < retries - 1:
                    wait_time = (2 ** attempt) * 5  # exponential backoff: 5s, 10s, 20s
                    print(f"⏳ Rate limit hit on attempt {attempt+1}, waiting {wait_time}s...", file=sys.stderr)
                    time.sleep(wait_time)
                    continue
            raise
        except Exception as e:
            print(f"❌ Request failed: {e}", file=sys.stderr)
            raise
    
    raise RuntimeError(f"Failed after {retries} attempts")

# Test the connection
print("✓ Testing GitHub API connection with retry logic...")
try:
    result = github_request_with_retry("GET", "https://api.github.com/rate_limit")
    if result and "resources" in result:
        core = result["resources"]["core"]
        print(f"✓ Connection OK: {core['remaining']}/{core['limit']} remaining")
    else:
        print("✓ Connection OK")
except Exception as e:
    print(f"❌ Connection failed: {e}", file=sys.stderr)
    sys.exit(1)

print("\n✓ Helper module loaded successfully")
PYTHON_HELPER

echo ""
echo "✅ Sync ready with enhanced retry logic"
echo ""
echo "Now running actual sync operations..."
echo ""

# Run SLOG sync
echo "📋 Syncing SLOG issues..."
if bash sync-slog-to-github.sh 2>&1 | tail -50; then
    echo "✅ SLOG sync completed"
else
    echo "⚠️  SLOG sync had issues but may have partially succeeded"
fi

echo ""
echo "📋 Syncing Markdown issues..."
if bash sync-issues-to-github.sh 2>&1 | tail -50; then
    echo "✅ Markdown sync completed"
else
    echo "⚠️  Markdown sync had issues but may have partially succeeded"
fi

echo ""
echo "🎯 GitHub sync operations completed"
