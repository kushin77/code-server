#!/usr/bin/env python3
# @file        apps/federation/reputation_sync.py
# @module      federation/reputation
# @description Engineer and agent reputation score portability across federated orgs

import logging
from typing import Dict, List, Optional
from datetime import datetime
import os

logger = logging.getLogger(__name__)


class ReputationSync:
    """Manages reputation score transfer across federated organizations."""

    def __init__(self):
        self.transfer_log: List[Dict] = []
        self.trust_weight = float(os.getenv("FEDERATION_TRUST_WEIGHT", "0.7"))

    def calculate_transferred_score(
        self,
        home_score: float,
        trust_weight: float = None,
    ) -> float:
        """
        Calculate portable reputation score.
        
        Formula: transferred_score = home_score * trust_weight
        
        Engineer reputation: partially portable (70% of score)
        Agent reputation: fully portable (100% of score)
        """
        if trust_weight is None:
            trust_weight = self.trust_weight
        
        # Clamp home_score to valid range [0-100]
        home_score = max(0.0, min(100.0, home_score))
        
        transferred = home_score * trust_weight
        transferred = round(transferred, 2)
        
        logger.debug(
            f"Score calculation: {home_score} * {trust_weight} = {transferred}"
        )
        
        return transferred

    def log_transfer(
        self,
        engineer_id: str,
        source_org: str,
        target_org: str,
        home_score: float,
        transferred_score: float,
    ):
        """Log reputation transfer event."""
        entry = {
            "engineer_id": engineer_id,
            "source_org": source_org,
            "target_org": target_org,
            "home_score": home_score,
            "transferred_score": transferred_score,
            "trust_weight": self.trust_weight,
            "timestamp": datetime.utcnow().isoformat(),
            "fraud_detected": False,
        }
        
        # Anomaly detection: flag suspicious transfers
        if self._is_anomalous_transfer(engineer_id, home_score, transferred_score):
            entry["fraud_detected"] = True
            logger.warning(f"⚠️  Anomalous transfer detected for {engineer_id}")
        
        self.transfer_log.append(entry)
        
        # In production: publish to federation.audit Kafka topic
        logger.info(f"Reputation transfer: {engineer_id} {home_score} → {transferred_score}")

    def get_transferred_score(
        self,
        engineer_id: str,
        source_org: str,
        target_org: str,
    ) -> Optional[float]:
        """
        Retrieve transferred score for engineer in target org.
        
        Looks up most recent transfer from source_org to target_org.
        """
        matching = [
            t for t in self.transfer_log
            if t["engineer_id"] == engineer_id
            and t["source_org"] == source_org
            and t["target_org"] == target_org
            and not t["fraud_detected"]
        ]
        
        if not matching:
            return None
        
        # Return most recent transfer
        return matching[-1]["transferred_score"]

    def get_transfer_history(
        self,
        engineer_id: str = None,
        org_id: str = None,
    ) -> List[Dict]:
        """
        Get reputation transfer history.
        
        Optionally filter by engineer_id or org_id.
        """
        filtered = self.transfer_log
        
        if engineer_id:
            filtered = [t for t in filtered if t["engineer_id"] == engineer_id]
        
        if org_id:
            filtered = [
                t for t in filtered
                if t["source_org"] == org_id or t["target_org"] == org_id
            ]
        
        return filtered

    def detect_anomalies(self) -> List[Dict]:
        """
        Detect anomalous reputation transfer patterns.
        
        Returns list of suspicious transfers for review.
        """
        anomalies = [t for t in self.transfer_log if t["fraud_detected"]]
        return anomalies

    def _is_anomalous_transfer(
        self,
        engineer_id: str,
        home_score: float,
        transferred_score: float,
    ) -> bool:
        """
        Detect anomalous patterns in reputation transfer.
        
        Flags:
        - Multiple transfers in same day
        - Large sudden score increase
        - Transfer to untrusted org
        """
        # Check: multiple transfers in past 24 hours
        recent_transfers = [
            t for t in self.transfer_log
            if t["engineer_id"] == engineer_id
        ]
        
        if len(recent_transfers) > 0:
            latest = recent_transfers[-1]
            last_timestamp = datetime.fromisoformat(latest["timestamp"])
            
            time_diff = (datetime.utcnow() - last_timestamp).total_seconds()
            
            # Flag if multiple transfers within 1 hour
            if time_diff < 3600:
                logger.warning(
                    f"Anomaly: multiple transfers for {engineer_id} within 1 hour"
                )
                return True
        
        # Check: sudden score jumps (e.g., from 10 to 90)
        if len(recent_transfers) > 0:
            previous = recent_transfers[-1]
            
            if abs(home_score - previous["home_score"]) > 50:
                logger.warning(
                    f"Anomaly: large score jump for {engineer_id}: "
                    f"{previous['home_score']} → {home_score}"
                )
                return True
        
        return False

    def agent_reputation_transfer(
        self,
        agent_id: str,
        source_org: str,
        target_org: str,
        task_success_rate: float,
    ) -> float:
        """
        Transfer agent reputation (fully portable, no trust weight).
        
        Agent reputation is objective and based on task outcomes,
        so transferred at 100%.
        """
        # Agent score based on success rate (0-100)
        agent_score = task_success_rate * 100
        
        # Agent reputation: fully portable (no trust weight reduction)
        transferred_score = agent_score
        
        entry = {
            "agent_id": agent_id,
            "source_org": source_org,
            "target_org": target_org,
            "task_success_rate": task_success_rate,
            "agent_score": agent_score,
            "transferred_score": transferred_score,
            "trust_weight": 1.0,  # 100% portable
            "timestamp": datetime.utcnow().isoformat(),
            "fraud_detected": False,
        }
        
        self.transfer_log.append(entry)
        logger.info(f"Agent reputation transfer: {agent_id} → {transferred_score}")
        
        return transferred_score
