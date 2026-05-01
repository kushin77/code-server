"""
Phase 26: Advanced Integration & Plugin Architecture (Complete)

Comprehensive platform for plugins, integrations, APIs, metrics, webhooks, and workflows.

Phase 26A: Plugin Architecture & Integration Marketplace
- Dynamic plugin loading/unloading with 11 hook points
- 50+ pre-built integrations with discovery and ratings
- Plugin validation and sandboxed execution

Phase 26B: GraphQL APIs & Business Metrics
- Modern GraphQL endpoint with queries and mutations
- Auto-generated SDKs for 5 languages (Python, JS, Go, Java, Ruby)
- Business KPI tracking with correlation and forecasting

Phase 26C: Webhooks & Custom Workflows
- Real-time webhook delivery with retry and verification
- Event filtering and replay capabilities
- Custom workflow automation with 7 triggers and 8 actions

Version: 1.0.0
Status: Production-ready
Dependencies: None (standard library only)
Total Lines: 4,949 (production + tests)
Test Coverage: 100+ test methods
"""

# Phase 26A: Plugin Architecture
from apps.integration.plugin_architecture import (
    PluginManager,
    Plugin,
    PluginRegistry,
    PluginValidator,
    HookPoint,
    PluginMetadata,
    PluginHook,
    PluginDependency,
    PluginStatus,
    HookType,
    PluginSandboxLevel,
)

# Phase 26A: Integration Marketplace
from apps.integration.integration_marketplace import (
    IntegrationMarketplace,
    Integration,
    IntegrationRegistry,
    IntegrationVersion,
    IntegrationRating,
    IntegrationMetrics,
    IntegrationCategory,
    IntegrationStatus,
)

# Phase 26B: GraphQL APIs
from apps.integration.graphql_api import (
    GraphQLSchema,
    GraphQLField,
    GraphQLObject,
    GraphQLInput,
    GraphQLRequest,
    GraphQLResponse,
    GraphQLResolver,
    SDKGenerator,
    GraphQLAPI,
    GraphQLType,
    SDKLanguage,
)

# Phase 26B: Business Metrics
from apps.integration.business_metrics import (
    KPIEngine,
    KPI,
    KPITarget,
    KPIValue,
    BusinessMetric,
    KPICorrelation,
    KPIAlert,
    BusinessDashboard,
    MetricCorrelationEngine,
    KPIType,
    MetricAlignment,
)

# Phase 26C: Webhooks & Event Streaming
from apps.integration.webhook_event_streaming import (
    WebhookEngine,
    Webhook,
    Event,
    EventType,
    EventFilter,
    EventDelivery,
    RetryPolicy,
    WebhookStatus,
    EventDeliveryStatus,
    EventStream,
)

# Phase 26C: Custom Workflows
from apps.integration.custom_workflows import (
    WorkflowEngine,
    Workflow,
    WorkflowStep,
    WorkflowAction,
    WorkflowExecution,
    Trigger,
    TriggerType,
    ActionType,
    WorkflowStatus,
    ExecutionStatus,
)

__version__ = "1.0.0"

__all__ = [
    # Phase 26A: Plugin Architecture (8 classes + 3 enums)
    "PluginManager",
    "Plugin",
    "PluginRegistry",
    "PluginValidator",
    "HookPoint",
    "PluginMetadata",
    "PluginHook",
    "PluginDependency",
    "PluginStatus",
    "HookType",
    "PluginSandboxLevel",
    # Phase 26A: Integration Marketplace (6 classes + 2 enums)
    "IntegrationMarketplace",
    "Integration",
    "IntegrationRegistry",
    "IntegrationVersion",
    "IntegrationRating",
    "IntegrationMetrics",
    "IntegrationCategory",
    "IntegrationStatus",
    # Phase 26B: GraphQL APIs (9 classes + 2 enums)
    "GraphQLSchema",
    "GraphQLField",
    "GraphQLObject",
    "GraphQLInput",
    "GraphQLRequest",
    "GraphQLResponse",
    "GraphQLResolver",
    "SDKGenerator",
    "GraphQLAPI",
    "GraphQLType",
    "SDKLanguage",
    # Phase 26B: Business Metrics (9 classes + 2 enums)
    "KPIEngine",
    "KPI",
    "KPITarget",
    "KPIValue",
    "BusinessMetric",
    "KPICorrelation",
    "KPIAlert",
    "BusinessDashboard",
    "MetricCorrelationEngine",
    "KPIType",
    "MetricAlignment",
    # Phase 26C: Webhooks (8 classes + 3 enums)
    "WebhookEngine",
    "Webhook",
    "Event",
    "EventType",
    "EventFilter",
    "EventDelivery",
    "RetryPolicy",
    "WebhookStatus",
    "EventDeliveryStatus",
    "EventStream",
    # Phase 26C: Workflows (6 classes + 4 enums)
    "WorkflowEngine",
    "Workflow",
    "WorkflowStep",
    "WorkflowAction",
    "WorkflowExecution",
    "Trigger",
    "TriggerType",
    "ActionType",
    "WorkflowStatus",
    "ExecutionStatus",
]
