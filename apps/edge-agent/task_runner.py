#!/usr/bin/env python3
# @file        apps/edge-agent/task_runner.py
# @module      edge-agent/task-runner
# @description Task execution and result reporting

import logging
import json
import psutil
from typing import Dict, Tuple
from datetime import datetime

logger = logging.getLogger(__name__)


class TaskRunner:
    """Orchestrates task execution on edge node."""

    def __init__(self):
        self.task_history = []

    async def execute_task(
        self,
        task_id: str,
        task_type: str,
        task_bundle: bytes,
        task_manifest: Dict,
    ) -> Dict:
        """
        Execute a task and return results.
        
        Task manifest includes:
        - command: command to execute
        - environment: env vars
        - timeout: max execution time
        - requires_wasm: bool
        """
        logger.info(f"Executing task {task_id} ({task_type})")
        
        start_time = datetime.utcnow()
        start_metrics = self._get_resource_metrics()
        
        try:
            # Execute task (placeholder)
            exit_code = 0
            stdout = f"Task {task_id} completed successfully"
            stderr = ""
            
            end_time = datetime.utcnow()
            end_metrics = self._get_resource_metrics()
            
            result = {
                "task_id": task_id,
                "task_type": task_type,
                "exit_code": exit_code,
                "stdout": stdout,
                "stderr": stderr,
                "start_time": start_time.isoformat(),
                "end_time": end_time.isoformat(),
                "duration_seconds": (end_time - start_time).total_seconds(),
                "resources": {
                    "cpu_percent": end_metrics["cpu_percent"],
                    "memory_mb": end_metrics["memory_mb"],
                },
            }
            
            logger.info(f"✅ Task {task_id} completed in {result['duration_seconds']:.2f}s")
            self.task_history.append(result)
            
            return result
            
        except Exception as e:
            logger.error(f"❌ Task {task_id} failed: {e}")
            
            end_time = datetime.utcnow()
            
            return {
                "task_id": task_id,
                "task_type": task_type,
                "exit_code": 1,
                "stdout": "",
                "stderr": str(e),
                "start_time": start_time.isoformat(),
                "end_time": end_time.isoformat(),
                "duration_seconds": (end_time - start_time).total_seconds(),
                "error": "execution_failed",
            }

    def _get_resource_metrics(self) -> Dict:
        """Get current resource usage metrics."""
        try:
            process = psutil.Process()
            return {
                "cpu_percent": process.cpu_percent(interval=0.1),
                "memory_mb": process.memory_info().rss / (1024 * 1024),
            }
        except Exception:
            return {"cpu_percent": 0, "memory_mb": 0}

    def verify_task_signature(self, task_bundle: bytes, signature: str) -> bool:
        """Verify task bundle signature (mutual TLS)."""
        # Placeholder: real impl would verify HMAC/RSA signature
        logger.info("Verifying task signature...")
        return True

    def get_task_history(self, limit: int = 10) -> list:
        """Get recent task history."""
        return self.task_history[-limit:]

    def get_stats(self) -> Dict:
        """Get edge node execution statistics."""
        if not self.task_history:
            return {
                "total_tasks": 0,
                "successful_tasks": 0,
                "failed_tasks": 0,
                "average_duration": 0,
            }
        
        successful = sum(1 for t in self.task_history if t.get("exit_code") == 0)
        failed = len(self.task_history) - successful
        avg_duration = (
            sum(t.get("duration_seconds", 0) for t in self.task_history)
            / len(self.task_history)
        )
        
        return {
            "total_tasks": len(self.task_history),
            "successful_tasks": successful,
            "failed_tasks": failed,
            "average_duration": avg_duration,
            "success_rate": (successful / len(self.task_history)) * 100,
        }
