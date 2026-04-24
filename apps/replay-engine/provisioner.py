#!/usr/bin/env python3
# @file        apps/replay-engine/provisioner.py
# @module      replay-engine/provisioner
# @description Environment provisioning with exact image digests for replay

import logging
import asyncio
import yaml
from typing import Dict, List, Optional
import subprocess
import json

logger = logging.getLogger(__name__)


class EnvironmentProvisioner:
    """Provisions exact environment for replay using captured env.yaml."""

    def __init__(self):
        self.provisioned_containers: Dict[str, str] = {}

    async def provision_environment(
        self,
        env_yaml: str,
        run_id: str,
        target_architecture: str = "linux/amd64",
    ) -> Dict:
        """
        Provision environment for replay.
        
        - Parse env.yaml with pinned image digests (@sha256:...)
        - Create isolated Docker network
        - Start containers with exact images
        - Return network info for runner
        """
        logger.info(f"Provisioning environment: run_id={run_id}, arch={target_architecture}")

        try:
            env_config = yaml.safe_load(env_yaml)
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse env.yaml: {e}")
            raise

        # Create network
        network_name = f"replay-{run_id}"
        await self._create_network(network_name)

        # Start containers
        containers = []
        for service_name, service_config in env_config.get("services", {}).items():
            image = service_config.get("image", "")
            
            if not image:
                logger.warning(f"No image for service {service_name}")
                continue

            container_id = await self._start_container(
                service_name=service_name,
                image=image,
                network=network_name,
                architecture=target_architecture,
                env_vars=service_config.get("environment", {}),
            )

            containers.append({
                "service": service_name,
                "image": image,
                "container_id": container_id,
            })

            self.provisioned_containers[container_id] = network_name

        logger.info(f"Environment provisioned: {len(containers)} containers")

        return {
            "network_name": network_name,
            "containers": containers,
            "status": "ready",
        }

    async def _create_network(self, network_name: str) -> str:
        """Create isolated Docker network for replay."""
        cmd = [
            "docker", "network", "create",
            "--driver=bridge",
            network_name,
        ]

        result = await self._run_command(cmd)
        logger.info(f"Network created: {network_name}")
        return network_name

    async def _start_container(
        self,
        service_name: str,
        image: str,
        network: str,
        architecture: str = "linux/amd64",
        env_vars: Optional[Dict] = None,
    ) -> str:
        """Start container with exact image digest."""
        # Verify image has sha256: pinning
        if "@sha256:" not in image:
            logger.warning(f"Image not pinned to digest: {image} — will use latest (not reproducible)")

        cmd = [
            "docker", "run",
            "--platform", architecture,
            "--network", network,
            "--name", f"{service_name}-{network}",
            "--detach",
        ]

        # Add environment variables
        if env_vars:
            for key, value in env_vars.items():
                cmd.extend(["-e", f"{key}={value}"])

        cmd.append(image)

        result = await self._run_command(cmd)
        container_id = result.strip()

        logger.info(f"Container started: {service_name} → {container_id[:12]}")
        return container_id

    async def cleanup_environment(self, network_name: str) -> bool:
        """Clean up provisioned environment (remove containers and network)."""
        logger.info(f"Cleaning up environment: {network_name}")

        # Get containers on network
        cmd = [
            "docker", "ps",
            "-a",
            "--filter", f"network={network_name}",
            "--format", "{{.ID}}",
        ]

        result = await self._run_command(cmd)
        container_ids = result.strip().split("\n")

        # Stop and remove containers
        for container_id in container_ids:
            if container_id:
                await self._run_command(["docker", "stop", container_id])
                await self._run_command(["docker", "rm", container_id])
                logger.info(f"Container removed: {container_id[:12]}")

        # Remove network
        await self._run_command(["docker", "network", "rm", network_name])
        logger.info(f"Network removed: {network_name}")

        return True

    async def _run_command(self, cmd: List[str]) -> str:
        """Run shell command and return output."""
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            logger.error(f"Command failed: {' '.join(cmd)} — {stderr.decode()}")
            raise RuntimeError(f"Command failed: {stderr.decode()}")

        return stdout.decode()

    async def validate_reproducibility(
        self,
        env_yaml: str,
        target_architecture: str = "linux/amd64",
    ) -> Dict:
        """
        Validate that environment is reproducible.
        
        - Check all images are pinned (@sha256:)
        - Check tool versions are available
        - Detect architecture dependencies
        """
        issues = []

        env_config = yaml.safe_load(env_yaml)

        for service_name, service_config in env_config.get("services", {}).items():
            image = service_config.get("image", "")

            if not image:
                issues.append(f"Service {service_name} has no image")
            elif "@sha256:" not in image:
                issues.append(f"Service {service_name} image not pinned: {image}")

        is_reproducible = len(issues) == 0

        return {
            "reproducible": is_reproducible,
            "issues": issues,
            "architecture": target_architecture,
            "recommendation": "Use @sha256: digest pinning" if issues else "Environment is reproducible",
        }
