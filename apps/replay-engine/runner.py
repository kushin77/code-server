#!/usr/bin/env python3
# @file        apps/replay-engine/runner.py
# @module      replay-engine/runner
# @description Isolated replay execution

import logging
import asyncio
import difflib
import time
from typing import Dict, Tuple, Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class ReplayRunner:
    """Executes replay in isolated environment."""

    def __init__(self):
        self.execution_results: Dict[str, Dict] = {}

    async def execute_replay(
        self,
        run_id: str,
        network_name: str,
        command: str,
        ci_output: str,
        timeout_seconds: int = 600,
    ) -> Dict:
        """
        Execute replay command in provisioned environment.
        
        - Run command in isolated Docker network
        - Capture stdout/stderr
        - Compare with CI output
        - Detect if reproducible or architecture-dependent
        """
        logger.info(f"Executing replay: run_id={run_id}, cmd={command}")

        start_time = time.time()

        # Parse command to extract container and cmd
        # Format: docker exec <container> <command>
        parts = command.split()
        if not command.startswith("docker"):
            # Wrap command as docker exec
            container_name = f"main-{network_name}"
            full_command = f"docker exec {container_name} {command}"
        else:
            full_command = command

        try:
            local_output, exit_code = await self._run_command(full_command)
            elapsed_seconds = time.time() - start_time

            # Compare outputs
            reproducible, divergence = self._compare_outputs(ci_output, local_output)

            # Determine status
            status = self._determine_status(
                reproducible=reproducible,
                exit_code=exit_code,
                divergence=divergence,
            )

            result = {
                "run_id": run_id,
                "status": status,
                "exit_code": exit_code,
                "ci_output": ci_output[:1000],  # First 1000 chars
                "local_output": local_output[:1000],
                "divergence": divergence,
                "elapsed_seconds": elapsed_seconds,
                "reproduced_at": datetime.utcnow().isoformat(),
            }

            self.execution_results[run_id] = result
            logger.info(f"Replay complete: {run_id} → {status}")

            return result

        except Exception as e:
            logger.error(f"Replay execution failed: {e}")

            return {
                "run_id": run_id,
                "status": "error",
                "error": str(e),
                "reproduced_at": datetime.utcnow().isoformat(),
            }

    async def _run_command(
        self,
        command: str,
        timeout_seconds: int = 600,
    ) -> Tuple[str, int]:
        """
        Run command and capture output.
        
        Returns: (combined_output, exit_code)
        """
        try:
            process = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout_seconds,
            )

            combined_output = stdout.decode() + "\n" + stderr.decode()
            return combined_output, process.returncode

        except asyncio.TimeoutError:
            logger.error(f"Command timeout after {timeout_seconds}s: {command}")
            process.kill()
            return "", 124  # Timeout exit code

        except Exception as e:
            logger.error(f"Command execution failed: {e}")
            return "", 1

    def _compare_outputs(self, ci_output: str, local_output: str) -> Tuple[bool, Dict]:
        """
        Compare CI output with local replay output.
        
        Returns: (reproducible, divergence_info)
        """
        ci_lines = ci_output.split("\n")
        local_lines = local_output.split("\n")

        # Calculate similarity
        matcher = difflib.SequenceMatcher(None, ci_output, local_output)
        similarity = matcher.ratio()  # 0.0 to 1.0

        # Extract divergence (first differing lines)
        diff = list(difflib.unified_diff(ci_lines, local_lines, lineterm="", n=2))

        reproducible = similarity > 0.95  # 95% similarity threshold

        divergence = {
            "similarity": similarity,
            "divergence_lines": diff[:20],  # First 20 diff lines
            "total_diff_lines": len(diff),
        }

        return reproducible, divergence

    def _determine_status(
        self,
        reproducible: bool,
        exit_code: int,
        divergence: Dict,
    ) -> str:
        """Determine replay status."""
        if exit_code == 124:
            return "timeout"
        elif reproducible:
            return "reproduced"
        elif divergence["similarity"] > 0.8:
            return "architecture_dependent"  # Close but not exact
        else:
            return "not_reproducible"

    def get_result(self, run_id: str) -> Optional[Dict]:
        """Retrieve replay result."""
        return self.execution_results.get(run_id)

    def get_side_by_side(self, run_id: str) -> Optional[Dict]:
        """Get side-by-side comparison for IDE display."""
        result = self.get_result(run_id)
        if not result:
            return None

        ci_lines = result.get("ci_output", "").split("\n")
        local_lines = result.get("local_output", "").split("\n")

        # Create parallel view
        side_by_side = []
        max_lines = max(len(ci_lines), len(local_lines))

        for i in range(max_lines):
            ci_line = ci_lines[i] if i < len(ci_lines) else ""
            local_line = local_lines[i] if i < len(local_lines) else ""

            is_different = ci_line != local_line
            side_by_side.append({
                "line_num": i + 1,
                "ci": ci_line,
                "local": local_line,
                "different": is_different,
            })

        return {
            "run_id": run_id,
            "status": result.get("status"),
            "side_by_side": side_by_side,
            "divergence": result.get("divergence"),
        }
