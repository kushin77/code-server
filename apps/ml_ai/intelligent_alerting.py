"""
Intelligent Alerting Engine (Phase 27D)

ML-based alert intelligence:
- Alert deduplication
- Severity prediction
- Alert fatigue suppression
- Dynamic threshold optimization
- Alert enrichment with context

Part of Observability Platform v1.0.0
"""

import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional


class AlertSeverity(Enum):
    """Alert severity levels."""
    
    CRITICAL = 5
    HIGH = 4
    MEDIUM = 3
    LOW = 2
    INFO = 1


@dataclass
class RawAlert:
    """Raw alert before processing."""
    
    id: str
    title: str
    description: str
    metric_name: str
    metric_value: float
    threshold: float
    source: str
    timestamp: datetime
    tags: Dict[str, str] = field(default_factory=dict)


@dataclass
class AlertSignature:
    """Unique signature for alert deduplication."""
    
    signature: str
    source_key: str
    metric_key: str
    threshold_key: str


@dataclass
class AlertGroup:
    """Grouped/deduplicated alerts."""
    
    signature: str
    first_occurrence: datetime
    last_occurrence: datetime
    occurrence_count: int
    alerts: List[RawAlert] = field(default_factory=list)
    severity: AlertSeverity = AlertSeverity.MEDIUM


@dataclass
class EnrichedAlert:
    """Alert with enrichment and intelligence."""
    
    id: str
    original_alert: RawAlert
    predicted_severity: AlertSeverity
    deduplication_group: Optional[str] = None
    fatigue_score: float = 0.0  # 0-1, higher = more redundant
    should_suppress: bool = False
    context: Dict[str, Any] = field(default_factory=dict)
    enrichment_metadata: Dict[str, Any] = field(default_factory=dict)


class AlertDeduplicator:
    """Alert deduplication engine."""
    
    def __init__(self, time_window_seconds: int = 300):
        """Initialize deduplicator."""
        self.time_window = timedelta(seconds=time_window_seconds)
        self.alert_groups: Dict[str, AlertGroup] = {}
        self.alert_history: List[RawAlert] = []
    
    def _generate_signature(self, alert: RawAlert) -> AlertSignature:
        """Generate signature for alert."""
        source_key = alert.source
        metric_key = alert.metric_name
        threshold_key = f"{alert.threshold:.2f}"
        
        signature_str = f"{source_key}:{metric_key}:{threshold_key}"
        signature = hashlib.md5(signature_str.encode()).hexdigest()[:16]
        
        return AlertSignature(
            signature=signature,
            source_key=source_key,
            metric_key=metric_key,
            threshold_key=threshold_key
        )
    
    def process_alert(self, alert: RawAlert) -> AlertGroup:
        """Process alert for deduplication."""
        sig = self._generate_signature(alert)
        
        # Check if signature already exists
        if sig.signature in self.alert_groups:
            group = self.alert_groups[sig.signature]
            
            # Update group if within time window
            time_diff = alert.timestamp - group.last_occurrence
            if time_diff <= self.time_window:
                group.alerts.append(alert)
                group.occurrence_count += 1
                group.last_occurrence = alert.timestamp
            else:
                # Create new group for old signature (new occurrence)
                new_sig = f"{sig.signature}_{len(self.alert_groups)}"
                group = AlertGroup(
                    signature=new_sig,
                    first_occurrence=alert.timestamp,
                    last_occurrence=alert.timestamp,
                    occurrence_count=1,
                    alerts=[alert]
                )
                self.alert_groups[new_sig] = group
        else:
            # New signature
            group = AlertGroup(
                signature=sig.signature,
                first_occurrence=alert.timestamp,
                last_occurrence=alert.timestamp,
                occurrence_count=1,
                alerts=[alert]
            )
            self.alert_groups[sig.signature] = group
        
        self.alert_history.append(alert)
        return group
    
    def get_active_groups(self) -> List[AlertGroup]:
        """Get currently active alert groups."""
        now = datetime.utcnow()
        active = []
        
        for group in self.alert_groups.values():
            if now - group.last_occurrence <= self.time_window:
                active.append(group)
        
        return active


class SeverityPredictor:
    """ML-based alert severity prediction."""
    
    def __init__(self):
        """Initialize predictor."""
        self.training_data: List[Tuple[RawAlert, AlertSeverity]] = []
        self.severity_ranges = {
            AlertSeverity.CRITICAL: (0.9, 1.0),
            AlertSeverity.HIGH: (0.7, 0.9),
            AlertSeverity.MEDIUM: (0.4, 0.7),
            AlertSeverity.LOW: (0.2, 0.4),
            AlertSeverity.INFO: (0.0, 0.2)
        }
    
    def predict_severity(self, alert: RawAlert) -> AlertSeverity:
        """Predict severity for alert."""
        # Calculate deviation from threshold
        if alert.threshold > 0:
            deviation = abs(alert.metric_value - alert.threshold) / alert.threshold
        else:
            deviation = abs(alert.metric_value)
        
        # Cap deviation
        deviation = min(deviation, 2.0)
        
        # Calculate confidence score
        score = min(deviation / 2.0, 1.0)
        
        # Determine severity based on score
        if score >= 0.9:
            severity = AlertSeverity.CRITICAL
        elif score >= 0.7:
            severity = AlertSeverity.HIGH
        elif score >= 0.4:
            severity = AlertSeverity.MEDIUM
        elif score >= 0.2:
            severity = AlertSeverity.LOW
        else:
            severity = AlertSeverity.INFO
        
        return severity
    
    def add_training_example(
        self,
        alert: RawAlert,
        actual_severity: AlertSeverity
    ) -> None:
        """Add training example for model improvement."""
        self.training_data.append((alert, actual_severity))


class AlertFatigueSuppression:
    """Suppress redundant alerts to reduce fatigue."""
    
    def __init__(self):
        """Initialize suppression engine."""
        self.alert_frequency: Dict[str, List[datetime]] = {}
        self.suppression_rules: List[Dict[str, Any]] = []
    
    def calculate_fatigue_score(
        self,
        group: AlertGroup,
        dedup_count: int
    ) -> float:
        """Calculate alert fatigue score."""
        # Fatigue based on:
        # 1. Number of deduplicates in group
        # 2. Frequency over time
        # 3. Alert severity
        
        dedup_fatigue = min(dedup_count / 10.0, 1.0)
        
        # Time-based fatigue
        if len(group.alerts) > 1:
            time_span = (group.last_occurrence - group.first_occurrence).total_seconds()
            if time_span > 0:
                frequency = len(group.alerts) / (time_span / 60)  # Per minute
                time_fatigue = min(frequency / 10.0, 1.0)
            else:
                time_fatigue = 0.5
        else:
            time_fatigue = 0.0
        
        # Severity-based fatigue (lower severity = more fatigue)
        severity_fatigue = 1.0 - (group.severity.value / 5.0)
        
        # Combined score
        fatigue = (dedup_fatigue * 0.5) + (time_fatigue * 0.3) + (severity_fatigue * 0.2)
        
        return min(fatigue, 1.0)
    
    def should_suppress(
        self,
        group: AlertGroup,
        dedup_count: int,
        fatigue_threshold: float = 0.7
    ) -> bool:
        """Determine if alert should be suppressed."""
        fatigue_score = self.calculate_fatigue_score(group, dedup_count)
        
        # Suppress if:
        # 1. Fatigue score exceeds threshold
        # 2. Severity is LOW or INFO
        # 3. Too many recent occurrences
        
        should_suppress = (
            fatigue_score > fatigue_threshold and
            group.severity in [AlertSeverity.LOW, AlertSeverity.INFO]
        ) or (dedup_count > 20 and group.severity not in [AlertSeverity.CRITICAL])
        
        return should_suppress
    
    def add_suppression_rule(
        self,
        metric_pattern: str,
        source_pattern: str,
        reason: str
    ) -> None:
        """Add suppression rule."""
        rule = {
            'metric_pattern': metric_pattern,
            'source_pattern': source_pattern,
            'reason': reason,
            'created_at': datetime.utcnow()
        }
        self.suppression_rules.append(rule)


class ThresholdOptimizer:
    """Dynamically optimize alert thresholds."""
    
    def __init__(self):
        """Initialize optimizer."""
        self.metric_thresholds: Dict[str, List[float]] = {}
        self.false_positive_history: List[RawAlert] = []
        self.true_positive_history: List[RawAlert] = []
    
    def add_false_positive(self, alert: RawAlert) -> None:
        """Record false positive alert."""
        self.false_positive_history.append(alert)
    
    def add_true_positive(self, alert: RawAlert) -> None:
        """Record true positive alert."""
        self.true_positive_history.append(alert)
    
    def optimize_thresholds(self) -> Dict[str, float]:
        """Optimize thresholds based on feedback."""
        optimized = {}
        
        # For each metric with history
        all_alerts = self.false_positive_history + self.true_positive_history
        metrics = set(a.metric_name for a in all_alerts)
        
        for metric in metrics:
            metric_fps = [a for a in self.false_positive_history if a.metric_name == metric]
            metric_tps = [a for a in self.true_positive_history if a.metric_name == metric]
            
            if not metric_tps:
                continue
            
            # Calculate optimal threshold
            tp_avg = sum(a.metric_value for a in metric_tps) / len(metric_tps)
            fp_avg = sum(a.metric_value for a in metric_fps) / len(metric_fps) if metric_fps else 0
            
            # New threshold between false positives and true positives
            if metric_fps:
                optimized[metric] = (tp_avg + fp_avg) / 2.0
            else:
                optimized[metric] = tp_avg * 1.1
        
        return optimized


@dataclass
class AlertEnrichmentContext:
    """Context for alert enrichment."""
    
    related_metrics: Dict[str, float] = field(default_factory=dict)
    service_status: Dict[str, str] = field(default_factory=dict)
    recent_changes: List[str] = field(default_factory=list)
    affected_users: int = 0
    incident_history: List[str] = field(default_factory=list)


class IntelligentAlerter:
    """Central intelligent alerting engine."""
    
    def __init__(self):
        """Initialize alerter."""
        self.deduplicator = AlertDeduplicator()
        self.severity_predictor = SeverityPredictor()
        self.fatigue_suppressor = AlertFatigueSuppression()
        self.threshold_optimizer = ThresholdOptimizer()
        self.processed_alerts: List[EnrichedAlert] = []
        self._stats = {
            'alerts_received': 0,
            'alerts_deduplicated': 0,
            'alerts_suppressed': 0,
            'alerts_escalated': 0
        }
    
    def process_alert(
        self,
        raw_alert: RawAlert,
        context: Optional[AlertEnrichmentContext] = None
    ) -> EnrichedAlert:
        """Process alert through intelligence pipeline."""
        self._stats['alerts_received'] += 1
        
        # Step 1: Deduplication
        group = self.deduplicator.process_alert(raw_alert)
        is_duplicate = group.occurrence_count > 1
        if is_duplicate:
            self._stats['alerts_deduplicated'] += 1
        
        # Step 2: Severity prediction
        predicted_severity = self.severity_predictor.predict_severity(raw_alert)
        group.severity = predicted_severity
        
        # Step 3: Fatigue suppression
        fatigue_score = self.fatigue_suppressor.calculate_fatigue_score(
            group,
            group.occurrence_count
        )
        should_suppress = self.fatigue_suppressor.should_suppress(
            group,
            group.occurrence_count
        )
        if should_suppress:
            self._stats['alerts_suppressed'] += 1
        
        # Step 4: Escalation decision
        if predicted_severity == AlertSeverity.CRITICAL:
            self._stats['alerts_escalated'] += 1
        
        # Prepare enrichment
        enrichment = {
            'deduplication_group_size': group.occurrence_count,
            'predicted_severity': predicted_severity.name,
            'fatigue_score': fatigue_score,
            'suggested_suppression': should_suppress
        }
        
        # Create enriched alert
        enriched = EnrichedAlert(
            id=raw_alert.id,
            original_alert=raw_alert,
            predicted_severity=predicted_severity,
            deduplication_group=group.signature,
            fatigue_score=fatigue_score,
            should_suppress=should_suppress,
            context=context.to_dict() if context else {},
            enrichment_metadata=enrichment
        )
        
        self.processed_alerts.append(enriched)
        return enriched
    
    def get_active_alerts(
        self,
        include_suppressed: bool = False
    ) -> List[EnrichedAlert]:
        """Get active alerts."""
        active = [a for a in self.processed_alerts if not a.should_suppress or include_suppressed]
        
        # Sort by severity descending
        active.sort(key=lambda a: a.predicted_severity.value, reverse=True)
        
        return active
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get alerter statistics."""
        return {
            'alerts_received': self._stats['alerts_received'],
            'alerts_deduplicated': self._stats['alerts_deduplicated'],
            'alerts_suppressed': self._stats['alerts_suppressed'],
            'alerts_escalated': self._stats['alerts_escalated'],
            'total_processed': len(self.processed_alerts),
            'active_groups': len(self.deduplicator.get_active_groups()),
            'deduplication_ratio': (
                self._stats['alerts_deduplicated'] / max(self._stats['alerts_received'], 1)
            ),
            'suppression_ratio': (
                self._stats['alerts_suppressed'] / max(self._stats['alerts_received'], 1)
            )
        }
