"""
Webhook & Event Streaming Module (Phase 26C)

Provides real-time event export to external systems with:
- Webhook registration and management
- Reliable delivery with exponential backoff retry
- Event filtering and transformation
- Cryptographic signature verification
- Event replay capability
- Comprehensive event types

Part of Observability Platform v1.0.0
"""

import hashlib
import hmac
import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Callable, Dict, List, Optional, Tuple
from urllib.parse import urljoin


class EventType(Enum):
    """Platform event types for webhook delivery."""
    
    METRIC_RECORDED = "metric.recorded"
    ALERT_FIRED = "alert.fired"
    ALERT_RESOLVED = "alert.resolved"
    TRACE_COMPLETED = "trace.completed"
    RESOURCE_CREATED = "resource.created"
    RESOURCE_MODIFIED = "resource.modified"
    RESOURCE_DELETED = "resource.deleted"
    COMPLIANCE_ASSESSED = "compliance.assessed"


class WebhookStatus(Enum):
    """Webhook status values."""
    
    ACTIVE = "active"
    INACTIVE = "inactive"
    FAILED = "failed"
    SUSPENDED = "suspended"


class EventDeliveryStatus(Enum):
    """Event delivery status."""
    
    PENDING = "pending"
    DELIVERED = "delivered"
    FAILED = "failed"
    RETRYING = "retrying"


@dataclass
class RetryPolicy:
    """Retry configuration for webhook delivery."""
    
    max_retries: int = 5
    initial_delay_seconds: int = 5
    max_delay_seconds: int = 3600
    backoff_multiplier: float = 2.0
    
    def get_retry_delay(self, attempt: int) -> int:
        """Calculate retry delay for attempt (exponential backoff)."""
        delay = self.initial_delay_seconds * (self.backoff_multiplier ** attempt)
        return min(int(delay), self.max_delay_seconds)


@dataclass
class EventFilter:
    """Filter for webhook events."""
    
    event_types: List[EventType] = field(default_factory=list)
    resource_types: Optional[List[str]] = None
    severity_levels: Optional[List[str]] = None
    tags: Optional[Dict[str, str]] = None
    
    def matches(self, event: 'Event') -> bool:
        """Check if event matches filter criteria."""
        # Check event type
        if self.event_types and event.type not in self.event_types:
            return False
        
        # Check resource type
        if self.resource_types:
            event_resource = event.data.get('resource_type')
            if event_resource not in self.resource_types:
                return False
        
        # Check severity
        if self.severity_levels:
            event_severity = event.data.get('severity')
            if event_severity not in self.severity_levels:
                return False
        
        # Check tags
        if self.tags:
            event_tags = event.data.get('tags', {})
            for key, value in self.tags.items():
                if event_tags.get(key) != value:
                    return False
        
        return True


@dataclass
class Event:
    """Webhook event wrapper."""
    
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    type: EventType = EventType.METRIC_RECORDED
    timestamp: datetime = field(default_factory=datetime.utcnow)
    data: Dict[str, Any] = field(default_factory=dict)
    source: str = "observability-platform"
    version: str = "1.0"
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert event to dictionary."""
        return {
            'id': self.id,
            'type': self.type.value,
            'timestamp': self.timestamp.isoformat(),
            'data': self.data,
            'source': self.source,
            'version': self.version
        }


@dataclass
class EventDelivery:
    """Record of event delivery attempt."""
    
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    webhook_id: str = ""
    event_id: str = ""
    status: EventDeliveryStatus = EventDeliveryStatus.PENDING
    attempt: int = 1
    response_status: int = 0
    response_body: str = ""
    timestamp: datetime = field(default_factory=datetime.utcnow)
    next_retry: Optional[datetime] = None
    error_message: Optional[str] = None


@dataclass
class Webhook:
    """Webhook registration."""
    
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    url: str = ""
    status: WebhookStatus = WebhookStatus.ACTIVE
    event_filter: EventFilter = field(default_factory=EventFilter)
    secret: str = field(default_factory=lambda: str(uuid.uuid4()))
    retry_policy: RetryPolicy = field(default_factory=RetryPolicy)
    rate_limit: int = 1000  # events per hour
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    last_delivery: Optional[datetime] = None
    delivery_count: int = 0
    failure_count: int = 0
    
    def verify_signature(self, payload: str, signature: str) -> bool:
        """Verify HMAC-SHA256 signature."""
        expected_signature = hmac.new(
            self.secret.encode(),
            payload.encode(),
            hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(signature, expected_signature)
    
    def generate_signature(self, payload: str) -> str:
        """Generate HMAC-SHA256 signature."""
        return hmac.new(
            self.secret.encode(),
            payload.encode(),
            hashlib.sha256
        ).hexdigest()


class WebhookEngine:
    """Central webhook orchestration engine."""
    
    def __init__(self):
        """Initialize webhook engine."""
        self.webhooks: Dict[str, Webhook] = {}
        self.deliveries: Dict[str, EventDelivery] = {}
        self.event_queue: List[Tuple[Event, str]] = []  # (event, webhook_id) pairs
        self.delivery_handlers: List[Callable] = []
        self._stats = {
            'webhooks_registered': 0,
            'events_delivered': 0,
            'delivery_failures': 0,
            'events_replayed': 0
        }
    
    def register_webhook(
        self,
        url: str,
        event_filter: Optional[EventFilter] = None,
        retry_policy: Optional[RetryPolicy] = None
    ) -> Webhook:
        """Register a new webhook."""
        webhook = Webhook(
            url=url,
            event_filter=event_filter or EventFilter(
                event_types=list(EventType)  # All events by default
            ),
            retry_policy=retry_policy or RetryPolicy()
        )
        self.webhooks[webhook.id] = webhook
        self._stats['webhooks_registered'] += 1
        return webhook
    
    def unregister_webhook(self, webhook_id: str) -> bool:
        """Unregister a webhook."""
        if webhook_id in self.webhooks:
            del self.webhooks[webhook_id]
            return True
        return False
    
    def update_webhook(
        self,
        webhook_id: str,
        **kwargs
    ) -> Optional[Webhook]:
        """Update webhook configuration."""
        if webhook_id not in self.webhooks:
            return None
        
        webhook = self.webhooks[webhook_id]
        for key, value in kwargs.items():
            if hasattr(webhook, key):
                setattr(webhook, key, value)
        webhook.updated_at = datetime.utcnow()
        return webhook
    
    def get_webhook(self, webhook_id: str) -> Optional[Webhook]:
        """Get webhook by ID."""
        return self.webhooks.get(webhook_id)
    
    def list_webhooks(
        self,
        status: Optional[WebhookStatus] = None
    ) -> List[Webhook]:
        """List registered webhooks."""
        if status is None:
            return list(self.webhooks.values())
        return [w for w in self.webhooks.values() if w.status == status]
    
    def send_event(self, event: Event) -> Dict[str, Any]:
        """Send event to all matching webhooks."""
        results = {}
        
        for webhook_id, webhook in self.webhooks.items():
            if webhook.status != WebhookStatus.ACTIVE:
                continue
            
            # Check filter match
            if not webhook.event_filter.matches(event):
                continue
            
            # Queue delivery
            delivery = EventDelivery(
                webhook_id=webhook_id,
                event_id=event.id,
                status=EventDeliveryStatus.PENDING
            )
            self.deliveries[delivery.id] = delivery
            
            # Attempt immediate delivery
            success = self._attempt_delivery(webhook, event, delivery)
            results[webhook_id] = {
                'delivery_id': delivery.id,
                'success': success,
                'status': delivery.status.value
            }
            
            if success:
                self._stats['events_delivered'] += 1
                webhook.delivery_count += 1
                webhook.last_delivery = datetime.utcnow()
        
        return {
            'event_id': event.id,
            'results': results,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def _attempt_delivery(
        self,
        webhook: Webhook,
        event: Event,
        delivery: EventDelivery
    ) -> bool:
        """Attempt to deliver event to webhook."""
        try:
            payload = json.dumps(event.to_dict())
            signature = webhook.generate_signature(payload)
            
            # Call registered delivery handlers
            for handler in self.delivery_handlers:
                success = handler(webhook, payload, signature)
                if success:
                    delivery.status = EventDeliveryStatus.DELIVERED
                    delivery.response_status = 200
                    return True
                else:
                    delivery.status = EventDeliveryStatus.FAILED
                    delivery.attempt += 1
                    if delivery.attempt <= webhook.retry_policy.max_retries:
                        delay = webhook.retry_policy.get_retry_delay(
                            delivery.attempt - 1
                        )
                        delivery.next_retry = datetime.utcnow() + timedelta(
                            seconds=delay
                        )
                        delivery.status = EventDeliveryStatus.RETRYING
            
            return delivery.status == EventDeliveryStatus.DELIVERED
        except Exception as e:
            delivery.error_message = str(e)
            delivery.status = EventDeliveryStatus.FAILED
            self._stats['delivery_failures'] += 1
            return False
    
    def register_delivery_handler(
        self,
        handler: Callable[[Webhook, str, str], bool]
    ) -> None:
        """Register a delivery handler (for testing/integration)."""
        self.delivery_handlers.append(handler)
    
    def replay_events(
        self,
        webhook_id: str,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """Replay historical events to webhook."""
        webhook = self.webhooks.get(webhook_id)
        if not webhook:
            return {'success': False, 'error': 'Webhook not found'}
        
        # Filter deliveries by time range
        replay_count = 0
        for delivery in self.deliveries.values():
            if delivery.webhook_id != webhook_id:
                continue
            
            if start_time and delivery.timestamp < start_time:
                continue
            if end_time and delivery.timestamp > end_time:
                continue
            
            # Mark for replay
            delivery.status = EventDeliveryStatus.PENDING
            delivery.attempt = 1
            replay_count += 1
        
        self._stats['events_replayed'] += replay_count
        return {
            'success': True,
            'webhook_id': webhook_id,
            'events_queued_for_replay': replay_count,
            'start_time': start_time.isoformat() if start_time else None,
            'end_time': end_time.isoformat() if end_time else None
        }
    
    def get_delivery_status(self, delivery_id: str) -> Optional[Dict[str, Any]]:
        """Get status of specific event delivery."""
        delivery = self.deliveries.get(delivery_id)
        if not delivery:
            return None
        
        return {
            'id': delivery.id,
            'webhook_id': delivery.webhook_id,
            'event_id': delivery.event_id,
            'status': delivery.status.value,
            'attempt': delivery.attempt,
            'response_status': delivery.response_status,
            'error_message': delivery.error_message,
            'timestamp': delivery.timestamp.isoformat(),
            'next_retry': delivery.next_retry.isoformat() if delivery.next_retry else None
        }
    
    def list_deliveries(
        self,
        webhook_id: Optional[str] = None,
        status: Optional[EventDeliveryStatus] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """List event deliveries."""
        deliveries = list(self.deliveries.values())
        
        if webhook_id:
            deliveries = [d for d in deliveries if d.webhook_id == webhook_id]
        
        if status:
            deliveries = [d for d in deliveries if d.status == status]
        
        # Sort by timestamp descending and limit
        deliveries.sort(key=lambda d: d.timestamp, reverse=True)
        
        return [
            {
                'id': d.id,
                'webhook_id': d.webhook_id,
                'event_id': d.event_id,
                'status': d.status.value,
                'timestamp': d.timestamp.isoformat()
            }
            for d in deliveries[:limit]
        ]
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get webhook engine statistics."""
        active_webhooks = len([w for w in self.webhooks.values()
                               if w.status == WebhookStatus.ACTIVE])
        pending_deliveries = len([d for d in self.deliveries.values()
                                  if d.status == EventDeliveryStatus.PENDING])
        failed_deliveries = len([d for d in self.deliveries.values()
                                 if d.status == EventDeliveryStatus.FAILED])
        
        return {
            'webhooks_registered': self._stats['webhooks_registered'],
            'active_webhooks': active_webhooks,
            'total_webhooks': len(self.webhooks),
            'events_delivered': self._stats['events_delivered'],
            'delivery_failures': self._stats['delivery_failures'],
            'events_replayed': self._stats['events_replayed'],
            'pending_deliveries': pending_deliveries,
            'failed_deliveries': failed_deliveries,
            'total_deliveries': len(self.deliveries)
        }


class EventStream:
    """Continuous event stream for real-time processing."""
    
    def __init__(self, webhook_engine: WebhookEngine):
        """Initialize event stream."""
        self.engine = webhook_engine
        self.subscribers: Dict[str, List[Callable]] = {}
        self.event_history: List[Event] = []
        self.max_history_size: int = 10000
    
    def subscribe(
        self,
        event_type: EventType,
        callback: Callable[[Event], None]
    ) -> str:
        """Subscribe to event type."""
        key = event_type.value
        if key not in self.subscribers:
            self.subscribers[key] = []
        
        self.subscribers[key].append(callback)
        return f"{key}:{id(callback)}"
    
    def unsubscribe(self, subscription_id: str) -> bool:
        """Unsubscribe from event type."""
        event_type, callback_id = subscription_id.split(':')
        if event_type in self.subscribers:
            self.subscribers[event_type] = [
                cb for cb in self.subscribers[event_type]
                if str(id(cb)) != callback_id
            ]
            return True
        return False
    
    def emit(self, event: Event) -> None:
        """Emit event to subscribers and webhook engine."""
        # Add to history
        self.event_history.append(event)
        if len(self.event_history) > self.max_history_size:
            self.event_history.pop(0)
        
        # Notify subscribers
        key = event.type.value
        if key in self.subscribers:
            for callback in self.subscribers[key]:
                try:
                    callback(event)
                except Exception:
                    pass  # Ignore callback errors
        
        # Send through webhook engine
        self.engine.send_event(event)
    
    def get_history(
        self,
        event_type: Optional[EventType] = None,
        limit: int = 100
    ) -> List[Event]:
        """Get event history."""
        if event_type is None:
            return self.event_history[-limit:]
        
        filtered = [e for e in self.event_history if e.type == event_type]
        return filtered[-limit:]
