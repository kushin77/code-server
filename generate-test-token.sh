#!/bin/bash
# Generate test Cloudflare token for development/testing
# NOTE: For production, get real token from Cloudflare dashboard

python3 << 'PYEOF'
import secrets
import os

# Generate 64-character hex string (32 bytes * 2 hex chars)
token_hex = secrets.token_hex(32)

# Format as aaaa-bbbb... (4 chars, dash, rest)
token = f"{token_hex[:4]}-{token_hex[4:]}"

print(f"TEST_TOKEN={token}")
print(f"Env format: CLOUDFLARE_TUNNEL_TOKEN={token}")
print()
print("⚠️  NOTE: This is a test token for development/testing only")
print("For production, obtain real token from:")
print("  https://dash.cloudflare.com/ → kushnir.cloud → Networks → Tunnels → ide-home-dev")
PYEOF
