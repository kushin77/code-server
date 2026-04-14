#!/usr/bin/env python3
"""
Git Credential Helper for Cloudflare Proxy Integration
Configure developers' machines to use the git proxy server.

Usage:
  git config --global credential.helper cloudflare-proxy

Or per-repo:
  git config credential.helper cloudflare-proxy
"""

import json
import sys
import subprocess
import os
from typing import Optional

# Configuration
PROXY_HOST = os.getenv("GIT_PROXY_HOST", "git-proxy.dev.yourdomain.com")
PROXY_PORT = os.getenv("GIT_PROXY_PORT", "8001")
CLOUDFLARE_TOKEN_ENDPOINT = os.getenv(
    "CLOUDFLARE_TOKEN_ENDPOINT",
    "https://dev.yourdomain.com/oauth/token"
)


def read_git_input() -> dict:
    """Read git credential helper input protocol"""
    data = {}
    while True:
        line = sys.stdin.readline()
        if not line or line == "\n":
            break
        if "=" in line:
            key, value = line.strip().split("=", 1)
            data[key] = value
    return data


def get_cloudflare_token() -> Optional[str]:
    """
    Get Cloudflare Access JWT token.
    The token is usually available via environment variable
    or from local Cloudflare tunnel authentication.
    """
    # Check environment first (set by Cloudflare tunnel)
    token = os.getenv("CF_ACCESS_TOKEN")
    if token:
        return token

    # Try to get from Cloudflare local machine auth
    try:
        result = subprocess.run(
            ["cloudflared", "access", "token", "--hostname", PROXY_HOST],
            capture_output=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.decode().strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    raise RuntimeError("Unable to obtain Cloudflare Access token. Ensure CF_ACCESS_TOKEN is set or cloudflared is running.")


def call_proxy(operation: str, **kwargs) -> dict:
    """Call the git proxy server API"""

    token = get_cloudflare_token()
    headers = {"Authorization": f"Bearer {token}"}

    import requests

    if operation == "get":
        # Ask proxy to authenticate
        response = requests.post(
            f"https://{PROXY_HOST}:{PROXY_PORT}/git/credentials",
            params={
                "operation": "get",
                "host": kwargs.get("host", "github.com"),
                "username": kwargs.get("username", "git")
            },
            headers=headers,
            timeout=10
        )
    elif operation == "push":
        response = requests.post(
            f"https://{PROXY_HOST}:{PROXY_PORT}/git/push",
            json={
                "repo": kwargs.get("repo"),
                "branch": kwargs.get("branch")
            },
            headers=headers,
            timeout=30
        )
    elif operation == "pull":
        response = requests.post(
            f"https://{PROXY_HOST}:{PROXY_PORT}/git/pull",
            json={
                "repo": kwargs.get("repo"),
                "branch": kwargs.get("branch")
            },
            headers=headers,
            timeout=30
        )
    elif operation == "store":
        # No-op
        return {}
    elif operation == "erase":
        # No-op
        return {}
    else:
        raise ValueError(f"Unknown operation: {operation}")

    if response.status_code == 200:
        return response.json()
    else:
        raise RuntimeError(f"Proxy error: {response.status_code} {response.text}")


def main():
    """Main credential helper entry point"""

    if len(sys.argv) < 2:
        print("Usage: git-credential-cloudflare-proxy <operation>", file=sys.stderr)
        sys.exit(1)

    operation = sys.argv[1]

    try:
        # Read input from git
        data = read_git_input()

        if operation == "get":
            # Ask proxy to authenticate
            result = call_proxy("get", host=data.get("host", "github.com"))

            # Output in git credential helper format
            print(f"host={data['host']}")
            print(f"protocol={data.get('protocol', 'https')}")
            print(f"username={result.get('username', 'git')}")
            print("password=authenticated-via-proxy")

        elif operation == "store":
            # No-op, credentials handled by proxy
            pass

        elif operation == "erase":
            # No-op
            pass

        else:
            raise ValueError(f"Unknown operation: {operation}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
