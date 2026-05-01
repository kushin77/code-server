"""
@file apps/agent-runtime/execution_router.py
@description Route agent tasks to optimal execution destination
@governance GOV-002: Deterministic routing matrix with cost/latency optimization
"""

from typing import Dict, Any, Optional
from enum import Enum
from models import AgentExecutionRequest, AgentType, RiskLevel
from log import get_logger, log_event

logger = get_logger(__name__)


class ExecutionDestination(str, Enum):
    """Possible execution destinations"""
    LOCAL = "local"           # Local host (fastest, lowest cost)
    CI = "ci"                 # CI/CD pipeline (tests, builds)
    EDGE = "edge"             # Edge node (distributed agents)
    CLOUD = "cloud"           # Cloud compute (expensive, unlimited resources)


class ExecutionRouter:
    """Route agent tasks to optimal execution destination"""
    
    def __init__(self):
        self.local_available = True
        self.ci_available = True
        self.edge_nodes = {"edge-1": True, "edge-2": True}
        self.cloud_available = True
    
    def route(self, request: AgentExecutionRequest) -> ExecutionDestination:
        """Determine optimal execution destination for request"""
        
        # Data sovereignty: sensitive data must stay local
        if request.data_classification in ["confidential", "restricted"]:
            return ExecutionDestination.LOCAL
        
        # Risk-level based routing
        if request.risk_level == RiskLevel.CRITICAL:
            # Critical operations on primary infrastructure
            if self.local_available:
                return ExecutionDestination.LOCAL
            return ExecutionDestination.CLOUD
        
        # Agent-type specific routing
        if request.agent_type == AgentType.CODE_REVIEWER:
            # Code review can run on edge or CI
            if self.ci_available:
                return ExecutionDestination.CI
            if self._any_edge_available():
                return ExecutionDestination.EDGE
            return ExecutionDestination.LOCAL
        
        elif request.agent_type == AgentType.INCIDENT_RESPONDER:
            # Incident response prefers local for speed
            if self.local_available:
                return ExecutionDestination.LOCAL
            if self._any_edge_available():
                return ExecutionDestination.EDGE
            return ExecutionDestination.CLOUD
        
        elif request.agent_type == AgentType.DOC_WRITER:
            # Documentation can run anywhere (low resource)
            if self._any_edge_available():
                return ExecutionDestination.EDGE
            if self.ci_available:
                return ExecutionDestination.CI
            return ExecutionDestination.LOCAL
        
        elif request.agent_type == AgentType.TEST_GENERATOR:
            # Test generation prefers CI infrastructure
            if self.ci_available:
                return ExecutionDestination.CI
            if self._any_edge_available():
                return ExecutionDestination.EDGE
            return ExecutionDestination.LOCAL
        
        # Default: local execution
        return ExecutionDestination.LOCAL
    
    def _any_edge_available(self) -> bool:
        """Check if any edge node is available"""
        return any(available for available in self.edge_nodes.values())
    
    def get_edge_node(self) -> Optional[str]:
        """Get an available edge node"""
        for node_id, available in self.edge_nodes.items():
            if available:
                return node_id
        return None
    
    def mark_local_unavailable(self):
        """Mark local as unavailable (e.g., during maintenance)"""
        self.local_available = False
        logger.warning("Local execution marked unavailable")
    
    def mark_local_available(self):
        """Mark local as available"""
        self.local_available = True
        logger.info("Local execution marked available")
    
    def mark_edge_node_unavailable(self, node_id: str):
        """Mark edge node as unavailable"""
        if node_id in self.edge_nodes:
            self.edge_nodes[node_id] = False
            logger.warning(f"Edge node {node_id} marked unavailable")
    
    def mark_edge_node_available(self, node_id: str):
        """Mark edge node as available"""
        if node_id in self.edge_nodes:
            self.edge_nodes[node_id] = True
            logger.info(f"Edge node {node_id} marked available")
    
    def get_routing_stats(self) -> Dict[str, Any]:
        """Get current routing statistics"""
        return {
            "local_available": self.local_available,
            "ci_available": self.ci_available,
            "edge_nodes": self.edge_nodes,
            "cloud_available": self.cloud_available,
            "total_edge_available": sum(1 for v in self.edge_nodes.values() if v)
        }
