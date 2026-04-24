#!/usr/bin/env python3
"""
Deploy OIDC Issuer RSA Signing Key to remote host (Fixed version)
"""

import subprocess
import os
import sys
import tempfile

def run_cmd(cmd, description=""):
    """Run command and return output."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        if description:
            print(f"✓ {description}")
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"✗ {description}")
        print(f"Error: {e.stderr}")
        sys.exit(1)

# Configuration
REMOTE_HOST = "192.168.168.31"
REMOTE_USER = "akushnir"
SSH_KEY = os.path.expanduser("~/.ssh/id_rsa_onprem")
REMOTE_FULL = f"{REMOTE_USER}@{REMOTE_HOST}"
SSH = f"ssh -i {SSH_KEY}"

print("Phase 2C: OIDC Issuer Signing Key Deployment")
print(f"Target: {REMOTE_FULL}")
print()

# Step 1: Generate RSA key locally
print("1. Generating RSA 2048-bit key...")
key_content = subprocess.check_output("openssl genrsa 2048 2>/dev/null", shell=True).decode()
print(f"   Key size: {len(key_content)} bytes")

# Step 2: Base64 encode the key for safe transmission
print("2. Encoding key for safe transmission...")
key_b64 = subprocess.check_output(
    "echo -n | openssl enc -A -base64",
    input=key_content.encode(),
    shell=True
).decode().strip()

# Step 3: Create deployment script on remote
print("3. Creating deployment script on remote...")
deploy_script = '''
import base64
import sys

# Decode key from stdin (base64)
key_b64 = sys.stdin.read().strip()
key_content = base64.b64decode(key_b64).decode()

# Read .env
with open('.env', 'r') as f:
    env_content = f.read()

# Check if already exists
if 'OIDC_ISSUER_SIGNING_KEY=' in env_content:
    print("OIDC_ISSUER_SIGNING_KEY already in .env, skipping")
    sys.exit(0)

# Append key
with open('.env', 'a') as f:
    f.write('\\n# OIDC Issuer RSA Signing Key (Phase 2C)\\n')
    f.write(f'OIDC_ISSUER_SIGNING_KEY="{key_content}"\\n')

print("Key added to .env")

# Verify
with open('.env', 'r') as f:
    if 'BEGIN PRIVATE KEY' in f.read():
        print("Verification passed")
    else:
        print("Verification failed")
        sys.exit(1)
'''

# Step 4: Execute on remote
print("4. Deploying key to remote .env...")
cmd = f'echo "{key_b64}" | {SSH} {REMOTE_FULL} "cd code-server-enterprise && python3 - << \'PYTHONEOF\'\n{deploy_script}\nPYTHONEOF"'

result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
if result.returncode == 0:
    print("   ✓ Key deployed")
    print(f"   {result.stdout}")
else:
    print("   ✗ Deployment failed")
    print(f"   {result.stderr}")
    sys.exit(1)

# Step 5: Restart services
print("5. Restarting oauth2-oidc-issuer and oauth2-proxy...")
run_cmd(
    f'{SSH} {REMOTE_FULL} "cd code-server-enterprise && docker-compose restart oauth2-oidc-issuer oauth2-proxy && sleep 3"',
    "Services restarted"
)

# Step 6: Check status
print("6. Checking service status...")
result = subprocess.run(
    f'{SSH} {REMOTE_FULL} "cd code-server-enterprise && docker-compose ps --format \'table {{{{.Names}}}}\\t{{{{.Status}}}}\' | grep -E \'oauth2-oidc-issuer|oauth2-proxy|code-server|postgres\'"',
    shell=True, capture_output=True, text=True
)
print(result.stdout)

if "Up" in result.stdout:
    print("\n✓ Phase 2C: OIDC Key deployment COMPLETE")
    print("\nNext steps:")
    print("  1. Verify OIDC endpoint: curl -s https://ide.kushnir.cloud/.well-known/openid-configuration")
    print("  2. Run Phase 2D: Add JWT observability metrics")
    print("  3. Run Phase 2E: E2E testing")
else:
    print("\n⚠ Services still starting, check logs:")
    print(f"  {SSH} {REMOTE_FULL} 'cd code-server-enterprise && docker-compose logs oauth2-oidc-issuer -f'")
