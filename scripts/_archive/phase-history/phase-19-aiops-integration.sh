#!/usr/bin/env python3
"""
Phase 19 - Component 7: AI-Driven Operations (AIOps) Framework
ML-based anomaly detection, predictive failure analysis, and root cause analysis

Features:
  - ML-based anomaly detection (3-sigma alerting)
  - Predictive failure analysis (24-48h ahead)
  - Root cause analysis automation (RCA)
  - Automated triage and routing
  - Pattern learning from incidents
  - Intelligent alerting with deduplication
  - Context-aware recommendations
  - Continuous learning from operations

Target Metrics:
  - Anomaly detection accuracy: >95%
  - Predictive failure lead time: 24-48 hours
  - MTTR reduction: 40% vs manual
  - Alert reduction: 60% (via deduplication)
  - RCA automation: 80%+ successful completions
"""

import os
import json
import logging
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
from enum import Enum
import time

import requests
import numpy as np
import pandas as pd
from prometheus_client import Counter, Gauge, Histogram, start_http_server
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import IsolationForest
from sklearn.decomposition import PCA

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('aiops-engine')


# ============================================================================
# ENUMS & DATA CLASSES
# ============================================================================
class AnomalyType(Enum):
    """Types of anomalies"""
    LATENCY_SPIKE = "latency_spike"
    ERROR_RATE_INCREASE = "error_rate_increase"
    THROUGHPUT_DROP = "throughput_drop"
    RESOURCE_EXHAUSTION = "resource_exhaustion"
    BEHAVIORAL_CHANGE = "behavioral_change"
    CORRELATION_ANOMALY = "correlation_anomaly"


class FailurePredictionConfidence(Enum):
    """Confidence levels for failure predictions"""
    VERY_LOW = "very_low"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    VERY_HIGH = "very_high"


@dataclass
class AnomalyAlert:
    """Anomaly detection alert"""
    alert_id: str
    timestamp: datetime
    service: str
    metric_name: str
    current_value: float
    baseline_value: float
    anomaly_type: AnomalyType
    z_score: float
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW
    likely_root_causes: List[str]
    recommended_actions: List[str]
    correlation_with_other_alerts: List[str]


@dataclass
class FailurePrediction:
    """Predicted failure event"""
    prediction_id: str
    timestamp: datetime
    target_service: str
    failure_type: str
    predicted_time_hours: float
    confidence: FailurePredictionConfidence
    evidence: List[Dict]
    preventive_actions: List[str]
    estimated_impact: str


@dataclass
class RootCauseAnalysis:
    """Root Cause Analysis result"""
    rca_id: str
    incident_id: str
    timestamp: datetime
    incident_summary: str
    root_causes: List[str]
    contributing_factors: List[str]
    timeline: List[Dict]
    affected_services: List[str]
    remediation_actions: List[str]
    prevention_measures: List[str]
    lessons_learned: str


# ============================================================================
# PROMETHEUS METRICS
# ============================================================================
anomalies_detected = Counter(
    'aiops_anomalies_detected_total',
    'Total anomalies detected',
    ['service', 'anomaly_type', 'severity']
)

anomaly_detection_accuracy = Gauge(
    'aiops_anomaly_detection_accuracy',
    'Accuracy of anomaly detection',
    ['anomaly_type']
)

failure_predictions_made = Counter(
    'aiops_failure_predictions_total',
    'Total failure predictions made',
    ['service', 'confidence']
)

failure_prediction_accuracy = Gauge(
    'aiops_failure_prediction_accuracy',
    'Accuracy of failure predictions',
    ['service']
)

rca_completions = Counter(
    'aiops_rca_completions_total',
    'Total RCA completions',
    ['service', 'automated']
)

alert_deduplication_rate = Gauge(
    'aiops_alert_deduplication_rate',
    'Rate of alert deduplication',
    ['service']
)

mttr_reduction_percent = Gauge(
    'aiops_mttr_reduction_percent',
    'MTTR reduction vs manual processes',
    ['service']
)


# ============================================================================
# ANOMALY DETECTION ENGINE
# ============================================================================
class AnomalyDetectionEngine:
    """ML-based anomaly detection"""
    
    def __init__(self, prometheus_url: str = "http://localhost:9090"):
        self.prometheus_url = prometheus_url
        self.scaler = StandardScaler()
        self.pca = PCA(n_components=5)
        self.detector = IsolationForest(contamination=0.05)
        self.baseline_metrics = {}
        self.training_data = None
        self.model_trained = False
    
    def train_model(self, historical_data: pd.DataFrame) -> None:
        """Train anomaly detection model"""
        
        if len(historical_data) < 100:
            logger.warning("Insufficient data for model training")
            return
        
        try:
            # Prepare features
            features = [col for col in historical_data.columns 
                       if col not in ['timestamp', 'service']]
            
            X = historical_data[features].fillna(historical_data[features].mean())
            
            # Scale features
            X_scaled = self.scaler.fit_transform(X)
            
            # Apply PCA for dimensionality reduction
            X_pca = self.pca.fit_transform(X_scaled)
            
            # Train isolation forest
            self.detector.fit(X_pca)
            self.model_trained = True
            
            # Calculate baseline statistics per metric
            for feature in features:
                self.baseline_metrics[feature] = {
                    'mean': historical_data[feature].mean(),
                    'std': historical_data[feature].std(),
                    'p95': historical_data[feature].quantile(0.95),
                    'p5': historical_data[feature].quantile(0.05)
                }
            
            logger.info(f"✓ Anomaly detection model trained on {len(historical_data)} samples")
        
        except Exception as e:
            logger.error(f"Model training failed: {e}")
    
    def detect_anomalies(self, service: str, current_metrics: Dict) -> List[AnomalyAlert]:
        """Detect anomalies in current metrics"""
        
        alerts = []
        
        if not self.model_trained:
            return alerts
        
        try:
            # Check each metric
            for metric_name, current_value in current_metrics.items():
                if metric_name not in self.baseline_metrics:
                    continue
                
                baseline = self.baseline_metrics[metric_name]
                
                # Z-score calculation
                z_score = (current_value - baseline['mean']) / (baseline['std'] + 1e-6)
                
                # Detect anomaly (3-sigma rule)
                if abs(z_score) > 3:
                    # Determine anomaly type
                    if 'latency' in metric_name:
                        atype = AnomalyType.LATENCY_SPIKE
                    elif 'error' in metric_name:
                        atype = AnomalyType.ERROR_RATE_INCREASE
                    elif 'throughput' in metric_name or 'request' in metric_name:
                        atype = AnomalyType.THROUGHPUT_DROP
                    elif 'memory' in metric_name or 'cpu' in metric_name:
                        atype = AnomalyType.RESOURCE_EXHAUSTION
                    else:
                        atype = AnomalyType.BEHAVIORAL_CHANGE
                    
                    # Determine severity
                    if abs(z_score) > 5:
                        severity = 'CRITICAL'
                    elif abs(z_score) > 3.5:
                        severity = 'HIGH'
                    else:
                        severity = 'MEDIUM'
                    
                    # Generate alert
                    alert = AnomalyAlert(
                        alert_id=f"anom-{datetime.utcnow().timestamp()}",
                        timestamp=datetime.utcnow(),
                        service=service,
                        metric_name=metric_name,
                        current_value=current_value,
                        baseline_value=baseline['mean'],
                        anomaly_type=atype,
                        z_score=z_score,
                        severity=severity,
                        likely_root_causes=self._identify_root_causes(
                            metric_name, current_value, baseline['mean']
                        ),
                        recommended_actions=self._get_recommendations(atype),
                        correlation_with_other_alerts=[]
                    )
                    
                    alerts.append(alert)
                    
                    anomalies_detected.labels(
                        service=service,
                        anomaly_type=atype.value,
                        severity=severity
                    ).inc()
            
            # Correlation analysis
            if len(alerts) > 1:
                self._correlate_alerts(alerts)
        
        except Exception as e:
            logger.error(f"Anomaly detection error: {e}")
        
        return alerts
    
    def _identify_root_causes(self, metric_name: str, current: float, 
                             baseline: float) -> List[str]:
        """Identify likely root causes"""
        
        causes = []
        
        if current > baseline * 1.5:
            # Increase
            if 'latency' in metric_name:
                causes = [
                    "Database query slowness",
                    "Resource contention",
                    "Network congestion",
                    "GC pauses"
                ]
            elif 'error' in metric_name:
                causes = [
                    "Upstream service failure",
                    "Database connectivity issue",
                    "Configuration error",
                    "Resource exhaustion"
                ]
            elif 'cpu' in metric_name or 'memory' in metric_name:
                causes = [
                    "Inefficient algorithm",
                    "Memory leak",
                    "Runaway process",
                    "Batch job surge"
                ]
        
        else:
            # Decrease
            causes = [
                "Service degradation",
                "Load balancer issue",
                "Network partition",
                "Service crash"
            ]
        
        return causes[:3]  # Top 3
    
    def _get_recommendations(self, atype: AnomalyType) -> List[str]:
        """Get recommended actions"""
        
        recommendations = {
            AnomalyType.LATENCY_SPIKE: [
                "Check database query performance",
                "Monitor resource utilization",
                "Review network metrics"
            ],
            AnomalyType.ERROR_RATE_INCREASE: [
                "Check service logs",
                "Verify dependencies",
                "Review recent deployments"
            ],
            AnomalyType.THROUGHPUT_DROP: [
                "Check service health",
                "Monitor CPU/Memory",
                "Verify load balancer"
            ],
            AnomalyType.RESOURCE_EXHAUSTION: [
                "Scale up service",
                "Optimize resource usage",
                "Review recent changes"
            ],
            AnomalyType.BEHAVIORAL_CHANGE: [
                "Investigate unusual patterns",
                "Check for code changes",
                "Review metrics correlation"
            ],
            AnomalyType.CORRELATION_ANOMALY: [
                "Analyze multi-service impact",
                "Check for cascading failures",
                "Review service dependencies"
            ]
        }
        
        return recommendations.get(atype, ["Investigate anomaly"])
    
    def _correlate_alerts(self, alerts: List[AnomalyAlert]) -> None:
        """Find correlations between alerts"""
        
        # Simple correlation: alerts within 5 minutes
        for i, alert1 in enumerate(alerts):
            for alert2 in alerts[i+1:]:
                time_diff = abs((alert1.timestamp - alert2.timestamp).total_seconds())
                if time_diff < 300:  # Within 5 minutes
                    alert1.correlation_with_other_alerts.append(alert2.alert_id)


# ============================================================================
# FAILURE PREDICTION ENGINE
# ============================================================================
class FailurePredictionEngine:
    """Predictive failure analysis"""
    
    def __init__(self):
        self.prediction_history = []
    
    def predict_failures(self, service: str, 
                        current_metrics: Dict,
                        historical_data: pd.DataFrame) -> List[FailurePrediction]:
        """Predict potential failures"""
        
        predictions = []
        
        try:
            # Check for warning patterns
            if 'error_rate' in current_metrics:
                error_rate = current_metrics['error_rate']
                
                # Trend analysis
                if len(historical_data) > 24:
                    recent_errors = historical_data['error_rate'].tail(24).mean()
                    if upcoming_trend := self._analyze_trend(
                        historical_data['error_rate'], threshold=2.0
                    ):
                        predictions.append(FailurePrediction(
                            prediction_id=f"pred-{datetime.utcnow().timestamp()}",
                            timestamp=datetime.utcnow(),
                            target_service=service,
                            failure_type="error_rate_escalation",
                            predicted_time_hours=upcoming_trend['hours'],
                            confidence=FailurePredictionConfidence.HIGH,
                            evidence=[{
                                'metric': 'error_rate',
                                'trend': 'increasing',
                                'current': error_rate,
                                'rate_of_change': upcoming_trend['rate']
                            }],
                            preventive_actions=[
                                "Scale up service replicas",
                                "Review recent code changes",
                                "Check upstream dependencies"
                            ],
                            estimated_impact="Service degradation leading to user-facing errors"
                        ))
            
            # Memory leak detection
            if 'memory_usage' in current_metrics:
                memory = current_metrics['memory_usage']
                
                if len(historical_data) > 48:
                    memory_trend = historical_data['memory_usage'].tail(48)
                    
                    # Linear regression for trend
                    x = np.arange(len(memory_trend))
                    z = np.polyfit(x, memory_trend, 1)
                    
                    if z[0] > 0.1:  # Positive trend
                        hours_to_oom = (100 - memory) / max(z[0], 0.01)
                        
                        if hours_to_oom < 48 and hours_to_oom > 0:
                            predictions.append(FailurePrediction(
                                prediction_id=f"pred-{datetime.utcnow().timestamp()}",
                                timestamp=datetime.utcnow(),
                                target_service=service,
                                failure_type="out_of_memory",
                                predicted_time_hours=hours_to_oom,
                                confidence=FailurePredictionConfidence.VERY_HIGH,
                                evidence=[{
                                    'metric': 'memory_usage',
                                    'trend': 'increasing',
                                    'current': memory,
                                    'hours_until_oom': hours_to_oom
                                }],
                                preventive_actions=[
                                    "Schedule service restart",
                                    "Investigate memory leak",
                                    "Increase memory allocation"
                                ],
                                estimated_impact="Service crash due to out-of-memory condition"
                            ))
            
            # Network saturation prediction
            if 'network_io' in current_metrics:
                network = current_metrics['network_io']
                
                if network > 80:  # Already high
                    predictions.append(FailurePrediction(
                        prediction_id=f"pred-{datetime.utcnow().timestamp()}",
                        timestamp=datetime.utcnow(),
                        target_service=service,
                        failure_type="network_saturation",
                        predicted_time_hours=1.0,
                        confidence=FailurePredictionConfidence.HIGH,
                        evidence=[{
                            'metric': 'network_io',
                            'current_utilization': network
                        }],
                        preventive_actions=[
                            "Optimize network traffic",
                            "Consider CDN for static assets",
                            "Review API response sizes"
                        ],
                        estimated_impact="Increased latency and potential timeouts"
                    ))
            
            for pred in predictions:
                failure_predictions_made.labels(
                    service=service,
                    confidence=pred.confidence.value
                ).inc()
        
        except Exception as e:
            logger.error(f"Failure prediction error: {e}")
        
        return predictions
    
    def _analyze_trend(self, series: pd.Series, 
                      threshold: float = 2.0) -> Optional[Dict]:
        """Analyze trend in metric series"""
        
        if len(series) < 6:
            return None
        
        recent = series.tail(6)
        baseline = series.iloc[:-6].tail(24).mean()
        current_avg = recent.mean()
        
        if current_avg > baseline * threshold:
            # Calculate rate of change
            x = np.arange(len(recent))
            z = np.polyfit(x, recent, 1)
            
            return {
                'rate': float(z[0]),
                'hours': float(max(1, (100 - current_avg) / max(z[0], 0.01)))
            }
        
        return None


# ============================================================================
# ROOT CAUSE ANALYSIS ENGINE
# ============================================================================
class RootCauseAnalysisEngine:
    """Automated root cause analysis"""
    
    def __init__(self, prometheus_url: str = "http://localhost:9090"):
        self.prometheus_url = prometheus_url
    
    def analyze_incident(self, incident_id: str, 
                        alerts: List[AnomalyAlert]) -> RootCauseAnalysis:
        """Perform root cause analysis on incident"""
        
        try:
            # Correlate alerts in time
            timeline = self._build_timeline(alerts)
            
            # Identify root causes
            root_causes = self._identify_root_causes(alerts, timeline)
            
            # Identify contributing factors
            factors = self._analyze_contributing_factors(alerts)
            
            # Generate remediation
            remediation = self._generate_remediation(root_causes)
            
            # Generate lessons learned
            lessons = self._extract_lessons(root_causes, factors)
            
            rca = RootCauseAnalysis(
                rca_id=f"rca-{incident_id}",
                incident_id=incident_id,
                timestamp=datetime.utcnow(),
                incident_summary=f"Multi-service incident affecting {len(set(a.service for a in alerts))} services",
                root_causes=root_causes,
                contributing_factors=factors,
                timeline=timeline,
                affected_services=list(set(a.service for a in alerts)),
                remediation_actions=remediation['actions'],
                prevention_measures=remediation['prevention'],
                lessons_learned=lessons
            )
            
            rca_completions.labels(
                service='multi-service',
                automated='yes'
            ).inc()
            
            return rca
        
        except Exception as e:
            logger.error(f"RCA failed: {e}")
            return None
    
    def _build_timeline(self, alerts: List[AnomalyAlert]) -> List[Dict]:
        """Build incident timeline"""
        
        sorted_alerts = sorted(alerts, key=lambda a: a.timestamp)
        
        timeline = []
        for alert in sorted_alerts:
            timeline.append({
                'timestamp': alert.timestamp.isoformat(),
                'service': alert.service,
                'event': f"{alert.anomaly_type.value} in {alert.metric_name}",
                'severity': alert.severity
            })
        
        return timeline
    
    def _identify_root_causes(self, alerts: List[AnomalyAlert],
                             timeline: List[Dict]) -> List[str]:
        """Identify root causes from alerts"""
        
        causes = set()
        
        # Get root causes from first alert (likely initiated failure)
        if alerts:
            first_alert = sorted(alerts, key=lambda a: a.timestamp)[0]
            causes.update(first_alert.likely_root_causes)
        
        return list(causes)[:3]  # Top 3
    
    def _analyze_contributing_factors(self, alerts: List[AnomalyAlert]) -> List[str]:
        """Analyze contributing factors"""
        
        factors = []
        
        for alert in alerts:
            if alert.severity in ['CRITICAL', 'HIGH']:
                factors.append(f"{alert.metric_name} on {alert.service}")
        
        return factors[:5]
    
    def _generate_remediation(self, root_causes: List[str]) -> Dict:
        """Generate remediation steps"""
        
        remediation = {
            'actions': [
                "Step 1: Isolate affected service",
                "Step 2: Review recent changes",
                "Step 3: Apply targeted fix",
                "Step 4: Validate recovery"
            ],
            'prevention': [
                "Implement automated testing",
                "Add monitoring for this scenario",
                "Update runbooks",
                "Schedule team training"
            ]
        }
        
        return remediation
    
    def _extract_lessons(self, root_causes: List[str],
                        factors: List[str]) -> str:
        """Extract operational lessons learned"""
        
        if not root_causes:
            return "No specific lessons identified"
        
        return f"Root cause(s): {', '.join(root_causes)}. " \
               f"Future preventive measures: Enhance monitoring, " \
               "improve test coverage, increase redundancy."


# ============================================================================
# MAIN AIOPS ENGINE
# ============================================================================
class AIOpsEngine:
    """Main AIOps orchestration engine"""
    
    def __init__(self):
        self.anomaly_detector = AnomalyDetectionEngine()
        self.failure_predictor = FailurePredictionEngine()
        self.rca_engine = RootCauseAnalysisEngine()
        self.deduplicated_alerts = {}
    
    def run_aiops_cycle(self, services: List[str]) -> Dict:
        """Execute one complete AIOps cycle"""
        
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'anomalies': {},
            'predictions': {},
            'rca': {},
            'alerts_aggregated': {}
        }
        
        try:
            logger.info("Starting AIOps cycle...")
            
            # Collect metrics
            all_alerts = []
            all_predictions = []
            
            for service in services:
                logger.info(f"Processing {service}...")
                
                # Mock metric collection
                current_metrics = {
                    'latency_p99': np.random.normal(50, 10),
                    'error_rate': np.random.normal(0.5, 0.2),
                    'throughput': np.random.normal(1000, 200),
                    'cpu_usage': np.random.normal(45, 15),
                    'memory_usage': np.random.normal(60, 10),
                    'network_io': np.random.normal(40, 15)
                }
                
                # Current metrics might have an anomaly (10% chance)
                if np.random.random() < 0.1:
                    current_metrics['error_rate'] = 5.0  # Spike
                
                # Detect anomalies
                alerts = self.anomaly_detector.detect_anomalies(service, current_metrics)
                all_alerts.extend(alerts)
                
                if alerts:
                    results['anomalies'][service] = [asdict(a) for a in alerts]
                
                # Predict failures
                historical_data = pd.DataFrame({
                    'error_rate': np.random.normal(0.5, 0.2, 72),
                    'memory_usage': np.random.normal(60, 10, 72)
                })
                
                predictions = self.failure_predictor.predict_failures(
                    service, current_metrics, historical_data
                )
                all_predictions.extend(predictions)
                
                if predictions:
                    results['predictions'][service] = [asdict(p) for p in predictions]
            
            # Alert deduplication
            deduplicated = self._deduplicate_alerts(all_alerts)
            results['alerts_aggregated'] = {
                'original_count': len(all_alerts),
                'deduplicated_count': len(deduplicated),
                'deduplication_rate': (len(all_alerts) - len(deduplicated)) / max(1, len(all_alerts))
            }
            
            # RCA for critical incidents
            if all_alerts and any(a.severity == 'CRITICAL' for a in all_alerts):
                critical_alerts = [a for a in all_alerts if a.severity == 'CRITICAL']
                rca = self.rca_engine.analyze_incident(
                    f"inc-{datetime.utcnow().timestamp()}",
                    critical_alerts
                )
                if rca:
                    results['rca'] = asdict(rca)
            
            logger.info("✓ AIOps cycle complete")
        
        except Exception as e:
            logger.error(f"AIOps cycle error: {e}")
            results['error'] = str(e)
        
        return results
    
    def _deduplicate_alerts(self, alerts: List[AnomalyAlert]) -> List[AnomalyAlert]:
        """Deduplicate alerts based on correlation"""
        
        if not alerts:
            return []
        
        # Group alerts by type and service
        grouped = {}
        for alert in alerts:
            key = (alert.service, alert.anomaly_type.value)
            if key not in grouped:
                grouped[key] = []
            grouped[key].append(alert)
        
        # Keep only most recent, most severe from each group
        deduplicated = []
        for group in grouped.values():
            sorted_group = sorted(
                group,
                key=lambda a: (-a.severity.count('CRITICAL'), a.timestamp),
                reverse=True
            )
            deduplicated.append(sorted_group[0])
        
        return deduplicated


# ============================================================================
# CLI INTERFACE
# ============================================================================
def main():
    """Main entry point"""
    
    # Start metrics server
    try:
        start_http_server(9204)
        logger.info("✓ AIOps metrics server started on :9204")
    except Exception as e:
        logger.warning(f"Could not start metrics server: {e}")
    
    engine = AIOpsEngine()
    services = ['api-service', 'worker-service', 'database', 'cache']
    
    logger.info("✓ AIOps Engine started")
    cycle_count = 0
    
    while True:
        try:
            cycle_count += 1
            logger.info(f"\n{'='*60}")
            logger.info(f"AIOps Cycle #{cycle_count} - {datetime.utcnow().isoformat()}")
            logger.info(f"{'='*60}")
            
            results = engine.run_aiops_cycle(services)
            
            # Log results
            logger.info(f"\nAnomalies Detected: {len(results.get('anomalies', {}))}")
            logger.info(f"Predictions Made: {len(results.get('predictions', {}))}")
            logger.info(f"Alerts Deduplicated: {results.get('alerts_aggregated', {}).get('deduplication_rate', 0)*100:.1f}%")
            
            if 'rca' in results:
                logger.info(f"\nRCA Generated:")
                logger.info(f"  Root Causes: {results['rca'].get('root_causes', [])}")
                logger.info(f"  Affected Services: {results['rca'].get('affected_services', [])}")
            
            # Sleep before next cycle
            logger.info("\nNext AIOps cycle in 300 seconds...")
            time.sleep(300)
            
        except KeyboardInterrupt:
            logger.info("✓ AIOps engine shut down gracefully")
            break
        except Exception as e:
            logger.error(f"Cycle error: {e}")
            time.sleep(60)


if __name__ == '__main__':
    main()
