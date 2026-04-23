#!/usr/bin/env python3
# @file        apps/replay-engine/capture.py
# @module      replay-engine/capture
# @description CI failure capture and archival

import logging
import json
import tarfile
import io
import os
from typing import Dict, List, Optional
from datetime import datetime
import asyncio

logger = logging.getLogger(__name__)


class FailureCapture:
    """Captures CI failure artifacts for replay."""

    def __init__(self, nas_mount_path: str = "/mnt/nas/replay-archives"):
        self.nas_mount_path = nas_mount_path
        os.makedirs(nas_mount_path, exist_ok=True)

    async def capture_from_github_actions(
        self,
        run_id: str,
        job_name: str,
        failure_details: Dict,
    ) -> Dict:
        """
        Capture CI failure from GitHub Actions.
        
        Called from capture-failure.yml workflow hook on workflow_run event.
        """
        logger.info(f"Capturing failure from GitHub Actions: run_id={run_id}")

        capture_data = {
            "run_id": run_id,
            "job_name": job_name,
            "captured_at": datetime.utcnow().isoformat(),
            "failure_details": failure_details,
            "metadata": {
                "git_commit": failure_details.get("git_commit"),
                "branch": failure_details.get("branch"),
                "pr_number": failure_details.get("pr_number"),
            },
            "environment": self._extract_environment(failure_details),
            "failure_signature": self._compute_failure_signature(failure_details),
        }

        # Create archive
        archive_path = await self._create_archive(run_id, capture_data)

        logger.info(f"Capture complete: {archive_path}")

        return {
            "archive_path": archive_path,
            "run_id": run_id,
            "size_mb": os.path.getsize(archive_path) / (1024 * 1024),
        }

    def _extract_environment(self, failure_details: Dict) -> Dict:
        """Extract and normalize environment details."""
        return {
            "env_yaml": failure_details.get("env_yaml", ""),
            "images": failure_details.get("images", {}),
            "tool_versions": {
                "docker": failure_details.get("docker_version", "unknown"),
                "terraform": failure_details.get("terraform_version", "unknown"),
                "node": failure_details.get("node_version", "unknown"),
                "python": failure_details.get("python_version", "unknown"),
            },
            "random_seeds": failure_details.get("random_seeds", {}),
        }

    def _compute_failure_signature(self, failure_details: Dict) -> str:
        """Compute deterministic failure signature for deduplication."""
        # Signature = hash(command + error_pattern)
        command = failure_details.get("command", "")
        error_output = failure_details.get("stderr", "")[:200]  # First 200 chars

        # Extract error line
        error_lines = error_output.split("\n")
        error_pattern = next(
            (line for line in error_lines if "error" in line.lower()),
            error_lines[0] if error_lines else "",
        )

        signature = f"{command}::{error_pattern}"
        return signature.replace(" ", "_")[:100]

    async def _create_archive(self, run_id: str, capture_data: Dict) -> str:
        """Create tar.gz archive with failure data."""
        archive_name = f"replay-{run_id}.tar.gz"
        archive_path = os.path.join(self.nas_mount_path, archive_name)

        try:
            with tarfile.open(archive_path, "w:gz") as tar:
                # Add capture metadata JSON
                metadata_json = json.dumps(capture_data, indent=2).encode()
                tarinfo = tarfile.TarInfo(name="capture-metadata.json")
                tarinfo.size = len(metadata_json)
                tar.addfile(tarinfo, io.BytesIO(metadata_json))

                # Add failure output
                failure_output = capture_data["failure_details"].get("full_output", "")
                output_data = failure_output.encode()
                tarinfo = tarfile.TarInfo(name="failure-output.txt")
                tarinfo.size = len(output_data)
                tar.addfile(tarinfo, io.BytesIO(output_data))

                # Add env.yaml
                env_yaml = capture_data["environment"].get("env_yaml", "")
                env_data = env_yaml.encode()
                tarinfo = tarfile.TarInfo(name="env.yaml")
                tarinfo.size = len(env_data)
                tar.addfile(tarinfo, io.BytesIO(env_data))

            logger.info(f"Archive created: {archive_path}")
            return archive_path

        except Exception as e:
            logger.error(f"Failed to create archive: {e}")
            raise

    async def publish_to_kafka(self, archive_path: str, run_id: str) -> bool:
        """Publish replay artifact event to Kafka."""
        # Placeholder: in production, would publish to ci.failure Kafka topic
        # with format: {"run_id": "...", "archive_url": "s3://...", "timestamp": "..."}

        event = {
            "run_id": run_id,
            "archive_path": archive_path,
            "event_type": "ci_failure_captured",
            "timestamp": datetime.utcnow().isoformat(),
        }

        logger.info(f"Publishing to Kafka: {json.dumps(event)}")

        return True

    async def notify_ide(self, run_id: str, archive_path: str) -> bool:
        """Notify IDE that replay is available."""
        # Placeholder: WebSocket or HTTP notification to VS Code extension
        notification = {
            "message": f"CI failed — replay available locally",
            "run_id": run_id,
            "command": f"elevatediq replay {run_id}",
        }

        logger.info(f"Notifying IDE: {json.dumps(notification)}")

        return True
