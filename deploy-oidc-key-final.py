#!/usr/bin/env python3
"""
Deploy OIDC Issuer RSA Signing Key - Simplified Version
"""

import subprocess
import os
import base64

# Config
REMOTE_HOST = "192.168.168.31"
REMOTE_USER = "akushnir"
SSH_KEY = os.path.expanduser("~/.ssh/id_rsa_onprem")
REMOTE_FULL = f"{REMOTE_USER}@{REMOTE_HOST}"

print("Phase 2C: OIDC Issuer Key Deployment")
print(f"Target: {REMOTE_FULL}\n")

# Generate key
print("1. Generating RSA 2048-bit key...")
key = subprocess.check_output("openssl genrsa 2048 2>/dev/null", shell=True).decode()
print(f"   ✓ Generated ({len(key)} bytes)\n")

# Encode to base64
print("2. Encoding key (base64)...")
key_b64 = base64.b64encode(key.encode()).decode()
print(f"   ✓ Encoded ({len(key_b64)} bytes)\n")

# Create command that adds key to .env on remote
print("3. Adding key to remote .env...")
add_key_cmd = f"""
cat > /tmp/add_key.py << 'EOF'
import base64, sys
key_b64 = input().strip()
key = base64.b64decode(key_b64).decode()
with open('.env', 'a') as f:
    f.write('\\n# OIDC_ISSUER_SIGNING_KEY (Phase 2C)\\n')
    f.write(f'OIDC_ISSUER_SIGNING_KEY="{key}"\\n')
print('Key added')
EOF

echo '{key_b64}' | python3 /tmp/add_key.py
"""

result = subprocess.run(
    f'ssh -i {SSH_KEY} {REMOTE_FULL} "cd code-server-enterprise && {add_key_cmd}"',
    shell=True, capture_output=True, text=True
)

if result.returncode == 0:
    print(f"   ✓ {result.stdout.strip()}\n")
else:
    print(f"   ✗ Error: {result.stderr}\n")
    exit(1)

# Restart services
print("4. Restarting services...")
subprocess.run(
    f'ssh -i {SSH_KEY} {REMOTE_FULL} "cd code-server-enterprise && docker-compose restart oauth2-oidc-issuer oauth2-proxy && sleep 2"',
    shell=True, capture_output=True
)
print("   ✓ Services restarted\n")

# Check status
print("5. Service status:")
result = subprocess.run(
    f'ssh -i {SSH_KEY} {REMOTE_FULL} "cd code-server-enterprise && docker-compose ps --format \'table {{{{.Names}}}}\\t{{{{.Status}}}}\' 2>&1 | head -10"',
    shell=True, capture_output=True, text=True
)
print(result.stdout)

if "oauth2-oidc-issuer" in result.stdout and "Up" in result.stdout:
    print("\n✅ Phase 2C Complete!")
    print("\nNext: Verify OIDC endpoint is responding")
    print(f"  ssh -i {SSH_KEY} {REMOTE_FULL} 'curl -s http://oauth2-oidc-issuer:4182/.well-known/openid-configuration | jq .'")
else:
    print("\n⚠ Still starting - check logs:")
    print(f"  ssh -i {SSH_KEY} {REMOTE_FULL} 'cd code-server-enterprise && docker-compose logs oauth2-oidc-issuer -f'")
