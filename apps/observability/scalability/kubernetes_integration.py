"""
Phase 25A: Kubernetes Integration Framework

Provides Kubernetes-native integration for the observability platform:
- Cluster discovery and resource management
- Pod lifecycle integration
- Service discovery and load balancing
- Namespace isolation and RBAC integration
- Events and metrics propagation

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple, Any
from enum import Enum
from datetime import datetime
import json

logger = logging.getLogger(__name__)


class PodPhase(Enum):
    """Kubernetes pod lifecycle phases."""
    PENDING = "Pending"
    RUNNING = "Running"
    SUCCEEDED = "Succeeded"
    FAILED = "Failed"
    UNKNOWN = "Unknown"


class NodeCondition(Enum):
    """Kubernetes node health conditions."""
    READY = "Ready"
    MEMORY_PRESSURE = "MemoryPressure"
    DISK_PRESSURE = "DiskPressure"
    PID_PRESSURE = "PIDPressure"
    NETWORK_UNAVAILABLE = "NetworkUnavailable"


@dataclass
class PodMetadata:
    """Pod metadata and identification."""
    name: str
    namespace: str
    uid: str
    labels: Dict[str, str] = field(default_factory=dict)
    annotations: Dict[str, str] = field(default_factory=dict)
    owner_references: List[Dict[str, str]] = field(default_factory=list)
    
    def get_label(self, key: str, default: str = "") -> str:
        """Get pod label by key."""
        return self.labels.get(key, default)
    
    def get_annotation(self, key: str, default: str = "") -> str:
        """Get pod annotation by key."""
        return self.annotations.get(key, default)
    
    def get_owner_ref(self, owner_type: str) -> Optional[Dict[str, str]]:
        """Get owner reference by type (Deployment, StatefulSet, etc)."""
        for ref in self.owner_references:
            if ref.get("kind") == owner_type:
                return ref
        return None


@dataclass
class PodStatus:
    """Pod current status and resource usage."""
    phase: PodPhase
    ready: bool
    restart_count: int
    containers_ready: int
    containers_total: int
    cpu_millicores: int = 0
    memory_bytes: int = 0
    storage_bytes: int = 0
    node_name: str = ""
    pod_ip: str = ""
    host_ip: str = ""
    started_at: Optional[datetime] = None
    
    @property
    def is_healthy(self) -> bool:
        """Check if pod is in healthy state."""
        return (
            self.phase == PodPhase.RUNNING and
            self.ready and
            self.containers_ready == self.containers_total and
            self.restart_count < 3
        )
    
    @property
    def is_degraded(self) -> bool:
        """Check if pod is in degraded state."""
        return (
            self.phase == PodPhase.RUNNING and
            (not self.ready or self.containers_ready < self.containers_total)
        )


@dataclass
class NodeMetadata:
    """Kubernetes node metadata."""
    name: str
    uid: str
    labels: Dict[str, str] = field(default_factory=dict)
    annotations: Dict[str, str] = field(default_factory=dict)
    
    def get_label(self, key: str, default: str = "") -> str:
        """Get node label by key."""
        return self.labels.get(key, default)
    
    def get_zone(self) -> str:
        """Get node zone from labels."""
        return self.get_label("topology.kubernetes.io/zone", "unknown")
    
    def get_region(self) -> str:
        """Get node region from labels."""
        return self.get_label("topology.kubernetes.io/region", "unknown")


@dataclass
class NodeStatus:
    """Node health and capacity status."""
    name: str
    ready: bool
    conditions: Dict[NodeCondition, bool] = field(default_factory=dict)
    allocatable_cpu_millicores: int = 0
    allocatable_memory_bytes: int = 0
    allocatable_pods: int = 0
    used_cpu_millicores: int = 0
    used_memory_bytes: int = 0
    used_pods: int = 0
    
    @property
    def is_healthy(self) -> bool:
        """Check if node is healthy."""
        return (
            self.ready and
            all(self.conditions.values()) and
            self.used_cpu_millicores < (self.allocatable_cpu_millicores * 0.9) and
            self.used_memory_bytes < (self.allocatable_memory_bytes * 0.9)
        )
    
    @property
    def available_cpu_millicores(self) -> int:
        """Get available CPU."""
        return self.allocatable_cpu_millicores - self.used_cpu_millicores
    
    @property
    def available_memory_bytes(self) -> int:
        """Get available memory."""
        return self.allocatable_memory_bytes - self.used_memory_bytes
    
    @property
    def available_pods(self) -> int:
        """Get available pod slots."""
        return self.allocatable_pods - self.used_pods
    
    @property
    def cpu_utilization_percent(self) -> float:
        """Get CPU utilization percentage."""
        if self.allocatable_cpu_millicores == 0:
            return 0.0
        return (self.used_cpu_millicores / self.allocatable_cpu_millicores) * 100.0
    
    @property
    def memory_utilization_percent(self) -> float:
        """Get memory utilization percentage."""
        if self.allocatable_memory_bytes == 0:
            return 0.0
        return (self.used_memory_bytes / self.allocatable_memory_bytes) * 100.0


@dataclass
class ServiceMetadata:
    """Kubernetes service metadata."""
    name: str
    namespace: str
    cluster_ip: str
    external_ips: List[str] = field(default_factory=list)
    labels: Dict[str, str] = field(default_factory=dict)
    selectors: Dict[str, str] = field(default_factory=dict)
    
    def get_label(self, key: str, default: str = "") -> str:
        """Get service label by key."""
        return self.labels.get(key, default)


@dataclass
class ServiceStatus:
    """Service health and endpoint status."""
    name: str
    endpoints_ready: int = 0
    endpoints_not_ready: int = 0
    
    @property
    def is_healthy(self) -> bool:
        """Check if service has ready endpoints."""
        return self.endpoints_ready > 0
    
    @property
    def total_endpoints(self) -> int:
        """Get total endpoint count."""
        return self.endpoints_ready + self.endpoints_not_ready


class KubernetesClusterInfo:
    """Kubernetes cluster discovery and information."""
    
    def __init__(self, cluster_name: str, version: str, api_server: str):
        """Initialize cluster information."""
        self.cluster_name = cluster_name
        self.version = version
        self.api_server = api_server
        self.discovery_time = datetime.utcnow()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "cluster_name": self.cluster_name,
            "version": self.version,
            "api_server": self.api_server,
            "discovery_time": self.discovery_time.isoformat(),
        }


class KubernetesResourceRegistry:
    """Registry for tracking Kubernetes resources."""
    
    def __init__(self):
        """Initialize resource registry."""
        self.pods: Dict[Tuple[str, str], Tuple[PodMetadata, PodStatus]] = {}
        self.nodes: Dict[str, Tuple[NodeMetadata, NodeStatus]] = {}
        self.services: Dict[Tuple[str, str], Tuple[ServiceMetadata, ServiceStatus]] = {}
        self.pod_services_map: Dict[Tuple[str, str], Set[str]] = {}
        self.last_sync = None
    
    def register_pod(
        self,
        metadata: PodMetadata,
        status: PodStatus
    ) -> None:
        """Register pod in registry."""
        key = (metadata.namespace, metadata.name)
        self.pods[key] = (metadata, status)
    
    def register_node(
        self,
        metadata: NodeMetadata,
        status: NodeStatus
    ) -> None:
        """Register node in registry."""
        self.nodes[metadata.name] = (metadata, status)
    
    def register_service(
        self,
        metadata: ServiceMetadata,
        status: ServiceStatus
    ) -> None:
        """Register service in registry."""
        key = (metadata.namespace, metadata.name)
        self.services[key] = (metadata, status)
    
    def get_pod(self, namespace: str, name: str) -> Optional[Tuple[PodMetadata, PodStatus]]:
        """Get pod by namespace and name."""
        return self.pods.get((namespace, name))
    
    def get_pods_in_namespace(self, namespace: str) -> List[Tuple[PodMetadata, PodStatus]]:
        """Get all pods in namespace."""
        return [
            (meta, status)
            for (ns, _), (meta, status) in self.pods.items()
            if ns == namespace
        ]
    
    def get_pods_for_node(self, node_name: str) -> List[Tuple[PodMetadata, PodStatus]]:
        """Get all pods scheduled on node."""
        return [
            (meta, status)
            for meta, status in self.pods.values()
            if status.node_name == node_name
        ]
    
    def get_healthy_pods(self) -> List[Tuple[PodMetadata, PodStatus]]:
        """Get all healthy pods."""
        return [
            (meta, status)
            for meta, status in self.pods.values()
            if status.is_healthy
        ]
    
    def get_degraded_pods(self) -> List[Tuple[PodMetadata, PodStatus]]:
        """Get all degraded pods."""
        return [
            (meta, status)
            for meta, status in self.pods.values()
            if status.is_degraded
        ]
    
    def get_node(self, name: str) -> Optional[Tuple[NodeMetadata, NodeStatus]]:
        """Get node by name."""
        return self.nodes.get(name)
    
    def get_healthy_nodes(self) -> List[Tuple[NodeMetadata, NodeStatus]]:
        """Get all healthy nodes."""
        return [
            (meta, status)
            for meta, status in self.nodes.values()
            if status.is_healthy
        ]
    
    def get_service(self, namespace: str, name: str) -> Optional[Tuple[ServiceMetadata, ServiceStatus]]:
        """Get service by namespace and name."""
        return self.services.get((namespace, name))
    
    def get_services_in_namespace(self, namespace: str) -> List[Tuple[ServiceMetadata, ServiceStatus]]:
        """Get all services in namespace."""
        return [
            (meta, status)
            for (ns, _), (meta, status) in self.services.items()
            if ns == namespace
        ]
    
    def get_healthy_services(self) -> List[Tuple[ServiceMetadata, ServiceStatus]]:
        """Get all services with ready endpoints."""
        return [
            (meta, status)
            for meta, status in self.services.values()
            if status.is_healthy
        ]
    
    def get_cluster_capacity(self) -> Dict[str, int]:
        """Get total cluster capacity."""
        total_cpu = 0
        total_memory = 0
        total_pods = 0
        
        for _, status in self.nodes.values():
            total_cpu += status.allocatable_cpu_millicores
            total_memory += status.allocatable_memory_bytes
            total_pods += status.allocatable_pods
        
        return {
            "cpu_millicores": total_cpu,
            "memory_bytes": total_memory,
            "pods": total_pods,
        }
    
    def get_cluster_usage(self) -> Dict[str, int]:
        """Get total cluster resource usage."""
        total_cpu = 0
        total_memory = 0
        total_pods = 0
        
        for _, status in self.nodes.values():
            total_cpu += status.used_cpu_millicores
            total_memory += status.used_memory_bytes
            total_pods += status.used_pods
        
        return {
            "cpu_millicores": total_cpu,
            "memory_bytes": total_memory,
            "pods": total_pods,
        }
    
    def clear(self) -> None:
        """Clear all registered resources."""
        self.pods.clear()
        self.nodes.clear()
        self.services.clear()
        self.pod_services_map.clear()


class KubernetesEventHandler:
    """Handler for Kubernetes resource events."""
    
    def __init__(self):
        """Initialize event handler."""
        self.callbacks: Dict[str, List[callable]] = {
            "pod.created": [],
            "pod.updated": [],
            "pod.deleted": [],
            "pod.failed": [],
            "node.ready": [],
            "node.not_ready": [],
            "service.created": [],
            "service.deleted": [],
        }
    
    def subscribe(self, event_type: str, callback: callable) -> None:
        """Subscribe to event type."""
        if event_type in self.callbacks:
            self.callbacks[event_type].append(callback)
    
    def unsubscribe(self, event_type: str, callback: callable) -> None:
        """Unsubscribe from event type."""
        if event_type in self.callbacks and callback in self.callbacks[event_type]:
            self.callbacks[event_type].remove(callback)
    
    async def emit(self, event_type: str, data: Any) -> None:
        """Emit event to all subscribers."""
        if event_type not in self.callbacks:
            logger.warning(f"Unknown event type: {event_type}")
            return
        
        for callback in self.callbacks[event_type]:
            try:
                if asyncio.iscoroutinefunction(callback):
                    await callback(data)
                else:
                    callback(data)
            except Exception as e:
                logger.error(f"Error in event callback for {event_type}: {e}")


class KubernetesResourceWatcher:
    """Watches Kubernetes resources for changes."""
    
    def __init__(self, registry: KubernetesResourceRegistry, event_handler: KubernetesEventHandler):
        """Initialize resource watcher."""
        self.registry = registry
        self.event_handler = event_handler
        self.is_watching = False
        self.watch_task = None
    
    async def start(self) -> None:
        """Start watching resources."""
        if self.is_watching:
            return
        
        self.is_watching = True
        self.watch_task = asyncio.create_task(self._watch_loop())
        logger.info("Started Kubernetes resource watcher")
    
    async def stop(self) -> None:
        """Stop watching resources."""
        if not self.is_watching:
            return
        
        self.is_watching = False
        if self.watch_task:
            await self.watch_task
        logger.info("Stopped Kubernetes resource watcher")
    
    async def _watch_loop(self) -> None:
        """Main watch loop."""
        while self.is_watching:
            try:
                # Simulate resource watch (would be replaced with real K8s client)
                await asyncio.sleep(30)
            except Exception as e:
                logger.error(f"Error in resource watcher: {e}")
                await asyncio.sleep(60)


__all__ = [
    "PodPhase",
    "NodeCondition",
    "PodMetadata",
    "PodStatus",
    "NodeMetadata",
    "NodeStatus",
    "ServiceMetadata",
    "ServiceStatus",
    "KubernetesClusterInfo",
    "KubernetesResourceRegistry",
    "KubernetesEventHandler",
    "KubernetesResourceWatcher",
]
