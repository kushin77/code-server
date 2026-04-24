#!/usr/bin/env python3
# @file        apps/paperclip-control-plane/heartbeat.py
# @module      paperclip/control-plane
# @description Agent heartbeat monitor - detect unresponsive agents, trigger kill
# @owner       paperclip/control-plane
# @status      production-ready
#
# Monitor agent liveliness: if heartbeat missed 2x (60s gap), kill agent + incident

import asyncio
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timedelta
from dataclasses import dataclass

from sqlalchemy.orm import Session
from sqlalchemy import and_

from .models import AgentHeartbeat, HeartbeatStatus

logger = logging.getLogger(__name__)


@dataclass
class HeartbeatReport:
    """Agent heartbeat check-in"""
    agent_id: str
    task_id: Optional[str] = None
    last_action: Optional[str] = None
    status: str = "healthy"
    elapsed_seconds: float = 0.0
    eta_seconds: Optional[float] = None
    memory_mb: float = 0.0
    cpu_percent: float = 0.0


class HeartbeatMonitor:
    """Monitor agent health via periodic heartbeats"""

    HEARTBEAT_INTERVAL_SECONDS = 30
    HEARTBEAT_TIMEOUT_SECONDS = 60  # 2 missed heartbeats = unresponsive
    
    def __init__(self, db_session: Session):
        self.db = db_session

    def record_heartbeat(self, report: HeartbeatReport) -> bool:
        """
        Record incoming heartbeat from agent
        
        Returns: success
        """
        heartbeat = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.agent_id == report.agent_id
        ).first()

        now = datetime.utcnow()

        if not heartbeat:
            # New agent
            heartbeat = AgentHeartbeat(
                agent_id=report.agent_id,
                task_id=report.task_id,
                last_action=report.last_action,
                status=HeartbeatStatus.HEALTHY,
                elapsed_seconds=report.elapsed_seconds,
                eta_seconds=report.eta_seconds,
                memory_mb=report.memory_mb,
                cpu_percent=report.cpu_percent,
                last_heartbeat_at=now,
                consecutive_healthy=1,
            )
            self.db.add(heartbeat)
        else:
            # Update existing
            heartbeat.task_id = report.task_id
            heartbeat.last_action = report.last_action
            heartbeat.elapsed_seconds = report.elapsed_seconds
            heartbeat.eta_seconds = report.eta_seconds
            heartbeat.memory_mb = report.memory_mb
            heartbeat.cpu_percent = report.cpu_percent
            heartbeat.last_heartbeat_at = now
            
            # If recovering from unresponsive
            if heartbeat.status == HeartbeatStatus.UNRESPONSIVE:
                heartbeat.status = HeartbeatStatus.HEALTHY
                heartbeat.unresponsive_since = None
                logger.info(f"Agent {report.agent_id} recovered from unresponsive state")
            
            heartbeat.missed_heartbeats = 0
            heartbeat.consecutive_healthy += 1

        self.db.commit()
        return True

    def check_timeouts(self) -> Dict[str, Any]:
        """
        Check for agents with missing heartbeats
        
        Returns: summary of actions taken
        """
        now = datetime.utcnow()
        timeout_threshold = now - timedelta(seconds=self.HEARTBEAT_TIMEOUT_SECONDS)
        
        # Find agents that haven't checked in
        stale_agents = self.db.query(AgentHeartbeat).filter(
            and_(
                AgentHeartbeat.last_heartbeat_at < timeout_threshold,
                AgentHeartbeat.status != HeartbeatStatus.KILLED,
            )
        ).all()

        killed_count = 0
        degraded_count = 0
        
        for hb in stale_agents:
            hb.missed_heartbeats += 1
            
            if hb.missed_heartbeats >= 2:
                # Agent unresponsive - mark for killing
                hb.status = HeartbeatStatus.UNRESPONSIVE
                hb.unresponsive_since = now
                killed_count += 1
                
                logger.error(
                    f"Agent {hb.agent_id} unresponsive for {hb.missed_heartbeats} intervals - "
                    f"marking for kill (task: {hb.task_id})"
                )
            else:
                # Degraded - warning
                hb.status = HeartbeatStatus.DEGRADED
                degraded_count += 1
                logger.warning(
                    f"Agent {hb.agent_id} missed {hb.missed_heartbeats} heartbeat(s)"
                )

        if killed_count + degraded_count > 0:
            self.db.commit()

        return {
            "degraded_agents": degraded_count,
            "unresponsive_agents": killed_count,
            "total_checked": len(stale_agents),
        }

    async def get_agent_status(self, agent_id: str) -> Optional[Dict[str, Any]]:
        """Get current status of a single agent"""
        hb = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.agent_id == agent_id
        ).first()

        if not hb:
            return None

        return {
            "agent_id": hb.agent_id,
            "status": hb.status.value,
            "task_id": hb.task_id,
            "last_action": hb.last_action,
            "last_heartbeat_at": hb.last_heartbeat_at.isoformat(),
            "elapsed_seconds": hb.elapsed_seconds,
            "eta_seconds": hb.eta_seconds,
            "memory_mb": hb.memory_mb,
            "cpu_percent": hb.cpu_percent,
            "consecutive_healthy": hb.consecutive_healthy,
            "missed_heartbeats": hb.missed_heartbeats,
            "unresponsive_since": hb.unresponsive_since.isoformat() if hb.unresponsive_since else None,
            "killed_at": hb.killed_at.isoformat() if hb.killed_at else None,
        }

    async def get_all_agents_status(self) -> Dict[str, Any]:
        """Get status of all active agents"""
        agents = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.status != HeartbeatStatus.KILLED
        ).order_by(AgentHeartbeat.last_heartbeat_at.desc()).all()

        by_status = {
            "healthy": [],
            "degraded": [],
            "unresponsive": [],
        }

        for hb in agents:
            agent_info = {
                "agent_id": hb.agent_id,
                "task_id": hb.task_id,
                "last_heartbeat_at": hb.last_heartbeat_at.isoformat(),
                "elapsed_seconds": hb.elapsed_seconds,
            }
            
            status = hb.status.value
            if status in by_status:
                by_status[status].append(agent_info)

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "agents": by_status,
            "total_healthy": len(by_status["healthy"]),
            "total_degraded": len(by_status["degraded"]),
            "total_unresponsive": len(by_status["unresponsive"]),
        }

    async def run_monitor_loop(self, check_interval_seconds: int = 15):
        """
        Background task: periodically check heartbeats for timeouts
        
        Run as: asyncio.create_task(heartbeat_monitor.run_monitor_loop())
        """
        logger.info("Starting heartbeat monitor loop")
        
        while True:
            try:
                summary = self.check_timeouts()
                
                if summary["degraded_agents"] + summary["unresponsive_agents"] > 0:
                    logger.info(
                        f"Heartbeat check: degraded={summary['degraded_agents']}, "
                        f"unresponsive={summary['unresponsive_agents']}"
                    )
                
                await asyncio.sleep(check_interval_seconds)
                
            except Exception as e:
                logger.error(f"Error in heartbeat monitor loop: {e}", exc_info=True)
                await asyncio.sleep(check_interval_seconds)

    def mark_agent_killed(self, agent_id: str) -> bool:
        """Mark agent as killed (after container termination)"""
        hb = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.agent_id == agent_id
        ).first()

        if hb:
            hb.status = HeartbeatStatus.KILLED
            hb.killed_at = datetime.utcnow()
            self.db.commit()
            logger.info(f"Agent {agent_id} marked as killed")
            return True

        return False

    def get_heartbeat_stats(self) -> Dict[str, Any]:
        """Get heartbeat statistics"""
        healthy = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.status == HeartbeatStatus.HEALTHY
        ).count()
        
        degraded = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.status == HeartbeatStatus.DEGRADED
        ).count()
        
        unresponsive = self.db.query(AgentHeartbeat).filter(
            AgentHeartbeat.status == HeartbeatStatus.UNRESPONSIVE
        ).count()
        
        return {
            "healthy_agents": healthy,
            "degraded_agents": degraded,
            "unresponsive_agents": unresponsive,
            "total_monitored": healthy + degraded + unresponsive,
        }
