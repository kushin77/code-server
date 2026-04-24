from pathlib import Path
import asyncio
import sys

APP_DIR = Path(__file__).resolve().parents[1]
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

import main as scheduler_main
from cost_tracker import CostTracker
from monitors import ResourceMonitoringService
from router import ExecutionScheduler


def test_app_imports_cleanly():
    assert scheduler_main.app.title == "Execution Scheduler"


def test_sensitive_tasks_route_local():
    scheduler = ExecutionScheduler()

    decision = scheduler.route_task(
        task_id="task-sensitive",
        task_type="data_processing",
        data_classification="confidential",
        estimated_cpu_cores=4,
    )

    assert decision.destination == "local"
    assert "Sensitive data" in decision.reason


def test_test_suite_routes_to_ci_when_local_saturated():
    scheduler = ExecutionScheduler()
    scheduler.update_local_resources({"cpu_available_percent": 5})

    decision = scheduler.route_task(
        task_id="task-ci",
        task_type="test_suite",
        estimated_cpu_cores=2,
    )

    assert decision.destination == "ci"
    assert "CI runner" in decision.reason


def test_elite_user_gets_local_priority_when_capacity_available():
    scheduler = ExecutionScheduler()
    scheduler.update_local_resources({"cpu_available_percent": 30})

    decision = scheduler.route_task(
        task_id="task-elite",
        task_type="data_processing",
        estimated_cpu_cores=16,
        user_reputation_tier="elite",
    )

    assert decision.destination == "local"
    assert "Elite user priority" in decision.reason


def test_paid_ci_tasks_are_billed_and_enforce_budget_controls():
    tracker = CostTracker(monthly_ci_budget_usd=1.0)

    cost = tracker.calculate_task_cost(
        task_id="task-paid-ci",
        destination="ci",
        duration_seconds=3600,
        ci_runner_type="paid",
    )

    assert cost.resource_cost_usd > 0
    assert tracker.check_budget_alert() is True
    assert tracker.should_enforce_cost_controls() is True


def test_resource_monitor_returns_metrics_without_psutil():
    service = ResourceMonitoringService()

    metrics = asyncio.run(service.get_all_metrics())

    assert set(metrics) >= {"local", "ci", "edge", "timestamp"}
    assert "cpu" in metrics["local"]
    assert "queue_depth" in metrics["ci"]
    assert "available_nodes" in metrics["edge"]