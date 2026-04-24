#!/usr/bin/env python3
# @file        scripts/ops/deploy-health-monitoring.py
# @module      infrastructure/monitoring
# @description Deploy health monitoring via Python subprocess (avoids terminal pager issues)
# @owner       Platform Engineering

import subprocess
import os
import sys
from pathlib import Path

def run_ssh(user, host, key, command):
    """Execute SSH command"""
    cmd = [
        "ssh",
        "-i", key,
        f"{user}@{host}",
        command
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def main():
    print("=== CLUSTER HEALTH MONITORING DEPLOYMENT ===")
    print()
    
    # Configuration
    ssh_user = "akushnir"
    ssh_key = os.path.expanduser("~/.ssh/id_rsa_onprem")
    r31 = "192.168.168.31"
    r42 = "192.168.168.42"
    deploy_path = "code-server-enterprise"
    
    # Verify SSH key exists
    if not os.path.exists(ssh_key):
        print(f"ERROR: SSH key not found: {ssh_key}")
        sys.exit(1)
    
    print(f"SSH Key: {ssh_key} ✓")
    print()
    
    # Deployment command
    deploy_cmd = f"cd {deploy_path} && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d prometheus"
    
    # Deploy to Replica 31
    print(f"[Replica 31] Deploying health monitoring...")
    success31, out31, err31 = run_ssh(ssh_user, r31, ssh_key, deploy_cmd)
    if success31:
        print(f"  ✓ Deployment successful")
    else:
        print(f"  ✗ Deployment failed")
        if err31:
            print(f"  Error: {err31[:100]}")
    
    # Deploy to Replica 42
    print(f"[Replica 42] Deploying health monitoring...")
    success42, out42, err42 = run_ssh(ssh_user, r42, ssh_key, deploy_cmd)
    if success42:
        print(f"  ✓ Deployment successful")
    else:
        print(f"  ✗ Deployment failed")
        if err42:
            print(f"  Error: {err42[:100]}")
    
    print()
    print("=== DEPLOYMENT COMPLETE ===")
    print()
    
    # Verification instructions
    print("Verification Instructions:")
    print(f"  1. Check Prometheus targets:")
    print(f"     curl -k https://{r31}:9090/api/v1/targets | jq '.data.activeTargets'")
    print()
    print(f"  2. Check health endpoint:")
    print(f"     curl -k https://{r31}/health")
    print(f"     curl -k https://{r42}/health")
    print()
    print(f"  3. View Prometheus:")
    print(f"     https://{r31}:9090/targets")
    print()
    
    # Exit code
    if success31 and success42:
        print("Status: ✅ SUCCESS")
        return 0
    else:
        print("Status: ⚠ PARTIAL/FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(main())
