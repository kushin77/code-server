#!/usr/bin/env python3
# @file        apps/prompt-gateway/tests/test_router_metrics.py
# @module      prompt-gateway/tests
# @description Tests for router metrics collection and analysis
#

import pytest
import time
from unittest.mock import Mock
import sys
sys.path.insert(0, "/app/apps/prompt-gateway")

from router_metrics import RouterMetricsCollector, RoutingDecision, ModelMetric


class TestRouterMetricsCollector:
    """Test metrics collection and aggregation"""
    
    @pytest.fixture
    def collector(self):
        """Initialize metrics collector"""
        return RouterMetricsCollector(retention_hours=24)
    
    def test_record_routing_decision(self, collector):
        """Test recording routing decision"""
        collector.record_decision(
            decision_id="d1",
            requested_model="gpt-4",
            selected_model="llama3:70b",
            fallback_chain=["llama3:8b", "mistral:7b"],
            user_reputation="ELITE",
            request_type="reasoning",
            token_count=500,
            latency_ms=1250,
            success=True
        )
        
        assert len(collector.decisions) == 1
        assert collector.decisions[0].selected_model == "llama3:70b"
        assert collector.decisions[0].success == True
    
    def test_record_failed_decision(self, collector):
        """Test recording failed routing decision"""
        collector.record_decision(
            decision_id="d2",
            requested_model="llama3:70b",
            selected_model="llama3:8b",
            fallback_chain=["mistral:7b"],
            user_reputation="STANDARD",
            request_type="general",
            token_count=100,
            latency_ms=5000,
            success=False,
            error="timeout"
        )
        
        assert collector.decisions[0].success == False
        assert collector.decisions[0].error == "timeout"
    
    def test_model_latency_stats(self, collector):
        """Test latency percentile calculation"""
        # Record decisions with various latencies
        for latency in [100, 150, 200, 250, 300, 350, 400, 450, 500, 1000]:
            collector.record_decision(
                decision_id=f"d{latency}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=latency,
                success=True
            )
        
        stats = collector.get_model_latency_stats("llama3:8b")
        
        assert stats["count"] == 10
        assert stats["min_ms"] == 100
        assert stats["max_ms"] == 1000
        assert stats["p50_ms"] == 300
        assert stats["p95_ms"] == 1000
    
    def test_model_error_rate(self, collector):
        """Test error rate calculation"""
        # 7 successes, 3 failures
        for i in range(7):
            collector.record_decision(
                decision_id=f"success{i}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=100 + i * 50,
                success=True
            )
        
        for i in range(3):
            collector.record_decision(
                decision_id=f"failure{i}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=5000,
                success=False,
                error="timeout"
            )
        
        error_stats = collector.get_model_error_rate("llama3:8b")
        
        assert error_stats["total_requests"] == 10
        assert error_stats["failure_count"] == 3
        assert error_stats["error_rate_percent"] == 30.0
        assert error_stats["error_types"]["timeout"] == 3
    
    def test_fallback_frequency(self, collector):
        """Test fallback usage calculation"""
        # Decisions with fallback chains
        for i in range(5):
            collector.record_decision(
                decision_id=f"fb{i}",
                requested_model="gpt-4",
                selected_model="llama3:70b",
                fallback_chain=["llama3:8b", "mistral:7b"],
                user_reputation="ELITE",
                request_type="reasoning",
                token_count=500,
                latency_ms=1000,
                success=True
            )
        
        # Decisions without fallback
        for i in range(5):
            collector.record_decision(
                decision_id=f"nofb{i}",
                requested_model=None,
                selected_model="llama3:70b",
                fallback_chain=[],
                user_reputation="ELITE",
                request_type="reasoning",
                token_count=100,
                latency_ms=500,
                success=True
            )
        
        fallback_freq = collector.get_fallback_frequency()
        
        assert "llama3:70b" in fallback_freq
        assert fallback_freq["llama3:70b"] == 50.0  # 5/10 used fallback
    
    def test_routing_by_user_tier(self, collector):
        """Test routing distribution by user tier"""
        tiers = ["ELITE", "SENIOR", "STANDARD", "RESTRICTED"]
        
        for tier in tiers:
            collector.record_decision(
                decision_id=f"tier{tier}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation=tier,
                request_type="general",
                token_count=100,
                latency_ms=100,
                success=True
            )
        
        tier_dist = collector.get_routing_by_user_tier()
        
        assert len(tier_dist) == 4
        for tier in tiers:
            assert tier_dist[tier]["llama3:8b"] == 1
    
    def test_routing_by_request_type(self, collector):
        """Test routing distribution by request type"""
        types = ["code_generation", "reasoning", "summarization", "general"]
        
        for req_type in types:
            collector.record_decision(
                decision_id=f"type{req_type}",
                requested_model=None,
                selected_model="llama3:8b" if req_type != "code_generation" else "codellama:13b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type=req_type,
                token_count=100,
                latency_ms=100,
                success=True
            )
        
        type_dist = collector.get_routing_by_request_type()
        
        assert "code_generation" in type_dist
        assert "reasoning" in type_dist
    
    def test_throughput_stats(self, collector):
        """Test throughput calculation"""
        now = time.time()
        
        # Record 10 decisions in last 60 seconds
        for i in range(10):
            collector.record_decision(
                decision_id=f"tp{i}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=100,
                success=True
            )
            # Manually set timestamp to recent
            collector.decisions[-1].timestamp = now - (60 - i*6)
        
        throughput = collector.get_throughput_stats("llama3:8b", window_seconds=60)
        
        assert throughput["requests_in_window"] == 10
        assert throughput["throughput_req_per_sec"] > 0
    
    def test_model_quality_score(self, collector):
        """Test composite quality score"""
        # High quality model: fast, reliable
        for i in range(20):
            collector.record_decision(
                decision_id=f"hq{i}",
                requested_model=None,
                selected_model="fast_model",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=100 + i*10,  # Fast
                success=True  # Always succeeds
            )
        
        quality = collector.get_model_quality_score("fast_model")
        
        assert quality["success_rate_percent"] == 100.0
        assert quality["quality_score"] > 70  # Should be high
    
    def test_prometheus_export(self, collector):
        """Test Prometheus metrics export"""
        for i in range(5):
            collector.record_decision(
                decision_id=f"prom{i}",
                requested_model=None,
                selected_model="llama3:8b",
                fallback_chain=[],
                user_reputation="STANDARD",
                request_type="general",
                token_count=100,
                latency_ms=100 + i*100,
                success=i < 4  # Last one fails
            )
        
        metrics = collector.export_prometheus_metrics()
        
        assert len(metrics) > 0
        assert any("router_latency" in m for m in metrics)
        assert any("router_error_rate" in m for m in metrics)
    
    def test_dashboard_data(self, collector):
        """Test comprehensive dashboard data generation"""
        for i in range(10):
            collector.record_decision(
                decision_id=f"dash{i}",
                requested_model=None,
                selected_model="llama3:8b" if i % 2 == 0 else "codellama:13b",
                fallback_chain=[],
                user_reputation="STANDARD" if i % 2 == 0 else "ELITE",
                request_type="general",
                token_count=100,
                latency_ms=100 + i*50,
                success=True
            )
        
        dashboard = collector.get_detailed_dashboard_data()
        
        assert dashboard["summary"]["total_decisions"] == 10
        assert dashboard["summary"]["models_in_rotation"] == 2
        assert "by_model" in dashboard
        assert "distributions" in dashboard
