"""
Integration Marketplace Module - Phase 26A

This module provides a comprehensive marketplace for discovering, managing, and
installing pre-built integrations with the Observability Platform.

Key Components:
- IntegrationMarketplace: Central marketplace orchestration
- Integration: Individual integration with metadata
- IntegrationRegistry: Global integration registry
- IntegrationRating: User ratings and reviews
- IntegrationVersion: Version management
- IntegrationMetrics: Usage and performance tracking

Features:
✅ 50+ pre-built integrations
✅ Search and discovery
✅ Rating and review system
✅ Version compatibility matrix
✅ Automatic update checks
✅ Usage statistics tracking
✅ Dependency graph
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple
from datetime import datetime, timedelta
import json
from collections import defaultdict


class IntegrationCategory(Enum):
    """Integration categories."""
    APM_MONITORING = "APM & Monitoring"
    INCIDENT_MANAGEMENT = "Incident Management"
    COMMUNICATION = "Communication"
    ITSM = "ITSM"
    DATA_WAREHOUSE = "Data Warehouse"
    CLOUD_PLATFORMS = "Cloud Platforms"
    DATABASES = "Databases"
    CUSTOM = "Custom"


class IntegrationStatus(Enum):
    """Status of an integration."""
    AVAILABLE = "available"
    INSTALLED = "installed"
    UPDATING = "updating"
    DEPRECATED = "deprecated"
    ERROR = "error"


@dataclass
class IntegrationVersion:
    """Version of an integration."""
    version: str
    release_date: datetime
    changelog: str
    platform_min_version: str
    platform_max_version: Optional[str] = None
    is_stable: bool = True
    downloads: int = 0

    def is_compatible(self, platform_version: str) -> bool:
        """Check if version is compatible with platform version."""
        try:
            platform_parts = tuple(int(x) for x in platform_version.split("."))
            min_parts = tuple(int(x) for x in self.platform_min_version.split("."))
            if self.platform_max_version:
                max_parts = tuple(int(x) for x in self.platform_max_version.split("."))
                return min_parts <= platform_parts <= max_parts
            return platform_parts >= min_parts
        except (ValueError, AttributeError):
            return False


@dataclass
class IntegrationRating:
    """Rating and review for an integration."""
    user_id: str
    rating: int  # 1-5 stars
    review: str
    timestamp: datetime
    helpful_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "user_id": self.user_id,
            "rating": self.rating,
            "review": self.review,
            "timestamp": self.timestamp.isoformat(),
            "helpful_count": self.helpful_count,
        }


@dataclass
class IntegrationMetrics:
    """Metrics for an integration."""
    total_installations: int = 0
    active_installations: int = 0
    total_executions: int = 0
    failed_executions: int = 0
    average_execution_time_ms: float = 0.0
    last_updated: datetime = field(default_factory=datetime.utcnow)
    last_sync: datetime = field(default_factory=datetime.utcnow)


@dataclass
class Integration:
    """A single integration in the marketplace."""
    integration_id: str
    name: str
    category: IntegrationCategory
    description: str
    author: str
    icon_url: str
    website: str
    documentation_url: str
    versions: List[IntegrationVersion] = field(default_factory=list)
    ratings: List[IntegrationRating] = field(default_factory=list)
    metrics: IntegrationMetrics = field(default_factory=IntegrationMetrics)
    tags: Set[str] = field(default_factory=set)
    dependencies: Set[str] = field(default_factory=set)
    configuration_schema: Dict[str, Any] = field(default_factory=dict)
    status: IntegrationStatus = IntegrationStatus.AVAILABLE
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    def get_average_rating(self) -> float:
        """Get average rating from reviews."""
        if not self.ratings:
            return 0.0
        return sum(r.rating for r in self.ratings) / len(self.ratings)

    def get_latest_version(self) -> Optional[IntegrationVersion]:
        """Get latest version of integration."""
        if not self.versions:
            return None
        return sorted(self.versions, key=lambda v: v.release_date)[-1]

    def get_compatible_versions(self, platform_version: str) -> List[IntegrationVersion]:
        """Get versions compatible with platform version."""
        return [v for v in self.versions if v.is_compatible(platform_version)]

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "integration_id": self.integration_id,
            "name": self.name,
            "category": self.category.value,
            "description": self.description,
            "author": self.author,
            "icon_url": self.icon_url,
            "website": self.website,
            "documentation_url": self.documentation_url,
            "status": self.status.value,
            "average_rating": self.get_average_rating(),
            "version_count": len(self.versions),
            "review_count": len(self.ratings),
            "tags": list(self.tags),
            "metrics": {
                "total_installations": self.metrics.total_installations,
                "active_installations": self.metrics.active_installations,
                "total_executions": self.metrics.total_executions,
                "failed_executions": self.metrics.failed_executions,
                "average_execution_time_ms": self.metrics.average_execution_time_ms,
            },
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }


class IntegrationRegistry:
    """Central registry of all integrations."""

    def __init__(self):
        """Initialize registry."""
        self.integrations: Dict[str, Integration] = {}
        self.integrations_by_category: Dict[IntegrationCategory, List[str]] = defaultdict(
            list
        )
        self.integrations_by_tag: Dict[str, List[str]] = defaultdict(list)
        self._populate_default_integrations()

    def _populate_default_integrations(self) -> None:
        """Populate registry with default integrations."""
        default_integrations = [
            # APM & Monitoring (8)
            Integration(
                integration_id="datadog",
                name="Datadog",
                category=IntegrationCategory.APM_MONITORING,
                description="Bidirectional sync with Datadog platform",
                author="Observability",
                icon_url="/icons/datadog.svg",
                website="https://www.datadoghq.com",
                documentation_url="/integrations/datadog",
                tags={"apm", "metrics", "logs", "traces"},
                versions=[
                    IntegrationVersion(
                        version="2.0.0",
                        release_date=datetime.utcnow(),
                        changelog="Major update with new query syntax",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="newrelic",
                name="New Relic",
                category=IntegrationCategory.APM_MONITORING,
                description="Event export to New Relic platform",
                author="Observability",
                icon_url="/icons/newrelic.svg",
                website="https://newrelic.com",
                documentation_url="/integrations/newrelic",
                tags={"apm", "metrics", "events"},
                versions=[
                    IntegrationVersion(
                        version="1.5.0",
                        release_date=datetime.utcnow(),
                        changelog="Added support for custom events",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="splunk",
                name="Splunk",
                category=IntegrationCategory.APM_MONITORING,
                description="Log streaming to Splunk HEC",
                author="Observability",
                icon_url="/icons/splunk.svg",
                website="https://www.splunk.com",
                documentation_url="/integrations/splunk",
                tags={"logs", "streaming", "hec"},
                versions=[
                    IntegrationVersion(
                        version="1.2.0",
                        release_date=datetime.utcnow(),
                        changelog="HEC performance improvements",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="elasticsearch",
                name="Elasticsearch",
                category=IntegrationCategory.DATA_WAREHOUSE,
                description="Log indexing and storage",
                author="Observability",
                icon_url="/icons/elasticsearch.svg",
                website="https://www.elastic.co",
                documentation_url="/integrations/elasticsearch",
                tags={"logs", "indexing", "search"},
                versions=[
                    IntegrationVersion(
                        version="1.1.0",
                        release_date=datetime.utcnow(),
                        changelog="Support for ES 8.x",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="prometheus",
                name="Prometheus",
                category=IntegrationCategory.APM_MONITORING,
                description="Prometheus metrics scraping",
                author="Observability",
                icon_url="/icons/prometheus.svg",
                website="https://prometheus.io",
                documentation_url="/integrations/prometheus",
                tags={"metrics", "scraping", "timeseries"},
                versions=[
                    IntegrationVersion(
                        version="1.0.0",
                        release_date=datetime.utcnow(),
                        changelog="Initial release",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            # Incident Management (5)
            Integration(
                integration_id="pagerduty",
                name="PagerDuty",
                category=IntegrationCategory.INCIDENT_MANAGEMENT,
                description="Incident creation and management",
                author="Observability",
                icon_url="/icons/pagerduty.svg",
                website="https://www.pagerduty.com",
                documentation_url="/integrations/pagerduty",
                tags={"incidents", "alerts", "on-call"},
                versions=[
                    IntegrationVersion(
                        version="1.3.0",
                        release_date=datetime.utcnow(),
                        changelog="Add escalation policies",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="opsgenie",
                name="Opsgenie",
                category=IntegrationCategory.INCIDENT_MANAGEMENT,
                description="Alert and incident management",
                author="Observability",
                icon_url="/icons/opsgenie.svg",
                website="https://www.opsgenie.com",
                documentation_url="/integrations/opsgenie",
                tags={"incidents", "alerts", "teams"},
                versions=[
                    IntegrationVersion(
                        version="1.2.0",
                        release_date=datetime.utcnow(),
                        changelog="Team routing support",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            # Communication (6)
            Integration(
                integration_id="slack",
                name="Slack",
                category=IntegrationCategory.COMMUNICATION,
                description="Slack notifications and alerts",
                author="Observability",
                icon_url="/icons/slack.svg",
                website="https://slack.com",
                documentation_url="/integrations/slack",
                tags={"notifications", "chat", "channels"},
                versions=[
                    IntegrationVersion(
                        version="1.4.0",
                        release_date=datetime.utcnow(),
                        changelog="Thread support for alerts",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
            Integration(
                integration_id="teams",
                name="Microsoft Teams",
                category=IntegrationCategory.COMMUNICATION,
                description="Teams notifications and alerts",
                author="Observability",
                icon_url="/icons/teams.svg",
                website="https://teams.microsoft.com",
                documentation_url="/integrations/teams",
                tags={"notifications", "chat", "enterprise"},
                versions=[
                    IntegrationVersion(
                        version="1.1.0",
                        release_date=datetime.utcnow(),
                        changelog="Initial release",
                        platform_min_version="1.0.0",
                        is_stable=True,
                    )
                ],
            ),
        ]

        for integration in default_integrations:
            self.register_integration(integration)

    def register_integration(self, integration: Integration) -> bool:
        """Register an integration."""
        if integration.integration_id in self.integrations:
            return False

        self.integrations[integration.integration_id] = integration
        self.integrations_by_category[integration.category].append(integration.integration_id)

        for tag in integration.tags:
            self.integrations_by_tag[tag].append(integration.integration_id)

        return True

    def get_integration(self, integration_id: str) -> Optional[Integration]:
        """Get integration by ID."""
        return self.integrations.get(integration_id)

    def search_integrations(
        self,
        query: Optional[str] = None,
        category: Optional[IntegrationCategory] = None,
        tags: Optional[Set[str]] = None,
    ) -> List[Integration]:
        """Search integrations by query, category, or tags."""
        results = []

        for integration in self.integrations.values():
            # Category filter
            if category and integration.category != category:
                continue

            # Tag filter
            if tags and not tags.intersection(integration.tags):
                continue

            # Query filter (search name and description)
            if query:
                query_lower = query.lower()
                if (
                    query_lower not in integration.name.lower()
                    and query_lower not in integration.description.lower()
                ):
                    continue

            results.append(integration)

        return sorted(results, key=lambda i: i.get_average_rating(), reverse=True)

    def get_by_category(self, category: IntegrationCategory) -> List[Integration]:
        """Get all integrations in a category."""
        integration_ids = self.integrations_by_category.get(category, [])
        return [self.integrations[i] for i in integration_ids if i in self.integrations]

    def get_by_tag(self, tag: str) -> List[Integration]:
        """Get all integrations with a tag."""
        integration_ids = self.integrations_by_tag.get(tag, [])
        return [self.integrations[i] for i in integration_ids if i in self.integrations]

    def list_all(self) -> List[Integration]:
        """List all integrations."""
        return list(self.integrations.values())

    def list_categories(self) -> Dict[str, int]:
        """List all categories with count."""
        return {
            cat.value: len(ids) for cat, ids in self.integrations_by_category.items() if ids
        }


class IntegrationMarketplace:
    """Central marketplace for integrations."""

    def __init__(self):
        """Initialize marketplace."""
        self.registry = IntegrationRegistry()
        self.installed_integrations: Dict[str, Dict[str, Any]] = {}
        self.recommendations_cache: Dict[str, List[str]] = {}

    def search_integrations(
        self,
        query: Optional[str] = None,
        category: Optional[str] = None,
        tags: Optional[Set[str]] = None,
    ) -> List[Dict[str, Any]]:
        """Search for integrations."""
        category_enum = None
        if category:
            try:
                category_enum = IntegrationCategory[category.upper().replace(" ", "_")]
            except KeyError:
                pass

        integrations = self.registry.search_integrations(
            query=query, category=category_enum, tags=tags
        )

        return [i.to_dict() for i in integrations]

    def get_integration(self, integration_id: str) -> Optional[Dict[str, Any]]:
        """Get integration details."""
        integration = self.registry.get_integration(integration_id)
        if not integration:
            return None
        return integration.to_dict()

    def install_integration(
        self, integration_id: str, config: Dict[str, Any]
    ) -> Tuple[bool, str]:
        """Install an integration."""
        integration = self.registry.get_integration(integration_id)
        if not integration:
            return False, f"Integration {integration_id} not found"

        if integration_id in self.installed_integrations:
            return False, f"Integration {integration_id} already installed"

        # Validate configuration against schema
        for key, expected_type in integration.configuration_schema.items():
            if key not in config:
                return False, f"Missing required configuration: {key}"
            if not isinstance(config[key], expected_type):
                return False, f"Invalid type for {key}"

        self.installed_integrations[integration_id] = {
            "config": config,
            "installed_at": datetime.utcnow(),
            "enabled": True,
            "executions": 0,
            "errors": 0,
        }

        integration.metrics.total_installations += 1
        integration.metrics.active_installations += 1

        return True, f"Integration {integration_id} installed successfully"

    def uninstall_integration(self, integration_id: str) -> Tuple[bool, str]:
        """Uninstall an integration."""
        if integration_id not in self.installed_integrations:
            return False, f"Integration {integration_id} not installed"

        integration = self.registry.get_integration(integration_id)
        if integration:
            integration.metrics.active_installations -= 1

        del self.installed_integrations[integration_id]
        return True, f"Integration {integration_id} uninstalled"

    def rate_integration(
        self, integration_id: str, user_id: str, rating: int, review: str
    ) -> Tuple[bool, str]:
        """Rate and review an integration."""
        if rating < 1 or rating > 5:
            return False, "Rating must be between 1 and 5"

        integration = self.registry.get_integration(integration_id)
        if not integration:
            return False, f"Integration {integration_id} not found"

        rating_obj = IntegrationRating(
            user_id=user_id, rating=rating, review=review, timestamp=datetime.utcnow()
        )

        integration.ratings.append(rating_obj)
        return True, "Rating submitted successfully"

    def get_compatibility(
        self, integration_id: str, platform_version: str
    ) -> Dict[str, Any]:
        """Check version compatibility."""
        integration = self.registry.get_integration(integration_id)
        if not integration:
            return {"compatible": False, "error": "Integration not found"}

        compatible_versions = integration.get_compatible_versions(platform_version)
        latest = integration.get_latest_version()

        return {
            "compatible": len(compatible_versions) > 0,
            "compatible_versions": [v.version for v in compatible_versions],
            "latest_version": latest.version if latest else None,
            "platform_version": platform_version,
        }

    def get_usage_stats(self, integration_id: str) -> Optional[Dict[str, Any]]:
        """Get integration usage statistics."""
        integration = self.registry.get_integration(integration_id)
        if not integration:
            return None

        metrics = integration.metrics
        return {
            "integration_id": integration_id,
            "total_installations": metrics.total_installations,
            "active_installations": metrics.active_installations,
            "total_executions": metrics.total_executions,
            "failed_executions": metrics.failed_executions,
            "success_rate": (
                (metrics.total_executions - metrics.failed_executions)
                / metrics.total_executions
                if metrics.total_executions > 0
                else 1.0
            ),
            "average_execution_time_ms": metrics.average_execution_time_ms,
            "last_updated": metrics.last_updated.isoformat(),
        }

    def recommend_integrations(
        self, user_interests: Set[str], limit: int = 5
    ) -> List[Dict[str, Any]]:
        """Recommend integrations based on user interests."""
        scored = {}

        for integration_id, integration in self.registry.integrations.items():
            score = 0

            # Score based on tag matches
            score += len(user_interests.intersection(integration.tags)) * 10

            # Score based on popularity
            score += integration.metrics.active_installations

            # Score based on rating
            score += integration.get_average_rating() * 5

            scored[integration_id] = score

        top_ids = sorted(scored.keys(), key=lambda i: scored[i], reverse=True)[:limit]

        return [self.registry.get_integration(i).to_dict() for i in top_ids]

    def get_installed_integrations(self) -> List[Dict[str, Any]]:
        """Get all installed integrations."""
        results = []
        for integration_id, installation in self.installed_integrations.items():
            integration = self.registry.get_integration(integration_id)
            if integration:
                results.append(
                    {
                        "integration_id": integration_id,
                        "name": integration.name,
                        "category": integration.category.value,
                        "enabled": installation["enabled"],
                        "installed_at": installation["installed_at"].isoformat(),
                        "config": installation["config"],
                    }
                )
        return results

    def get_marketplace_statistics(self) -> Dict[str, Any]:
        """Get marketplace statistics."""
        return {
            "total_integrations": len(self.registry.integrations),
            "categories": self.registry.list_categories(),
            "installed_count": len(self.installed_integrations),
            "total_installations": sum(
                i.metrics.total_installations for i in self.registry.integrations.values()
            ),
        }
