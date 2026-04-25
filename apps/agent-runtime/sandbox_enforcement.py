"""
@governance: Sandbox resource enforcement — limit agent execution resource usage
@Purpose: Enforce CPU, memory, network, and filesystem limits for agent execution
@Author: Autonomous Infrastructure
@Date: 2026-04-25
@Related issues: #1534 (IaC Governance), #1557 (Agent Runtime)

Sandbox enforcement system for agent execution with Docker resource limits
and network/filesystem restrictions.
"""

import logging
import os
from enum import Enum
from typing import Optional, Dict, Any, List, Tuple
from dataclasses import dataclass
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class SandboxViolationType(str, Enum):
    """Types of sandbox violations"""
    CPU_LIMIT_EXCEEDED = "cpu_limit_exceeded"
    MEMORY_LIMIT_EXCEEDED = "memory_limit_exceeded"
    TIMEOUT_EXCEEDED = "timeout_exceeded"
    NETWORK_RESTRICTION_VIOLATED = "network_restriction_violated"
    FILESYSTEM_RESTRICTION_VIOLATED = "filesystem_restriction_violated"
    PROCESS_LIMIT_EXCEEDED = "process_limit_exceeded"


@dataclass
class SandboxConstraint:
    """Sandbox execution constraints"""
    max_execution_time_seconds: int
    max_memory_mb: int
    max_cpu_cores: float
    max_processes: int = 10
    allowed_network_egress: List[str] = None  # CIDR blocks or hostnames
    allowed_filesystem_paths: List[str] = None  # Allowed read/write paths
    allow_local_network: bool = False
    allow_internet_access: bool = False
    
    def __post_init__(self):
        if self.allowed_network_egress is None:
            self.allowed_network_egress = []
        if self.allowed_filesystem_paths is None:
            self.allowed_filesystem_paths = []


class DockerResourceMonitor:
    """Monitor Docker resource usage for agent containers"""
    
    def __init__(self, container_id: str):
        self.container_id = container_id
        self.start_time = datetime.utcnow()
        self.peak_memory_mb = 0
        self.peak_cpu_percent = 0
        self.violations: List[Tuple[SandboxViolationType, str]] = []
    
    async def check_memory_limit(self, current_memory_mb: int, limit_mb: int) -> bool:
        """Check if memory limit exceeded"""
        self.peak_memory_mb = max(self.peak_memory_mb, current_memory_mb)
        
        if current_memory_mb > limit_mb:
            violation_msg = (
                f"Memory limit exceeded: {current_memory_mb}MB / {limit_mb}MB "
                f"(container: {self.container_id})"
            )
            self.violations.append((SandboxViolationType.MEMORY_LIMIT_EXCEEDED, violation_msg))
            logger.error(violation_msg)
            return False
        
        # Warn at 90% threshold
        if current_memory_mb > limit_mb * 0.9:
            logger.warning(f"Memory usage at 90% capacity: {current_memory_mb}MB / {limit_mb}MB")
        
        return True
    
    async def check_cpu_limit(self, current_cpu_percent: float, limit_percent: float) -> bool:
        """Check if CPU limit exceeded"""
        self.peak_cpu_percent = max(self.peak_cpu_percent, current_cpu_percent)
        
        if current_cpu_percent > limit_percent:
            violation_msg = (
                f"CPU limit exceeded: {current_cpu_percent:.1f}% / {limit_percent:.1f}% "
                f"(container: {self.container_id})"
            )
            self.violations.append((SandboxViolationType.CPU_LIMIT_EXCEEDED, violation_msg))
            logger.error(violation_msg)
            return False
        
        # Warn at 85% threshold
        if current_cpu_percent > limit_percent * 0.85:
            logger.warning(f"CPU usage at 85% limit: {current_cpu_percent:.1f}%")
        
        return True
    
    async def check_execution_timeout(self, elapsed_seconds: int, timeout_seconds: int) -> bool:
        """Check if execution timeout exceeded"""
        if elapsed_seconds > timeout_seconds:
            violation_msg = (
                f"Execution timeout exceeded: {elapsed_seconds}s / {timeout_seconds}s "
                f"(container: {self.container_id})"
            )
            self.violations.append((SandboxViolationType.TIMEOUT_EXCEEDED, violation_msg))
            logger.error(violation_msg)
            return False
        
        # Warn at 90% of timeout
        if elapsed_seconds > timeout_seconds * 0.9:
            logger.warning(f"Execution time at 90% of timeout: {elapsed_seconds}s / {timeout_seconds}s")
        
        return True
    
    def get_violation_summary(self) -> Dict[str, Any]:
        """Get summary of violations"""
        return {
            "container_id": self.container_id,
            "violations_count": len(self.violations),
            "peak_memory_mb": self.peak_memory_mb,
            "peak_cpu_percent": self.peak_cpu_percent,
            "violations": [
                {"type": v[0].value, "message": v[1]} for v in self.violations
            ]
        }


class NetworkPolicyEnforcer:
    """Enforce network access policies for agent execution"""
    
    readonly_LOCAL_RANGES = [
        "127.0.0.0/8",      # Loopback
        "10.0.0.0/8",       # Private
        "172.16.0.0/12",    # Private
        "192.168.0.0/16",   # Private
    ]
    
    readonly_RESERVED_RANGES = [
        "0.0.0.0/8",        # This host on this network
        "169.254.0.0/16",   # Link local
        "224.0.0.0/4",      # Multicast
        "240.0.0.0/4",      # Reserved
    ]
    
    def __init__(self, constraint: SandboxConstraint):
        self.constraint = constraint
        self.attempted_connections: List[str] = []
    
    def is_ip_allowed(self, ip_address: str) -> bool:
        """Check if IP is allowed based on policy"""
        # Always allow localhost
        if ip_address in ("127.0.0.1", "localhost", "::1"):
            return True
        
        # Check if reserved range
        for reserved_range in self.readonly_RESERVED_RANGES:
            if self._ip_in_cidr(ip_address, reserved_range):
                return False
        
        # Check allowed list
        if not self.constraint.allow_internet_access:
            for private_range in self.readonly_LOCAL_RANGES:
                if self._ip_in_cidr(ip_address, private_range):
                    if not self.constraint.allow_local_network:
                        return False
            
            # All other IPs blocked if no internet access
            return False
        
        # Internet access allowed - check explicit allowlist
        if self.constraint.allowed_network_egress:
            for allowed in self.constraint.allowed_network_egress:
                if self._matches_allowed_destination(ip_address, allowed):
                    return True
            
            # If allowlist specified, other IPs blocked
            return False
        
        return True
    
    def _ip_in_cidr(self, ip: str, cidr: str) -> bool:
        """Check if IP is in CIDR range"""
        try:
            import ipaddress
            return ipaddress.ip_address(ip) in ipaddress.ip_network(cidr, strict=False)
        except Exception as e:
            logger.warning(f"IP/CIDR check failed: {e}")
            return False
    
    def _matches_allowed_destination(self, ip: str, allowed: str) -> bool:
        """Check if destination matches allowed (IP, CIDR, or hostname)"""
        # Handle CIDR
        if "/" in allowed:
            return self._ip_in_cidr(ip, allowed)
        
        # Handle hostname
        try:
            import socket
            resolved_ips = socket.gethostbyname_ex(allowed)[2]
            return ip in resolved_ips
        except Exception:
            # Hostname resolution failed, check exact match
            return ip == allowed
    
    def record_connection_attempt(self, destination: str) -> None:
        """Record attempted network connection"""
        self.attempted_connections.append(destination)


class FileSystemPolicyEnforcer:
    """Enforce filesystem access policies for agent execution"""
    
    readonly_PROTECTED_PATHS = [
        "/etc",
        "/sys",
        "/proc",
        "/dev",
        "/boot",
        "/root",
    ]
    
    def __init__(self, constraint: SandboxConstraint):
        self.constraint = constraint
        self.file_access_attempts: List[Dict[str, Any]] = []
    
    def is_path_allowed(self, path: str, access_type: str = "read") -> bool:
        """Check if file path is allowed for access"""
        # Convert to absolute path
        absolute_path = os.path.abspath(path)
        
        # Always deny protected paths
        for protected in self.readonly_PROTECTED_PATHS:
            if absolute_path.startswith(protected):
                return False
        
        # Check allowed paths
        if self.constraint.allowed_filesystem_paths:
            for allowed_path in self.constraint.allowed_filesystem_paths:
                allowed_abs = os.path.abspath(allowed_path)
                if absolute_path.startswith(allowed_abs):
                    return True
            
            # Allowlist specified but path not in it
            return False
        
        # No restrictions
        return True
    
    def record_access_attempt(
        self,
        path: str,
        access_type: str,
        allowed: bool
    ) -> None:
        """Record file access attempt"""
        self.file_access_attempts.append({
            "path": path,
            "access_type": access_type,
            "allowed": allowed,
            "timestamp": datetime.utcnow().isoformat()
        })


class SandboxOrchestrator:
    """Orchestrate sandbox enforcement across all dimensions"""
    
    def __init__(self, agent_id: str, constraint: SandboxConstraint):
        self.agent_id = agent_id
        self.constraint = constraint
        self.resource_monitor: Optional[DockerResourceMonitor] = None
        self.network_enforcer = NetworkPolicyEnforcer(constraint)
        self.filesystem_enforcer = FileSystemPolicyEnforcer(constraint)
        self.start_time = datetime.utcnow()
    
    def set_container_id(self, container_id: str) -> None:
        """Set container ID for resource monitoring"""
        self.resource_monitor = DockerResourceMonitor(container_id)
    
    async def check_all_constraints(
        self,
        current_memory_mb: Optional[int] = None,
        current_cpu_percent: Optional[float] = None
    ) -> Tuple[bool, List[str]]:
        """Check all sandbox constraints"""
        violations = []
        
        # Check execution timeout
        if self.resource_monitor:
            elapsed = (datetime.utcnow() - self.start_time).total_seconds()
            if not await self.resource_monitor.check_execution_timeout(
                int(elapsed),
                self.constraint.max_execution_time_seconds
            ):
                violations.append("Execution timeout exceeded")
        
        # Check memory
        if current_memory_mb and self.resource_monitor:
            if not await self.resource_monitor.check_memory_limit(
                current_memory_mb,
                self.constraint.max_memory_mb
            ):
                violations.append("Memory limit exceeded")
        
        # Check CPU
        if current_cpu_percent and self.resource_monitor:
            max_cpu_percent = self.constraint.max_cpu_cores * 100
            if not await self.resource_monitor.check_cpu_limit(
                current_cpu_percent,
                max_cpu_percent
            ):
                violations.append("CPU limit exceeded")
        
        return len(violations) == 0, violations
    
    def get_enforcement_report(self) -> Dict[str, Any]:
        """Get comprehensive enforcement report"""
        return {
            "agent_id": self.agent_id,
            "constraints": {
                "max_execution_time_seconds": self.constraint.max_execution_time_seconds,
                "max_memory_mb": self.constraint.max_memory_mb,
                "max_cpu_cores": self.constraint.max_cpu_cores,
                "allow_internet_access": self.constraint.allow_internet_access,
                "allow_local_network": self.constraint.allow_local_network,
            },
            "resource_monitoring": self.resource_monitor.get_violation_summary() if self.resource_monitor else None,
            "network_policy": {
                "attempted_connections": len(self.network_enforcer.attempted_connections),
                "attempts": self.network_enforcer.attempted_connections[:100]  # Last 100
            },
            "filesystem_policy": {
                "access_attempts": len(self.filesystem_enforcer.file_access_attempts),
                "attempts": self.filesystem_enforcer.file_access_attempts[:100]  # Last 100
            }
        }
