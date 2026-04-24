#!/usr/bin/env python3
# @file        apps/extension-runtime/isolation.py
# @module      extension-runtime/isolation
# @description Extension isolation enforcement (network + capabilities)

import logging
import subprocess
from typing import Dict, List, Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class IsolationPolicy:
    """Isolation policy for extension."""

    extension_id: str
    allowed_capabilities: List[str]
    allowed_networks: List[str]  # service names it can reach
    cpu_limit: str = "0.5"  # CPU cores
    memory_limit: str = "512m"  # Memory
    can_read_workspace: bool = False
    can_write_workspace: bool = False


class ExtensionIsolationManager:
    """Manages extension network and capability isolation."""

    def __init__(self):
        self.isolation_policies: Dict[str, IsolationPolicy] = {}
        self.extension_containers: Dict[str, str] = {}  # ext_id -> container_id

    def create_isolation_policy(
        self,
        extension_id: str,
        manifest: Dict,
    ) -> IsolationPolicy:
        """Create isolation policy from extension manifest."""
        capabilities = manifest.get("capabilities", {})
        permissions = manifest.get("permissions", {})

        # Determine allowed networks based on permissions
        allowed_networks = []
        if "event_bus" in permissions:
            allowed_networks.append("kafka")
        if "memory" in permissions:
            allowed_networks.append("memory-engine")

        # Create policy
        policy = IsolationPolicy(
            extension_id=extension_id,
            allowed_capabilities=list(capabilities.keys()),
            allowed_networks=allowed_networks,
            can_read_workspace="read_files" in capabilities,
            can_write_workspace="write_files" in capabilities,
        )

        self.isolation_policies[extension_id] = policy
        logger.info(f"Isolation policy created for {extension_id}: {policy}")
        return policy

    async def create_isolated_container(
        self,
        extension_id: str,
        image: str,
        policy: IsolationPolicy,
    ) -> Optional[str]:
        """Create Docker container with isolation policy."""
        try:
            logger.info(f"Creating isolated container for {extension_id}")

            # Network isolation: extensions use separate network
            network_name = f"extension-net-{extension_id}"
            self._create_network(network_name)

            # Build docker run command
            cmd = [
                "docker",
                "run",
                "-d",
                "--name",
                f"extension-{extension_id}",
                "--network",
                network_name,
                "--cpus",
                policy.cpu_limit,
                "--memory",
                policy.memory_limit,
            ]

            # Mount workspace if allowed (read-only by default)
            if policy.can_read_workspace:
                cmd.extend(["-v", "/workspace:/workspace:ro"])

            if policy.can_write_workspace:
                cmd.extend(["-v", "/workspace:/workspace:rw"])

            # Add capabilities restrictions
            cmd.extend([
                "--cap-drop",
                "ALL",
                "--cap-add",
                "NET_BIND_SERVICE",
            ])

            # Security options
            cmd.extend([
                "--security-opt",
                "no-new-privileges:true",
                image,
            ])

            # Run container
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                logger.error(f"Container creation failed: {result.stderr}")
                return None

            container_id = result.stdout.strip()
            self.extension_containers[extension_id] = container_id

            logger.info(f"✅ Isolated container created: {container_id}")
            return container_id

        except Exception as e:
            logger.error(f"Failed to create isolated container: {e}")
            return None

    async def cleanup_container(self, extension_id: str) -> bool:
        """Stop and remove extension container."""
        try:
            container_id = self.extension_containers.get(extension_id)
            if not container_id:
                logger.warning(f"No container found for {extension_id}")
                return False

            # Stop container
            subprocess.run(["docker", "stop", container_id], check=True)

            # Remove container
            subprocess.run(["docker", "rm", container_id], check=True)

            # Remove network
            network_name = f"extension-net-{extension_id}"
            subprocess.run(["docker", "network", "rm", network_name], check=False)

            del self.extension_containers[extension_id]
            logger.info(f"✅ Cleaned up container for {extension_id}")
            return True

        except Exception as e:
            logger.error(f"Cleanup failed: {e}")
            return False

    def _create_network(self, network_name: str):
        """Create Docker network for extension isolation."""
        try:
            subprocess.run(
                ["docker", "network", "create", network_name],
                check=True,
                capture_output=True,
            )
            logger.debug(f"Network created: {network_name}")
        except subprocess.CalledProcessError:
            # Network may already exist
            logger.debug(f"Network may already exist: {network_name}")

    def enforce_capability_restrictions(
        self,
        extension_id: str,
        requested_capability: str,
    ) -> bool:
        """Enforce capability restrictions via OPA."""
        policy = self.isolation_policies.get(extension_id)
        if not policy:
            logger.warning(f"No policy found for {extension_id}")
            return False

        if requested_capability not in policy.allowed_capabilities:
            logger.warning(
                f"Capability not allowed for {extension_id}: {requested_capability}"
            )
            return False

        logger.debug(f"Capability allowed: {extension_id}.{requested_capability}")
        return True
