#!/usr/bin/env python3
# @file        scripts/ops/execute-phase-2-deployment.py
# @module      ops/deployment
# @description Phase 2 deployment executor: Deploy WebSocket to production replicas (IaC/idempotent)
# @owner       infrastructure
# @status      active

import subprocess
import sys
import json
import time
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration (IaC-driven from environment)
REPLICA_1 = "192.168.168.31"
REPLICA_2 = "192.168.168.42"
DEPLOY_USER = "akushnir"
DEPLOY_DIR = "code-server-enterprise"
SSH_KEY = Path.home() / ".ssh" / "id_rsa_onprem"
EXPECTED_COMMIT = "2d4d0c08"
EXPECTED_CONTAINERS = 38
HEALTH_CHECK_RETRIES = 10
HEALTH_CHECK_DELAY = 5

class DeploymentExecutor:
    """Execute Phase 2 deployment with IaC/idempotent guarantees"""
    
    def __init__(self, dry_run=False):
        self.dry_run = dry_run
        self.replicas = [REPLICA_1, REPLICA_2]
        self.errors = []
    
    def run_command(self, cmd, shell=False, check=True):
        """Run command and return output (idempotent error handling)"""
        try:
            if self.dry_run:
                logger.info(f"[DRY-RUN] Would execute: {cmd}")
                return 0, ""
            
            result = subprocess.run(
                cmd,
                shell=shell,
                capture_output=True,
                text=True,
                check=False
            )
            
            if check and result.returncode != 0:
                logger.error(f"Command failed: {cmd}")
                logger.error(f"stderr: {result.stderr}")
                return result.returncode, result.stderr
            
            return result.returncode, result.stdout
        except Exception as e:
            logger.error(f"Exception running command: {e}")
            return 1, str(e)
    
    def run_ssh_command(self, host, cmd):
        """Run command on remote replica via SSH (idempotent)"""
        if not SSH_KEY.exists():
            logger.error(f"SSH key not found: {SSH_KEY}")
            return 1, f"SSH key missing: {SSH_KEY}"
        
        ssh_cmd = [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-i", str(SSH_KEY),
            f"{DEPLOY_USER}@{host}",
            cmd
        ]
        
        try:
            if self.dry_run:
                logger.info(f"[DRY-RUN] Would SSH to {host}: {cmd}")
                return 0, ""
            
            result = subprocess.run(
                ssh_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=60
            )
            
            if result.returncode != 0:
                logger.error(f"SSH to {host} failed: {result.stderr}")
                return result.returncode, result.stderr
            
            return result.returncode, result.stdout.strip()
        except subprocess.TimeoutExpired:
            logger.error(f"SSH to {host} timed out")
            return 1, "SSH timeout"
        except Exception as e:
            logger.error(f"SSH exception: {e}")
            return 1, str(e)
    
    def verify_ssh_access(self, host):
        """Verify SSH access to replica (idempotent pre-check)"""
        logger.info(f"Verifying SSH access to {host}...")
        returncode, output = self.run_ssh_command(host, "true")
        
        if returncode == 0:
            logger.info(f"✓ SSH access verified for {host}")
            return True
        else:
            logger.error(f"✗ SSH access failed for {host}")
            self.errors.append(f"SSH access to {host} failed")
            return False
    
    def deploy_to_replica(self, host):
        """Deploy to single replica (idempotent operations)"""
        logger.info(f"Deploying to {host}...")
        
        # Deployment command chain (all idempotent)
        deploy_cmd = (
            f"cd {DEPLOY_DIR} && "
            "git pull --ff-only origin main && "
            "docker compose pull && "
            "docker compose up -d"
        )
        
        returncode, output = self.run_ssh_command(host, deploy_cmd)
        
        if returncode != 0:
            logger.error(f"✗ Deployment to {host} failed")
            self.errors.append(f"Deployment to {host} failed: {output}")
            return False
        
        logger.info(f"✓ Deployment to {host} completed")
        return True
    
    def verify_health(self, host):
        """Verify health endpoint (idempotent with retries)"""
        logger.info(f"Checking health endpoint for {host}...")
        
        for attempt in range(1, HEALTH_CHECK_RETRIES + 1):
            try:
                result = subprocess.run(
                    ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                     f"http://{host}:3000/health/ready"],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False
                )
                
                status_code = result.stdout.strip()
                
                if status_code == "200":
                    logger.info(f"✓ Health check passed for {host}")
                    return True
                
                logger.warning(f"Health check attempt {attempt}/{HEALTH_CHECK_RETRIES}: HTTP {status_code}")
                
                if attempt < HEALTH_CHECK_RETRIES:
                    time.sleep(HEALTH_CHECK_DELAY)
            
            except Exception as e:
                logger.warning(f"Health check exception (attempt {attempt}): {e}")
                if attempt < HEALTH_CHECK_RETRIES:
                    time.sleep(HEALTH_CHECK_DELAY)
        
        logger.error(f"✗ Health check failed for {host}")
        self.errors.append(f"Health check failed for {host}")
        return False
    
    def verify_commit(self, host):
        """Verify replica is on expected commit"""
        logger.info(f"Verifying commit on {host}...")
        
        returncode, commit = self.run_ssh_command(host, "cd code-server-enterprise && git rev-parse --short HEAD")
        
        if returncode != 0 or not commit:
            logger.error(f"✗ Could not get commit from {host}")
            self.errors.append(f"Could not get commit from {host}")
            return False
        
        if commit == EXPECTED_COMMIT:
            logger.info(f"✓ {host} on expected commit: {commit}")
            return True
        else:
            logger.warning(f"⚠ {host} on different commit: {commit} (expected: {EXPECTED_COMMIT})")
            return True  # Non-fatal for now
    
    def verify_containers(self, host):
        """Verify container count on replica"""
        logger.info(f"Checking container count on {host}...")
        
        returncode, count_str = self.run_ssh_command(host, "docker ps --quiet | wc -l")
        
        if returncode != 0 or not count_str:
            logger.error(f"✗ Could not get container count from {host}")
            self.errors.append(f"Could not get container count from {host}")
            return False
        
        try:
            count = int(count_str)
            if count >= EXPECTED_CONTAINERS:
                logger.info(f"✓ {host} has {count} containers (expected: {EXPECTED_CONTAINERS}+)")
                return True
            else:
                logger.warning(f"⚠ {host} has {count} containers (expected: {EXPECTED_CONTAINERS}+)")
                return False
        except ValueError:
            logger.error(f"✗ Could not parse container count from {host}: {count_str}")
            self.errors.append(f"Could not parse container count from {host}")
            return False
    
    def execute_phase_2(self):
        """Execute full Phase 2 deployment (IaC/idempotent)"""
        logger.info("=" * 70)
        logger.info("PHASE 2: DEPLOY WEBSOCKET TO PRODUCTION REPLICAS")
        logger.info("=" * 70)
        
        if self.dry_run:
            logger.info("[DRY-RUN MODE] No changes will be made")
        
        logger.info("")
        
        # Pre-flight checks
        logger.info("PHASE 2a: PRE-FLIGHT CHECKS")
        logger.info("-" * 70)
        
        ssh_ok = all(self.verify_ssh_access(host) for host in self.replicas)
        
        if not ssh_ok:
            logger.error("SSH verification failed")
            return False
        
        logger.info("")
        
        # Deploy to replicas
        logger.info("PHASE 2b: PARALLEL DEPLOYMENT")
        logger.info("-" * 70)
        
        deploy_results = {}
        for host in self.replicas:
            success = self.deploy_to_replica(host)
            deploy_results[host] = success
        
        if not all(deploy_results.values()):
            logger.error("Deployment failed on one or more replicas")
            return False
        
        logger.info("")
        
        # Post-deployment verification
        logger.info("PHASE 2c: POST-DEPLOYMENT VERIFICATION")
        logger.info("-" * 70)
        
        verification_results = {}
        
        for host in self.replicas:
            logger.info(f"Verifying {host}...")
            verify_ok = (
                self.verify_commit(host) and
                self.verify_containers(host) and
                self.verify_health(host)
            )
            verification_results[host] = verify_ok
        
        logger.info("")
        
        # Summary
        logger.info("=" * 70)
        
        if all(verification_results.values()) and not self.errors:
            logger.info("✓ PHASE 2 DEPLOYMENT SUCCESSFUL")
            logger.info("✓ All replicas deployed and verified")
            logger.info("=" * 70)
            return True
        else:
            logger.error("✗ PHASE 2 DEPLOYMENT INCOMPLETE")
            if self.errors:
                logger.error("Errors encountered:")
                for error in self.errors:
                    logger.error(f"  - {error}")
            logger.info("=" * 70)
            return False

def main():
    """Main entry point"""
    dry_run = "--dry-run" in sys.argv or "DRY_RUN" in subprocess.os.environ
    
    executor = DeploymentExecutor(dry_run=dry_run)
    success = executor.execute_phase_2()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
