#!/usr/bin/env python3
# @file        scripts/ops/verify-production-readiness.py
# @module      ops/verification
# @description Comprehensive production readiness audit for Kushnir.cloud
# @owner       platform
# @status      active
#

import os
import sys
import json
import logging
from datetime import datetime, timezone

# Add parent directory to path for common imports if needed
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Configuration from environment
REPLICAS = os.getenv("REPLICAS", "192.168.168.31,192.168.168.42").split(",")
NAS_MOUNT = os.getenv("NAS_MOUNT_POINT", "/mnt/nas/persistent")

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def check_connectivity(host):
    """Verify host responds to SSH"""
    logger.info(f"Checking connectivity to {host}...")
    response = os.system(f"ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no akushnir@{host} 'echo OK' > /dev/null 2>&1")
    return response == 0

def check_nas_mount(host):
    """Verify NAS is mounted on host"""
    logger.info(f"Verifying NAS mount on {host}...")
    cmd = f"ssh akushnir@{host} 'mountpoint -q {NAS_MOUNT}' > /dev/null 2>&1"
    return os.system(cmd) == 0

def run_readiness_audit():
    """Main audit execution"""
    logger.info("Starting Production Readiness Audit...")
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": "PASS",
        "nodes": []
    }
    
    for replica in REPLICAS:
        node_status = {"host": replica, "checks": {}}
        
        # 1. Connectivity
        up = check_connectivity(replica)
        node_status["checks"]["connectivity"] = "OK" if up else "FAIL"
        
        # 2. Storage
        if up:
            nas_ok = check_nas_mount(replica)
            node_status["checks"]["nas_mount"] = "OK" if nas_ok else "FAIL"
        else:
            node_status["checks"]["nas_mount"] = "UNREACHABLE"
            
        report["nodes"].append(node_status)
        if any(v == "FAIL" for v in node_status["checks"].values()):
            report["status"] = "FAIL"
            
    logger.info(f"Audit Status: {report['status']}")
    return report

if __name__ == "__main__":
    result = run_readiness_audit()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["status"] == "PASS" else 1)
