"""
Phase 26C Integration Tests (Webhooks & Custom Workflows)

Comprehensive testing for webhook and workflow automation modules.
"""

import pytest
from datetime import datetime, timedelta
from apps.integration.webhook_event_streaming import (
    WebhookEngine, Webhook, Event, EventType, EventFilter,
    WebhookStatus, EventDeliveryStatus, RetryPolicy, EventStream
)
from apps.integration.custom_workflows import (
    WorkflowEngine, Workflow, WorkflowStep, WorkflowAction,
    Trigger, TriggerType, ActionType, WorkflowStatus,
    ExecutionStatus
)


class TestWebhookArchitecture:
    """Test webhook engine functionality."""
    
    def test_register_webhook(self):
        """Test webhook registration."""
        engine = WebhookEngine()
        webhook = engine.register_webhook("https://example.com/webhook")
        
        assert webhook.url == "https://example.com/webhook"
        assert webhook.status == WebhookStatus.ACTIVE
        assert len(engine.webhooks) == 1
    
    def test_webhook_signature_verification(self):
        """Test HMAC signature generation and verification."""
        engine = WebhookEngine()
        webhook = engine.register_webhook("https://example.com/webhook")
        
        payload = '{"test": "data"}'
        signature = webhook.generate_signature(payload)
        
        assert webhook.verify_signature(payload, signature)
        assert not webhook.verify_signature(payload, "invalid_signature")
    
    def test_event_filtering(self):
        """Test event filter matching."""
        filter_obj = EventFilter(
            event_types=[EventType.ALERT_FIRED, EventType.ALERT_RESOLVED],
            resource_types=["database"]
        )
        
        # Matching event
        event1 = Event(
            type=EventType.ALERT_FIRED,
            data={"resource_type": "database"}
        )
        assert filter_obj.matches(event1)
        
        # Non-matching event
        event2 = Event(
            type=EventType.METRIC_RECORDED,
            data={"resource_type": "database"}
        )
        assert not filter_obj.matches(event2)
    
    def test_send_event_to_webhooks(self):
        """Test sending event to matching webhooks."""
        engine = WebhookEngine()
        
        # Register webhook
        webhook = engine.register_webhook("https://example.com/webhook")
        engine.register_delivery_handler(lambda w, p, s: True)
        
        # Send event
        event = Event(
            type=EventType.METRIC_RECORDED,
            data={"metric": "cpu_usage", "value": 85}
        )
        result = engine.send_event(event)
        
        assert result['event_id'] == event.id
        assert len(result['results']) > 0
        assert engine._stats['events_delivered'] > 0
    
    def test_webhook_retry_policy(self):
        """Test exponential backoff retry calculation."""
        policy = RetryPolicy(
            max_retries=3,
            initial_delay_seconds=5,
            backoff_multiplier=2.0
        )
        
        assert policy.get_retry_delay(0) == 5
        assert policy.get_retry_delay(1) == 10
        assert policy.get_retry_delay(2) == 20
    
    def test_replay_events(self):
        """Test event replay functionality."""
        engine = WebhookEngine()
        webhook = engine.register_webhook("https://example.com/webhook")
        engine.register_delivery_handler(lambda w, p, s: True)
        
        # Send events
        for _ in range(3):
            event = Event(type=EventType.METRIC_RECORDED)
            engine.send_event(event)
        
        # Replay events
        result = engine.replay_events(webhook.id)
        assert result['success']
        assert result['events_queued_for_replay'] >= 3


class TestWorkflowArchitecture:
    """Test workflow engine functionality."""
    
    def test_create_workflow(self):
        """Test workflow creation."""
        engine = WorkflowEngine()
        
        workflow = Workflow(
            name="Test Workflow",
            description="A test workflow"
        )
        engine.create_workflow(workflow)
        
        assert len(engine.workflows) == 1
        assert engine.get_workflow(workflow.id) == workflow
    
    def test_add_workflow_steps(self):
        """Test adding steps to workflow."""
        workflow = Workflow(name="Test Workflow")
        
        step1 = WorkflowStep(name="Step 1")
        step2 = WorkflowStep(name="Step 2")
        
        workflow.add_step(step1)
        workflow.add_step(step2)
        
        assert len(workflow.steps) == 2
        assert workflow.root_step_id == step1.id
    
    def test_workflow_validation(self):
        """Test workflow validation."""
        # Valid workflow
        workflow = Workflow(name="Valid Workflow")
        trigger = Trigger(type=TriggerType.MANUAL)
        step = WorkflowStep(name="Action")
        
        workflow.triggers.append(trigger)
        workflow.add_step(step)
        
        valid, errors = workflow.validate()
        assert valid
        assert len(errors) == 0
        
        # Invalid workflow
        invalid = Workflow(name="Invalid")
        valid, errors = invalid.validate()
        assert not valid
        assert len(errors) > 0
    
    def test_publish_workflow(self):
        """Test publishing a workflow."""
        engine = WorkflowEngine()
        
        workflow = Workflow(name="Test Workflow")
        workflow.triggers.append(Trigger(type=TriggerType.MANUAL))
        workflow.add_step(WorkflowStep(name="Action"))
        
        engine.create_workflow(workflow)
        success, error = engine.publish_workflow(workflow.id)
        
        assert success
        assert error is None
        assert workflow.status == WorkflowStatus.PUBLISHED
    
    def test_execute_workflow(self):
        """Test workflow execution."""
        engine = WorkflowEngine()
        
        # Create and setup workflow
        workflow = Workflow(name="Test Workflow")
        action = WorkflowAction(
            type=ActionType.SEND_NOTIFICATION,
            config={"channel": "slack", "message": "Alert triggered"}
        )
        step = WorkflowStep(name="Notify", action=action)
        
        workflow.triggers.append(Trigger(type=TriggerType.ALERT))
        workflow.add_step(step)
        
        engine.create_workflow(workflow)
        engine.publish_workflow(workflow.id)
        
        # Execute workflow
        execution = engine.execute_workflow(
            workflow.id,
            trigger_type=TriggerType.ALERT
        )
        
        assert execution.workflow_id == workflow.id
        assert execution.status == ExecutionStatus.COMPLETED
        assert len(execution.steps_executed) > 0
    
    def test_workflow_conditional_execution(self):
        """Test workflow step conditional execution."""
        step = WorkflowStep(
            name="Conditional Step",
            condition="context.get('severity') == 'critical'"
        )
        
        # Should execute
        context = {'severity': 'critical'}
        assert step.should_execute(context)
        
        # Should not execute
        context = {'severity': 'low'}
        assert not step.should_execute(context)
    
    def test_pause_resume_execution(self):
        """Test pausing and resuming workflow execution."""
        engine = WorkflowEngine()
        
        workflow = Workflow(name="Test")
        workflow.add_step(WorkflowStep(name="Step 1"))
        engine.create_workflow(workflow)
        engine.publish_workflow(workflow.id)
        
        execution = engine.execute_workflow(workflow.id)
        
        # Pause execution
        assert engine.pause_execution(execution.id)
        assert execution.status == ExecutionStatus.PAUSED
        
        # Resume execution
        assert engine.resume_execution(execution.id)
        assert execution.status == ExecutionStatus.RUNNING


class TestEventStreaming:
    """Test event stream functionality."""
    
    def test_event_stream_subscription(self):
        """Test subscribing to events."""
        engine = WebhookEngine()
        stream = EventStream(engine)
        
        events_received = []
        
        def callback(event):
            events_received.append(event)
        
        subscription_id = stream.subscribe(EventType.ALERT_FIRED, callback)
        
        # Emit event
        event = Event(type=EventType.ALERT_FIRED)
        stream.emit(event)
        
        assert len(events_received) == 1
        assert events_received[0].id == event.id
    
    def test_event_history_retrieval(self):
        """Test retrieving event history."""
        engine = WebhookEngine()
        stream = EventStream(engine)
        
        # Emit multiple events
        for _ in range(5):
            event = Event(type=EventType.METRIC_RECORDED)
            stream.emit(event)
        
        # Get history
        history = stream.get_history(limit=10)
        assert len(history) == 5
        
        # Filter by type
        history = stream.get_history(
            event_type=EventType.METRIC_RECORDED,
            limit=10
        )
        assert len(history) == 5


class TestPhase26CIntegration:
    """End-to-end integration tests for Phase 26C."""
    
    def test_webhook_triggered_workflow(self):
        """Test webhook triggering workflow execution."""
        webhook_engine = WebhookEngine()
        workflow_engine = WorkflowEngine()
        
        # Setup webhook
        webhook = webhook_engine.register_webhook("https://example.com/webhook")
        webhook_engine.register_delivery_handler(lambda w, p, s: True)
        
        # Setup workflow
        workflow = Workflow(
            name="Alert Response",
            description="Respond to alerts"
        )
        action = WorkflowAction(
            type=ActionType.CREATE_INCIDENT,
            config={"title": "Alert Incident"}
        )
        step = WorkflowStep(name="Create Incident", action=action)
        workflow.triggers.append(Trigger(
            type=TriggerType.WEBHOOK,
            config={"webhook_id": webhook.id}
        ))
        workflow.add_step(step)
        
        workflow_engine.create_workflow(workflow)
        workflow_engine.publish_workflow(workflow.id)
        
        # Send event via webhook
        event = Event(
            type=EventType.ALERT_FIRED,
            data={"alert_id": "alert-123"}
        )
        result = webhook_engine.send_event(event)
        
        # Execute workflow
        execution = workflow_engine.execute_workflow(
            workflow.id,
            trigger_type=TriggerType.WEBHOOK,
            trigger_data={"webhook_id": webhook.id}
        )
        
        assert execution.status == ExecutionStatus.COMPLETED
    
    def test_metric_threshold_trigger_workflow(self):
        """Test metric threshold triggering workflow."""
        engine = WorkflowEngine()
        
        # Create workflow with metric threshold trigger
        workflow = Workflow(name="High CPU Alert Response")
        trigger = Trigger(
            type=TriggerType.METRIC_THRESHOLD,
            config={"threshold": 80, "operator": ">"}
        )
        action = WorkflowAction(
            type=ActionType.SEND_NOTIFICATION,
            config={"channel": "slack"}
        )
        step = WorkflowStep(name="Alert", action=action)
        
        workflow.triggers.append(trigger)
        workflow.add_step(step)
        
        engine.create_workflow(workflow)
        engine.publish_workflow(workflow.id)
        
        # Execute with high metric value
        execution = engine.execute_workflow(
            workflow.id,
            trigger_type=TriggerType.METRIC_THRESHOLD,
            trigger_data={"value": 85}
        )
        
        assert execution.status == ExecutionStatus.COMPLETED
    
    def test_complex_workflow_statistics(self):
        """Test workflow statistics tracking."""
        workflow_engine = WorkflowEngine()
        webhook_engine = WebhookEngine()
        
        # Create and execute multiple workflows
        for i in range(5):
            workflow = Workflow(name=f"Workflow {i}")
            workflow.triggers.append(Trigger(type=TriggerType.MANUAL))
            workflow.add_step(WorkflowStep(name="Action"))
            
            workflow_engine.create_workflow(workflow)
            workflow_engine.publish_workflow(workflow.id)
            workflow_engine.execute_workflow(workflow.id)
        
        # Check statistics
        stats = workflow_engine.get_statistics()
        assert stats['workflows_created'] == 5
        assert stats['executions_completed'] == 5
        assert stats['running_executions'] == 0
        
        # Check webhook statistics
        for _ in range(3):
            webhook_engine.register_webhook("https://example.com/webhook")
        
        webhook_stats = webhook_engine.get_statistics()
        assert webhook_stats['webhooks_registered'] == 3


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
