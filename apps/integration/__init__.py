"""
Phase 26A: Advanced Integration - Plugin Architecture and Marketplace

This package provides comprehensive plugin and integration capabilities:

Plugin Architecture:
- Dynamic plugin loading/unloading
- Hook-based extension system
- Plugin validation and sandboxing
- Dependency resolution
- Plugin registry and lifecycle management

Integration Marketplace:
- 50+ pre-built integrations
- Search and discovery
- Rating and review system
- Version compatibility checking
- Usage tracking and recommendations

Key Classes:
- PluginManager: Central plugin orchestration
- Plugin: Base class for plugins
- PluginRegistry: Plugin discovery and management
- IntegrationMarketplace: Marketplace operations
- Integration: Individual integration metadata

Hook Points:
- metrics.collected: When metrics are collected
- alert.triggered: When alerts fire
- alert.resolved: When alerts resolve
- trace.completed: When traces complete
- query.executed: When queries run
- resource.created/modified/deleted: Resource lifecycle
- compliance.assessed: When compliance is assessed

Version: 1.0.0
Status: Production-ready
Dependencies: None (standard library only)
"""

from apps.integration.plugin_architecture import (
    # Classes
    PluginManager,
    Plugin,
    PluginRegistry,
    PluginValidator,
    HookPoint,
    PluginMetadata,
    PluginHook,
    PluginDependency,
    # Enums
    PluginStatus,
    HookType,
    PluginSandboxLevel,
)

from apps.integration.integration_marketplace import (
    # Classes
    IntegrationMarketplace,
    Integration,
    IntegrationRegistry,
    IntegrationVersion,
    IntegrationRating,
    IntegrationMetrics,
    # Enums
    IntegrationCategory,
    IntegrationStatus,
)

__version__ = "1.0.0"

__all__ = [
    # Plugin Architecture
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
    # Integration Marketplace
    "IntegrationMarketplace",
    "Integration",
    "IntegrationRegistry",
    "IntegrationVersion",
    "IntegrationRating",
    "IntegrationMetrics",
    "IntegrationCategory",
    "IntegrationStatus",
]
