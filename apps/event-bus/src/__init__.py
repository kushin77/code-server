#!/usr/bin/env python3
# @file apps/event-bus/src/__init__.py
# @module event-bus
# @description ElevatedIQ DevOS Event Bus library

from .producer import (
    EventProducer,
    EventEnvelope,
    DeployEventProducer,
    AgentEventProducer,
    AIEventProducer,
)

from .consumer import (
    EventConsumer,
    ActivityFeedConsumer,
    ReputationEngineConsumer,
    AuditLogConsumer,
    PaperclipConsumer,
)

__version__ = "1.0.0"
__all__ = [
    "EventProducer",
    "EventEnvelope",
    "DeployEventProducer",
    "AgentEventProducer",
    "AIEventProducer",
    "EventConsumer",
    "ActivityFeedConsumer",
    "ReputationEngineConsumer",
    "AuditLogConsumer",
    "PaperclipConsumer",
]
