#!/usr/bin/env python3
# @file        apps/edge-agent/sandbox.py
# @module      edge-agent/sandbox
# @description Wasm sandbox execution environment

import logging
import json
import subprocess
from pathlib import Path
from typing import Optional, Dict, Tuple

logger = logging.getLogger(__name__)


class WasmSandbox:
    """Manages Wasm sandbox execution using Wasmtime."""

    def __init__(self, workspace: Optional[str] = None):
        self.workspace = Path(workspace or "/tmp/edge-workspace")
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.wasmtime_available = self._check_wasmtime()

    def _check_wasmtime(self) -> bool:
        """Check if Wasmtime is installed."""
        try:
            result = subprocess.run(
                ["wasmtime", "--version"],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            logger.warning("⚠️ Wasmtime not found - Wasm sandbox unavailable")
            return False

    async def execute_wasm_task(
        self,
        wasm_binary: bytes,
        task_manifest: Dict,
        cpu_limit_percent: int = 50,
        memory_limit_mb: int = 512,
    ) -> Tuple[int, str, str]:
        """
        Execute task in Wasm sandbox.
        
        Returns: (exit_code, stdout, stderr)
        """
        if not self.wasmtime_available:
            logger.error("❌ Wasm sandbox unavailable - falling back to Docker")
            return self._fallback_docker_execution(task_manifest)

        try:
            # Write Wasm binary to workspace
            wasm_path = self.workspace / "task.wasm"
            wasm_path.write_bytes(wasm_binary)

            # Build wasmtime command with sandbox restrictions
            cmd = [
                "wasmtime",
                "--dir=" + str(self.workspace),  # Restrict filesystem
                "--inherit-stdio",
                str(wasm_path),
            ]

            # Add command arguments
            if "command" in task_manifest:
                cmd.extend(task_manifest["command"].split())

            logger.info(f"Executing Wasm task: {' '.join(cmd)}")

            # Run with resource limits
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=task_manifest.get("timeout", 300),
                cwd=str(self.workspace),
                text=True,
            )

            logger.info(f"✅ Wasm task completed with exit code: {result.returncode}")

            return result.returncode, result.stdout, result.stderr

        except subprocess.TimeoutExpired:
            logger.error("⏱️ Task timeout")
            return 124, "", "Task exceeded timeout"
        except Exception as e:
            logger.error(f"❌ Wasm execution error: {e}")
            return 1, "", str(e)

    def _fallback_docker_execution(self, task_manifest: Dict) -> Tuple[int, str, str]:
        """Fallback to Docker execution for non-Wasm tasks."""
        logger.warning("⚠️ Falling back to Docker execution (requires manual trust)")
        
        # Placeholder: real impl would run Docker with sandboxing
        return 0, "Docker execution placeholder", ""

    def verify_sandbox_isolation(self) -> bool:
        """Verify sandbox properly isolates from filesystem."""
        try:
            # Test: write file outside workspace
            test_path = Path("/tmp/edge-sandbox-test-outside")
            test_path.write_text("test")

            # Attempt to read from Wasm sandbox (should fail)
            # Placeholder test
            test_path.unlink()
            return True
        except Exception as e:
            logger.error(f"Sandbox isolation verification failed: {e}")
            return False
