#!/usr/bin/env python3
# @file        apps/prompt-gateway/router_metrics.py
# @module      prompt-gateway/router
# @description Router metrics and performance monitoring
#
# Comprehensive metrics collection, aggregation, and analysis for model routing decisions
# Supports Prometheus export and real-time dashboarding

import time
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from collections import defaultdict
import json


@dataclass
class ModelMetric:
    """Per-model performance metric"""
    model_id: str
    metric_name: str  # latency, throughput, error_rate, fallback_rate, quality_score
    value: float
    timestamp: float
    dimensions: Dict[str, str] = field(default_factory=dict)  # user_tier, request_type, hour


@dataclass
class RoutingDecision:
    """Recorded routing decision for analysis"""
    decision_id: str
    requested_model: Optional[str]
    selected_model: str
    fallback_chain: List[str]
    user_reputation: str
    request_type: str
    token_count: int
    latency_ms: float
    success: bool
    error: Optional[str]
    timestamp: float


class RouterMetricsCollector:
    """
    Collect and aggregate routing metrics.
    
    Tracks:
    - Latency per model (p50, p95, p99)
    - Throughput (req/sec per model)
    - Error rate by model
    - Fallback frequency
    - Request type distribution
    - User tier routing distribution
    - A/B test performance
    """
    
    def __init__(self, retention_hours: int = 24):
        self.retention_hours = retention_hours
        self.decisions: List[RoutingDecision] = []
        self.model_metrics: Dict[str, List[ModelMetric]] = defaultdict(list)
        self.current_window_start = time.time()
    
    def record_decision(self, 
                       decision_id: str,
                       requested_model: Optional[str],
                       selected_model: str,
                       fallback_chain: List[str],
                       user_reputation: str,
                       request_type: str,
                       token_count: int,
                       latency_ms: float,
                       success: bool,
                       error: Optional[str] = None) -> None:
        """Record a routing decision"""
        decision = RoutingDecision(
            decision_id=decision_id,
            requested_model=requested_model,
            selected_model=selected_model,
            fallback_chain=fallback_chain,
            user_reputation=user_reputation,
            request_type=request_type,
            token_count=token_count,
            latency_ms=latency_ms,
            success=success,
            error=error,
            timestamp=time.time()
        )
        
        self.decisions.append(decision)
        
        # Clean old decisions
        cutoff_time = time.time() - (self.retention_hours * 3600)
        self.decisions = [d for d in self.decisions if d.timestamp > cutoff_time]
    
    def record_metric(self, model_id: str, metric_name: str, value: float, 
                     dimensions: Optional[Dict[str, str]] = None) -> None:
        """Record performance metric for model"""
        metric = ModelMetric(
            model_id=model_id,
            metric_name=metric_name,
            value=value,
            timestamp=time.time(),
            dimensions=dimensions or {}
        )
        
        self.model_metrics[model_id].append(metric)
        
        # Keep recent metrics only
        cutoff_time = time.time() - (self.retention_hours * 3600)
        self.model_metrics[model_id] = [
            m for m in self.model_metrics[model_id]
            if m.timestamp > cutoff_time
        ]
    
    def get_model_latency_stats(self, model_id: str) -> Dict:
        """Calculate latency percentiles for model"""
        decisions = [d for d in self.decisions if d.selected_model == model_id and d.success]
        
        if not decisions:
            return {"error": "No successful decisions for model"}
        
        latencies = sorted([d.latency_ms for d in decisions])
        n = len(latencies)
        
        return {
            "model_id": model_id,
            "count": n,
            "min_ms": latencies[0],
            "max_ms": latencies[-1],
            "avg_ms": sum(latencies) / n,
            "p50_ms": latencies[int(n * 0.5)],
            "p95_ms": latencies[int(n * 0.95)] if n > 20 else latencies[-1],
            "p99_ms": latencies[int(n * 0.99)] if n > 100 else latencies[-1],
        }
    
    def get_model_error_rate(self, model_id: str) -> Dict:
        """Calculate error rate for model"""
        decisions = [d for d in self.decisions if d.selected_model == model_id]
        
        if not decisions:
            return {"error": "No decisions for model"}
        
        failures = [d for d in decisions if not d.success]
        error_rate = len(failures) / len(decisions) * 100
        
        error_types = defaultdict(int)
        for d in failures:
            if d.error:
                error_types[d.error] += 1
        
        return {
            "model_id": model_id,
            "total_requests": len(decisions),
            "failure_count": len(failures),
            "error_rate_percent": round(error_rate, 2),
            "error_types": dict(error_types)
        }
    
    def get_fallback_frequency(self) -> Dict[str, float]:
        """Calculate fallback usage frequency by model"""
        model_fallback_count = defaultdict(int)
        model_total_count = defaultdict(int)
        
        for decision in self.decisions:
            model_total_count[decision.selected_model] += 1
            if len(decision.fallback_chain) > 0:
                model_fallback_count[decision.selected_model] += 1
        
        return {
            model: (count / model_total_count[model] * 100) if model_total_count[model] > 0 else 0
            for model, count in model_fallback_count.items()
        }
    
    def get_routing_by_user_tier(self) -> Dict:
        """Distribution of routing decisions by user tier"""
        tier_model_dist = defaultdict(lambda: defaultdict(int))
        
        for decision in self.decisions:
            tier_model_dist[decision.user_reputation][decision.selected_model] += 1
        
        return {
            tier: dict(models)
            for tier, models in tier_model_dist.items()
        }
    
    def get_routing_by_request_type(self) -> Dict:
        """Distribution of routing decisions by request type"""
        type_model_dist = defaultdict(lambda: defaultdict(int))
        
        for decision in self.decisions:
            type_model_dist[decision.request_type][decision.selected_model] += 1
        
        return {
            req_type: dict(models)
            for req_type, models in type_model_dist.items()
        }
    
    def get_throughput_stats(self, model_id: str, window_seconds: int = 300) -> Dict:
        """Calculate throughput (req/sec) for model in time window"""
        now = time.time()
        window_start = now - window_seconds
        
        recent_decisions = [
            d for d in self.decisions
            if d.selected_model == model_id and d.timestamp > window_start
        ]
        
        throughput = len(recent_decisions) / window_seconds if window_seconds > 0 else 0
        
        return {
            "model_id": model_id,
            "window_seconds": window_seconds,
            "requests_in_window": len(recent_decisions),
            "throughput_req_per_sec": round(throughput, 2)
        }
    
    def get_model_quality_score(self, model_id: str) -> Dict:
        """
        Calculate composite quality score based on:
        - Success rate
        - Latency (lower is better)
        - Throughput (higher is better)
        - Error frequency
        """
        decisions = [d for d in self.decisions if d.selected_model == model_id]
        
        if not decisions:
            return {"error": "No decisions for model"}
        
        success_rate = sum(1 for d in decisions if d.success) / len(decisions)
        avg_latency = sum(d.latency_ms for d in decisions) / len(decisions)
        error_rate = 1 - success_rate
        
        # Composite score: 0-100
        # 40% success rate, 30% latency, 30% throughput
        latency_score = max(0, 100 - (avg_latency / 100))  # Normalize
        throughput_ms = 300000 / len(decisions) if len(decisions) > 0 else 1000
        throughput_score = max(0, 100 - (throughput_ms / 100))
        
        quality_score = (
            (success_rate * 40) +
            (latency_score * 30) +
            (throughput_score * 30)
        ) / 100
        
        return {
            "model_id": model_id,
            "quality_score": round(quality_score, 2),
            "success_rate_percent": round(success_rate * 100, 2),
            "avg_latency_ms": round(avg_latency, 2),
            "error_rate_percent": round(error_rate * 100, 2),
            "decision_count": len(decisions)
        }
    
    def export_prometheus_metrics(self) -> List[str]:
        """Export metrics in Prometheus format"""
        metrics = []
        
        # Latency metrics
        for model_id in set(d.selected_model for d in self.decisions):
            stats = self.get_model_latency_stats(model_id)
            if "error" not in stats:
                metrics.append(f'router_latency_p50{{model="{model_id}"}} {stats["p50_ms"]}')
                metrics.append(f'router_latency_p95{{model="{model_id}"}} {stats["p95_ms"]}')
                metrics.append(f'router_latency_p99{{model="{model_id}"}} {stats["p99_ms"]}')
        
        # Error rate metrics
        for model_id in set(d.selected_model for d in self.decisions):
            error_stats = self.get_model_error_rate(model_id)
            if "error" not in error_stats:
                metrics.append(
                    f'router_error_rate{{model="{model_id}"}} {error_stats["error_rate_percent"]}'
                )
        
        # Throughput metrics
        for model_id in set(d.selected_model for d in self.decisions):
            throughput_stats = self.get_throughput_stats(model_id)
            metrics.append(
                f'router_throughput{{model="{model_id}"}} {throughput_stats["throughput_req_per_sec"]}'
            )
        
        # Quality score
        for model_id in set(d.selected_model for d in self.decisions):
            quality = self.get_model_quality_score(model_id)
            if "error" not in quality:
                metrics.append(f'router_quality_score{{model="{model_id}"}} {quality["quality_score"]}')
        
        return metrics
    
    def get_detailed_dashboard_data(self) -> Dict:
        """Get complete metrics for dashboard rendering"""
        model_ids = set(d.selected_model for d in self.decisions)
        
        return {
            "summary": {
                "total_decisions": len(self.decisions),
                "models_in_rotation": len(model_ids),
                "collection_window_hours": self.retention_hours
            },
            "by_model": {
                model_id: {
                    "latency": self.get_model_latency_stats(model_id),
                    "errors": self.get_model_error_rate(model_id),
                    "throughput": self.get_throughput_stats(model_id),
                    "quality": self.get_model_quality_score(model_id),
                    "fallback_rate": self.get_fallback_frequency().get(model_id, 0)
                }
                for model_id in model_ids
            },
            "distributions": {
                "by_user_tier": self.get_routing_by_user_tier(),
                "by_request_type": self.get_routing_by_request_type()
            }
        }
