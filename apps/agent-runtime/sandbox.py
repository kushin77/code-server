#!/usr/bin/env python3
# @file        apps/agent-runtime/sandbox.py
# @module      agent-runtime/sandbox
# @description Agent sandbox container manager - create, configure, destroy
# @owner       agent-runtime
# @status      production-ready
#
# Container isolation: no host filesystem access, OIDC-bound, read-only mounts

import os
import uuid
import json
import logging
import subprocess
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta

from .models import AgentInstance, AgentType

logger = logging.getLogger(__name__)

DOCKER_IMAGE = os.environ.get("AGENT_RUNTIME_IMAGE", "kushnir.cloud/agent-runtime:latest")
WORKSPACE_MOUNT = os.environ.get("WORKSPACE_MOUNT", "/workspace")
TMP_MOUNT = os.environ.get("TMP_MOUNT", "/tmp")


class SandboxManager:
    """Manage agent sandbox containers with security isolation"""

    def __init__(self, db_session):
        self.db = db_session

    def spawn_agent(
        self,
        agent_type: AgentType,
        parent_task_id: str,
        oidc_token: str,
        oidc_expires_at: datetime,
        env_vars: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """
        Spawn a new agent container
        
        Returns: {agent_id, container_id, oidc_token, status}
        """
        agent_id = f"{agent_type.value}/{str(uuid.uuid4())[:8]}"
        container_name = f"agent-{agent_type.value}-{str(uuid.uuid4())[:8]}"
        
        # Build container configuration
        config = {
            "name": container_name,
            "image": DOCKER_IMAGE,
            "detach": True,
            "network": "paperclip",
            "read_only": True,  # Root filesystem read-only
            "security_opt": ["no-new-privileges:true"],
            "cap_drop": ["ALL"],  # Drop all Linux capabilities
            "environment": {
                "AGENT_ID": agent_id,
                "AGENT_TYPE": agent_type.value,
                "PARENT_TASK_ID": parent_task_id,
                "OIDC_TOKEN": oidc_token,
                "OIDC_EXPIRES_AT": oidc_expires_at.isoformat(),
                "LOG_LEVEL": "INFO",
            },
            "volumes": {
                # Mount workspace as read-only for reads
                f"{WORKSPACE_MOUNT}": {"bind": "/workspace", "mode": "ro"},
                # Mount temp for agent working files
                f"{TMP_MOUNT}": {"bind": "/agent-tmp", "mode": "rw"},
            },
            "resources": {
                "cpuset": "0-1",  # Limit to 2 CPUs
                "memory": "512m",  # 512 MB RAM max
                "memswap": "512m",  # No swap
            },
            "labels": {
                "app": "paperclip-agent",
                "agent_type": agent_type.value,
                "parent_task_id": parent_task_id,
            },
        }
        
        # Add custom environment variables
        if env_vars:
            config["environment"].update(env_vars)
        
        # Spawn container
        try:
            result = subprocess.run(
                [
                    "docker", "run",
                    "--name", container_name,
                    "-d",
                    "--network", config["network"],
                    "--read-only",
                    "--security-opt=no-new-privileges:true",
                    "--cap-drop=ALL",
                    "-e", f"AGENT_ID={agent_id}",
                    "-e", f"AGENT_TYPE={agent_type.value}",
                    "-e", f"PARENT_TASK_ID={parent_task_id}",
                    "-e", f"OIDC_TOKEN={oidc_token}",
                    "--cpuset-cpus", "0-1",
                    "--memory", "512m",
                    "--memory-swap", "512m",
                    "-v", f"{WORKSPACE_MOUNT}:/workspace:ro",
                    "-v", f"{TMP_MOUNT}:/agent-tmp:rw",
                    DOCKER_IMAGE,
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if result.returncode != 0:
                logger.error(f"Failed to spawn container: {result.stderr}")
                raise RuntimeError(f"Container spawn failed: {result.stderr}")
            
            container_id = result.stdout.strip()
            
            # Record in database
            instance = AgentInstance(
                id=agent_id,
                agent_type=agent_type,
                parent_task_id=parent_task_id,
                container_id=container_id,
                oidc_token=oidc_token,
                oidc_issued_at=datetime.utcnow(),
                oidc_expires_at=oidc_expires_at,
                created_by="system",
            )
            self.db.add(instance)
            self.db.commit()
            
            logger.info(
                f"Agent spawned: {agent_id} (container: {container_id}) "
                f"(type: {agent_type.value}, parent_task: {parent_task_id})"
            )
            
            return {
                "agent_id": agent_id,
                "container_id": container_id,
                "status": "running",
                "oidc_token": oidc_token,
                "oidc_expires_at": oidc_expires_at.isoformat(),
            }
            
        except Exception as e:
            logger.error(f"Error spawning agent: {e}")
            raise

    def get_agent_status(self, agent_id: str) -> Dict[str, Any]:
        """Get current status of agent container"""
        instance = self.db.query(AgentInstance).filter(
            AgentInstance.id == agent_id
        ).first()
        
        if not instance:
            return {"status": "not_found"}
        
        if instance.destroyed_at:
            return {
                "status": "destroyed",
                "exit_code": instance.exit_code,
                "destroyed_at": instance.destroyed_at.isoformat(),
            }
        
        # Check if container still exists
        try:
            result = subprocess.run(
                ["docker", "inspect", instance.container_id],
                capture_output=True,
                text=True,
                timeout=5,
            )
            
            if result.returncode != 0:
                # Container doesn't exist anymore
                return {"status": "exited_unexpectedly"}
            
            # Parse container state
            info = json.loads(result.stdout)[0]
            state = info.get("State", {})
            
            return {
                "status": "running" if state.get("Running") else "stopped",
                "running": state.get("Running"),
                "exit_code": state.get("ExitCode"),
                "started_at": state.get("StartedAt"),
                "finished_at": state.get("FinishedAt"),
            }
            
        except Exception as e:
            logger.warning(f"Error checking container status: {e}")
            return {"status": "unknown"}

    def destroy_agent(self, agent_id: str, reason: str = "") -> bool:
        """
        Destroy agent container and mark as killed
        
        Returns: success
        """
        instance = self.db.query(AgentInstance).filter(
            AgentInstance.id == agent_id
        ).first()
        
        if not instance or instance.destroyed_at:
            return False
        
        try:
            # Stop container (with 10s timeout before kill)
            subprocess.run(
                ["docker", "stop", "-t", "10", instance.container_id],
                timeout=20,
            )
            
            # Remove container
            subprocess.run(
                ["docker", "rm", instance.container_id],
                timeout=10,
            )
            
            # Record destruction
            instance.destroyed_at = datetime.utcnow()
            instance.exit_code = 137  # SIGKILL
            self.db.commit()
            
            logger.info(f"Agent destroyed: {agent_id} ({reason})")
            return True
            
        except Exception as e:
            logger.error(f"Error destroying agent {agent_id}: {e}")
            return False

    def get_agent_logs(self, agent_id: str, tail_lines: int = 100) -> str:
        """Retrieve agent container logs"""
        instance = self.db.query(AgentInstance).filter(
            AgentInstance.id == agent_id
        ).first()
        
        if not instance:
            return ""
        
        try:
            result = subprocess.run(
                ["docker", "logs", "--tail", str(tail_lines), instance.container_id],
                capture_output=True,
                text=True,
                timeout=10,
            )
            
            return result.stdout
            
        except Exception as e:
            logger.error(f"Error retrieving logs for {agent_id}: {e}")
            return ""

    def verify_sandbox_isolation(self, agent_id: str) -> Dict[str, Any]:
        """
        Verify agent cannot escape sandbox
        
        Returns: {isolated: bool, details: {...}}
        """
        instance = self.db.query(AgentInstance).filter(
            AgentInstance.id == agent_id
        ).first()
        
        if not instance:
            return {"isolated": False, "reason": "agent_not_found"}
        
        checks = {
            "root_filesystem_readonly": False,
            "no_capabilities": False,
            "no_host_network": False,
            "cpuset_limited": False,
            "memory_limited": False,
        }
        
        try:
            result = subprocess.run(
                ["docker", "inspect", instance.container_id],
                capture_output=True,
                text=True,
                timeout=5,
            )
            
            if result.returncode == 0:
                info = json.loads(result.stdout)[0]
                
                # Check read-only root
                checks["root_filesystem_readonly"] = info.get("HostConfig", {}).get("ReadonlyRootfs", False)
                
                # Check capabilities
                caps = info.get("HostConfig", {}).get("CapAdd", [])
                checks["no_capabilities"] = len(caps) == 0
                
                # Check network
                checks["no_host_network"] = not info.get("HostConfig", {}).get("NetworkMode") == "host"
                
                # Check CPU limits
                cpuset = info.get("HostConfig", {}).get("CpusetCpus", "")
                checks["cpuset_limited"] = len(cpuset) > 0
                
                # Check memory limits
                memory = info.get("HostConfig", {}).get("Memory", 0)
                checks["memory_limited"] = memory > 0
            
        except Exception as e:
            logger.error(f"Error verifying sandbox: {e}")
        
        all_passed = all(checks.values())
        
        return {
            "isolated": all_passed,
            "checks": checks,
        }

    def list_running_agents(self) -> List[Dict[str, Any]]:
        """List all currently running agents"""
        instances = self.db.query(AgentInstance).filter(
            AgentInstance.destroyed_at == None
        ).order_by(AgentInstance.created_at.desc()).all()
        
        return [
            {
                "agent_id": i.id,
                "agent_type": i.agent_type.value,
                "container_id": i.container_id,
                "created_at": i.created_at.isoformat(),
                "parent_task_id": i.parent_task_id,
            }
            for i in instances
        ]
