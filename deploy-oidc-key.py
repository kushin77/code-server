#!/usr/bin/env python3
"""
Deploy OIDC Issuer RSA Signing Key to remote host
Usage: python3 deploy-oidc-key.py [--host 192.168.168.31] [--user akushnir]
"""

import subprocess
import sys
import os
import tempfile
import argparse

def run_cmd(cmd, description="", check=True):
    """Run a shell command and return output."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
        if description:
            print(f"✓ {description}")
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"✗ {description}")
        print(f"  Error: {e.stderr}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Deploy OIDC Issuer RSA key to remote")
    parser.add_argument("--host", default="192.168.168.31", help="Remote host")
    parser.add_argument("--user", default="akushnir", help="Remote user")
    parser.add_argument("--key-path", default=os.path.expanduser("~/.ssh/id_rsa_onprem"), help="SSH key path")
    args = parser.parse_args()
    
    remote = f"{args.user}@{args.host}"
    ssh_cmd = f"ssh -i {args.key_path}"
    ssh_key = f"-i {args.key_path}"
    
    print("Phase 2C: OIDC Issuer Signing Key Deployment")
    print(f"Target: {remote}")
    print()
    
    # Step 1: Generate RSA key
    print("1. Generating RSA 2048-bit key...")
    key_content = run_cmd("openssl genrsa 2048 2>/dev/null", "RSA key generated")
    
    # Step 2: Create Python script for remote deployment
    print("2. Preparing deployment script...")
    deploy_script = f"""
import os
import sys

# Read key from stdin
key_content = sys.stdin.read()

# Update .env
env_file = '.env'

# Check if key already exists
with open(env_file, 'r') as f:
    content = f.read()

if 'OIDC_ISSUER_SIGNING_KEY=' in content:
    print("WARNING: OIDC_ISSUER_SIGNING_KEY already exists in .env")
    sys.exit(0)

# Remove any existing partial entry
lines = content.split('\\n')
lines = [l for l in lines if not l.startswith('OIDC_ISSUER_SIGNING_KEY=')]
content = '\\n'.join(lines)

# Append new key
with open(env_file, 'w') as f:
    f.write(content)
    if not content.endswith('\\n'):
        f.write('\\n')
    f.write('\\n# OIDC Issuer RSA Signing Key (generated for Phase 2C deployment)\\n')
    f.write(f'OIDC_ISSUER_SIGNING_KEY="{key_content}"\\n')

print("✓ OIDC_ISSUER_SIGNING_KEY added to .env")

# Verify
with open(env_file, 'r') as f:
    if 'BEGIN PRIVATE KEY' in f.read():
        print("✓ Key verification passed")
"""
    
    # Step 3: Upload and execute
    print("3. Deploying to remote host...")
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(deploy_script)
        deploy_script_path = f.name
    
    try:
        # Copy script to remote
        run_cmd(f"scp {ssh_key} {deploy_script_path} {remote}:/tmp/deploy_oidc_key.py", "Script uploaded")
        
        # Execute with key content piped to it
        key_for_pipe = key_content.replace('"', '\\"').replace('$', '\\$')
        exec_cmd = f'{ssh_cmd} {remote} "cd code-server-enterprise && python3 /tmp/deploy_oidc_key.py" << \'KEYEOF\'\n{key_content}\nKEYEOF'
        
        result = subprocess.run(exec_cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✓ Key deployed to remote")
            print(result.stdout)
        else:
            print(f"✗ Deployment failed")
            print(result.stderr)
            sys.exit(1)
        
        # Step 4: Restart services
        print("4. Restarting services...")
        run_cmd(f'{ssh_cmd} {remote} "cd code-server-enterprise && docker-compose restart oauth2-oidc-issuer oauth2-proxy"', 
                "Services restarted")
        
        # Step 5: Verify
        print("5. Verifying deployment...")
        result = subprocess.run(
            f'{ssh_cmd} {remote} "cd code-server-enterprise && docker-compose ps --format \'table {{{{.Names}}}}\\t{{{{.Status}}}}\'  | grep -E \'oauth2-oidc-issuer|oauth2-proxy\'"',
            shell=True, capture_output=True, text=True
        )
        print(result.stdout)
        
        if "Up" in result.stdout:
            print("✓ Phase 2C deployment complete!")
        else:
            print("⚠ Services may still be starting, check logs with:")
            print(f"  {ssh_cmd} {remote} 'cd code-server-enterprise && docker-compose logs oauth2-oidc-issuer'")
            
    finally:
        os.unlink(deploy_script_path)

if __name__ == "__main__":
    main()
