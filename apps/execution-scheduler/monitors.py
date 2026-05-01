#!/usr/bin/env python3
# @file apps/execution-scheduler/monitors.py
# @module infrastructure/execution-scheduler
# @description P3-1561 Phase 2: Resource monitors for local, CI, and edge
# @governance GOV-002: All capacity monitoring feeds into scheduler decisions

import asyncio
from typing import Dict, Any, Optional
from datetime import datetime, timedelta
import os

from log import get_logger

logger = get_logger(__name__)

try:
    import psutil  # For local resource monitoring
except ModuleNotFoundError:
    psutil = None

logging.basicConfig(level=logging.INFO)

class LocalResourceMonitor:
    """Monitor local GPU/CPU resources"""
    
    def __init__(self, poll_interval_seconds: int = 30):
        self.poll_interval = poll_interval_seconds
        self.last_update = None
        self.cached_resources = {}
    
    def get_cpu_metrics(self) -> Dict[str, Any]:
        """Get CPU utilization"""
        if psutil:
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_count = psutil.cpu_count()
        else:
            cpu_percent = 50.0
            cpu_count = os.cpu_count() or 4
        
        return {
            "total_cores": cpu_count,
            "utilization_percent": cpu_percent,
            "available_percent": 100 - cpu_percent,
            "available_cores": (cpu_count * (100 - cpu_percent)) / 100
        }
    
    def get_memory_metrics(self) -> Dict[str, Any]:
        """Get memory utilization"""
        if psutil:
            mem = psutil.virtual_memory()
            total_gb = mem.total / (1024**3)
            available_gb = mem.available / (1024**3)
            utilization_percent = mem.percent
        else:
            total_gb = 16.0
            available_gb = 8.0
            utilization_percent = 50.0
        
        return {
            "total_gb": total_gb,
            "available_gb": available_gb,
            "utilization_percent": utilization_percent,
            "available_percent": 100 - utilization_percent
        }
    
    def get_gpu_metrics(self) -> Dict[str, Any]:
        """Get GPU metrics (mock - would use nvidia-ml-py in production)"""
        # In production, query nvidia-ml-py or CUDA tools
        return {
            "gpu_count": 2,
            "gpu_utilization_percent": 45,
            "gpu_available_percent": 55,
            "gpu_memory_available_gb": 24
        }
    
    def get_disk_metrics(self) -> Dict[str, Any]:
        """Get disk I/O metrics"""
        if psutil:
            disk = psutil.disk_usage('/')
            total_gb = disk.total / (1024**3)
            free_gb = disk.free / (1024**3)
            utilization_percent = disk.percent
        else:
            total_gb = 256.0
            free_gb = 128.0
            utilization_percent = 50.0
        
        return {
            "total_gb": total_gb,
            "free_gb": free_gb,
            "utilization_percent": utilization_percent,
            "available_percent": 100 - utilization_percent
        }
    
    async def poll_resources(self) -> Dict[str, Any]:
        """Poll all local resources"""
        logger.info("Polling local resources...")
        
        resources = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "cpu": self.get_cpu_metrics(),
            "memory": self.get_memory_metrics(),
            "gpu": self.get_gpu_metrics(),
            "disk": self.get_disk_metrics()
        }
        
        self.cached_resources = resources
        self.last_update = datetime.utcnow()
        
        logger.info(f"Local CPU: {resources['cpu']['available_percent']:.1f}% free")
        logger.info(f"Local GPU: {resources['gpu']['gpu_available_percent']:.1f}% free")
        
        return resources
    
    def get_cached_resources(self) -> Optional[Dict[str, Any]]:
        """Get cached resources (faster than polling)"""
        if not self.cached_resources:
            return None
        
        # Invalidate cache after 30 seconds
        if datetime.utcnow() - self.last_update > timedelta(seconds=self.poll_interval):
            return None
        
        return self.cached_resources

class CIResourceMonitor:
    """Monitor CI runner capacity (GitHub Actions)"""
    
    def __init__(self, github_token: str = ""):
        self.github_token = github_token
    
    async def get_queue_depth(self) -> int:
        """Get count of queued CI jobs"""
        # Would query GitHub Actions API
        # GET https://api.github.com/repos/{owner}/{repo}/actions/runs?status=queued
        # For now, return mock
        return 3
    
    async def get_available_runners(self) -> Dict[str, Any]:
        """Get available CI runners"""
        # Would query GitHub Actions API for runner status
        return {
            "total_runners": 10,
            "busy_runners": 7,
            "idle_runners": 3,
            "queue_depth": await self.get_queue_depth()
        }
    
    async def get_ci_metrics(self) -> Dict[str, Any]:
        """Get CI capacity metrics"""
        runners = await self.get_available_runners()
        
        logger.info(f"CI capacity: {runners['idle_runners']}/{runners['total_runners']} runners available")
        
        return {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "queue_depth": runners["queue_depth"],
            "idle_runners": runners["idle_runners"],
            "total_runners": runners["total_runners"],
            "estimated_wait_minutes": (runners["queue_depth"] / max(runners["idle_runners"], 1)) * 5
        }

class EdgeNodeRegistry:
    """Track available edge nodes for burst compute"""
    
    def __init__(self):
        self.nodes: Dict[str, Dict[str, Any]] = {}
    
    def register_node(
        self,
        node_id: str,
        hostname: str,
        cpu_cores: int,
        gpu_available: bool = False,
        available_memory_gb: int = 16
    ):
        """Register an edge node"""
        self.nodes[node_id] = {
            "hostname": hostname,
            "cpu_cores": cpu_cores,
            "gpu_available": gpu_available,
            "memory_gb": available_memory_gb,
            "registered_at": datetime.utcnow().isoformat() + "Z",
            "last_heartbeat": datetime.utcnow().isoformat() + "Z",
            "utilization_percent": 0
        }
        logger.info(f"Registered edge node: {node_id} ({hostname})")
    
    def update_node_health(self, node_id: str, utilization_percent: int):
        """Update edge node health metrics"""
        if node_id not in self.nodes:
            logger.warning(f"Node not found: {node_id}")
            return
        
        self.nodes[node_id]["last_heartbeat"] = datetime.utcnow().isoformat() + "Z"
        self.nodes[node_id]["utilization_percent"] = utilization_percent
    
    def get_available_nodes(self, min_cpu_cores: int = 2) -> list:
        """Get available edge nodes that meet requirements"""
        available = []
        for node_id, node in self.nodes.items():
            # Node healthy if heartbeat within 2 minutes
            heartbeat = datetime.fromisoformat(node["last_heartbeat"].replace("Z", "+00:00"))
            is_healthy = (datetime.utcnow(tzinfo=None) - heartbeat.replace(tzinfo=None)) < timedelta(minutes=2)
            
            if is_healthy and node["cpu_cores"] >= min_cpu_cores and node["utilization_percent"] < 80:
                available.append(node_id)
        
        return available
    
    def get_edge_metrics(self) -> Dict[str, Any]:
        """Get edge cluster metrics"""
        available = self.get_available_nodes()
        total_available_cores = sum(
            self.nodes[n]["cpu_cores"] for n in available
        )
        
        logger.info(f"Edge capacity: {len(available)} nodes available, {total_available_cores} cores total")
        
        return {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "total_nodes": len(self.nodes),
            "available_nodes": len(available),
            "total_available_cores": total_available_cores,
            "node_ids": available
        }

class ResourceMonitoringService:
    """Aggregate all resource monitors"""
    
    def __init__(self, poll_interval_seconds: int = 30):
        self.local_monitor = LocalResourceMonitor(poll_interval_seconds)
        self.ci_monitor = CIResourceMonitor()
        self.edge_registry = EdgeNodeRegistry()
        self.poll_interval = poll_interval_seconds
    
    async def get_all_metrics(self) -> Dict[str, Any]:
        """Get metrics from all sources"""
        local = await self.local_monitor.poll_resources()
        ci = await self.ci_monitor.get_ci_metrics()
        edge = self.edge_registry.get_edge_metrics()
        
        return {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "local": local,
            "ci": ci,
            "edge": edge
        }

if __name__ == "__main__":
    import asyncio
    
    async def test():
        monitor = ResourceMonitoringService()
        
        # Register some edge nodes
        monitor.edge_registry.register_node(
            "edge-01",
            "engineer-laptop-01.local",
            cpu_cores=8,
            gpu_available=True,
            available_memory_gb=16
        )
        monitor.edge_registry.update_node_health("edge-01", 40)
        
        metrics = await monitor.get_all_metrics()
        logger.info("\n=== Resource Metrics ===")
        logger.info(f"Local CPU: {metrics['local']['cpu']['available_percent']:.1f}% free")
        logger.info(f"CI Queue: {metrics['ci']['queue_depth']} jobs")
        logger.info(f"Edge Nodes: {metrics['edge']['available_nodes']}/{metrics['edge']['total_nodes']} available")
    
    asyncio.run(test())
