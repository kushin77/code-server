#!/usr/bin/env python3
# @file        apps/edge-agent/main.py
# @module      edge-agent/daemon
# @description Edge node daemon for laptop burst compute — registers, receives tasks, executes in Wasm sandbox

import asyncio
import logging
import os
import signal
import sys
from pathlib import Path
from datetime import datetime

import aiohttp
import psutil

from .heartbeat import SchedulerHeartbeat
from .task_runner import TaskRunner
from .sandbox import WasmSandbox

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s"
)
logger = logging.getLogger(__name__)


class EdgeNodeDaemon:
    """Edge node daemon running on engineer's laptop."""

    def __init__(self, name: str, scheduler_url: str = None):
        self.name = name
        self.scheduler_url = scheduler_url or os.getenv("SCHEDULER_URL", "https://scheduler.kushnir.cloud")
        self.capabilities = self._detect_capabilities()
        self.running = False
        self.task_queue = []
        self.heartbeat = SchedulerHeartbeat(self.scheduler_url, self.name, self.capabilities)
        self.task_runner = TaskRunner()
        self.sandbox = WasmSandbox()
        self.battery_threshold = 20  # Stop at 20% battery

    def _detect_capabilities(self) -> dict:
        """Detect node capabilities (CPU, memory, GPU)."""
        cpu_count = psutil.cpu_count(logical=False)
        memory_gb = psutil.virtual_memory().total / (1024 ** 3)
        
        # Check for GPU (placeholder - real implementation would detect NVIDIA/AMD)
        gpu_count = 0
        
        return {
            "cpu": f"{cpu_count}",
            "memory": f"{int(memory_gb)}Gi",
            "gpu": f"{gpu_count}",
        }

    def _check_battery(self) -> float:
        """Get battery percentage. Returns 100 if no battery (desktop)."""
        try:
            battery = psutil.sensors_battery()
            if battery is None:
                return 100  # Desktop has no battery
            return battery.percent
        except Exception:
            return 100  # Default to 100 if unable to detect

    def _is_eligible_task(self, task_type: str) -> bool:
        """Check if task type can run on edge node."""
        # Tasks eligible for edge execution
        eligible = {"test_suite", "lint", "doc_generation", "build"}
        
        # Tasks that require resources at primary (GPU-heavy, secret access, etc.)
        ineligible = {"ai_inference", "deploy", "secret_access"}
        
        return task_type in eligible and task_type not in ineligible

    async def register(self) -> bool:
        """Register this node with scheduler."""
        try:
            registered = await self.heartbeat.register()
            if registered:
                logger.info(f"✅ Node '{self.name}' registered with scheduler")
                return True
            else:
                logger.error(f"❌ Failed to register node '{self.name}'")
                return False
        except Exception as e:
            logger.error(f"Registration error: {e}")
            return False

    async def start(self):
        """Start the edge node daemon."""
        logger.info(f"🚀 Starting edge node daemon: {self.name}")
        logger.info(f"Capabilities: {self.capabilities}")
        
        self.running = True
        
        # Register with scheduler
        if not await self.register():
            logger.error("Failed to register with scheduler")
            self.running = False
            return
        
        try:
            # Start heartbeat task
            heartbeat_task = asyncio.create_task(self._heartbeat_loop())
            
            # Start monitoring battery
            battery_task = asyncio.create_task(self._battery_monitor_loop())
            
            # Start task processor
            process_task = asyncio.create_task(self._process_tasks_loop())
            
            # Wait for tasks
            await asyncio.gather(heartbeat_task, battery_task, process_task)
            
        except asyncio.CancelledError:
            logger.info("Edge node daemon shutting down")
        except Exception as e:
            logger.error(f"Daemon error: {e}")
        finally:
            self.running = False

    async def _heartbeat_loop(self):
        """Send periodic heartbeats to scheduler."""
        while self.running:
            try:
                battery = self._check_battery()
                accepting_tasks = battery > self.battery_threshold
                
                await self.heartbeat.send_heartbeat(accepting_tasks)
                
                # Log status
                logger.debug(
                    f"Heartbeat sent | Battery: {battery}% | "
                    f"Accepting tasks: {accepting_tasks} | "
                    f"Queue: {len(self.task_queue)}"
                )
                
                # Heartbeat every 60 seconds
                await asyncio.sleep(60)
                
            except Exception as e:
                logger.error(f"Heartbeat error: {e}")
                await asyncio.sleep(60)

    async def _battery_monitor_loop(self):
        """Monitor battery and pause task acceptance when low."""
        while self.running:
            try:
                battery = self._check_battery()
                
                if battery < self.battery_threshold and len(self.task_queue) > 0:
                    logger.warning(
                        f"⚠️ Battery {battery}% < {self.battery_threshold}% threshold. "
                        f"Stopping task acceptance."
                    )
                    # Notify scheduler to not send more tasks
                    await self.heartbeat.send_heartbeat(accepting_tasks=False)
                
                await asyncio.sleep(30)  # Check every 30 seconds
                
            except Exception as e:
                logger.error(f"Battery monitor error: {e}")
                await asyncio.sleep(30)

    async def _process_tasks_loop(self):
        """Process tasks from queue."""
        while self.running:
            try:
                # Check for tasks from scheduler (placeholder - real impl would listen for tasks)
                # For now, just sleep
                await asyncio.sleep(5)
                
            except Exception as e:
                logger.error(f"Task processing error: {e}")
                await asyncio.sleep(5)

    def status(self) -> dict:
        """Get current daemon status."""
        return {
            "name": self.name,
            "running": self.running,
            "battery": self._check_battery(),
            "queue_length": len(self.task_queue),
            "capabilities": self.capabilities,
        }


async def main():
    """Entry point for edge node daemon."""
    node_name = os.getenv("NODE_NAME", "default-edge-node")
    scheduler_url = os.getenv("SCHEDULER_URL", "https://scheduler.kushnir.cloud")
    
    daemon = EdgeNodeDaemon(node_name, scheduler_url)
    
    # Handle shutdown signals
    def signal_handler(sig, frame):
        logger.info("Received shutdown signal")
        asyncio.create_task(daemon.stop())
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        await daemon.start()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
