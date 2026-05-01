"""
Phase 26A Integration Tests

Comprehensive testing for plugin architecture and integration marketplace modules.
Tests cover plugin lifecycle, hook execution, marketplace operations, and edge cases.
"""

import pytest
from datetime import datetime, timedelta
from apps.integration.plugin_architecture import (
    Plugin,
    PluginMetadata,
    PluginManager,
    HookType,
    PluginStatus,
    PluginSandboxLevel,
    PluginDependency,
    HookPoint,
)
from apps.integration.integration_marketplace import (
    Integration,
    IntegrationMarketplace,
    IntegrationCategory,
    IntegrationVersion,
    IntegrationRating,
)


class TestPluginArchitecture:
    """Test suite for plugin architecture system."""

    def test_plugin_metadata_creation(self):
        """Test creating plugin metadata."""
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test Plugin",
            version="1.0.0",
            author="Test Author",
            description="Test plugin for testing",
            plugin_type="monitoring",
            hook_points=[HookType.METRICS_COLLECTED],
            permissions={"read:metrics", "write:alerts"},
        )

        assert metadata.plugin_id == "test-plugin"
        assert metadata.name == "Test Plugin"
        assert len(metadata.hook_points) == 1
        assert len(metadata.permissions) == 2

    def test_plugin_creation(self):
        """Test creating a plugin instance."""
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test Plugin",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
        )

        plugin = Plugin(metadata, {})
        assert plugin.status == PluginStatus.UNLOADED
        assert plugin.execution_count == 0
        assert len(plugin.hooks) == 0

    def test_plugin_lifecycle(self):
        """Test plugin load/unload lifecycle."""
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
        )

        plugin = Plugin(metadata, {})
        assert plugin.on_load() == True
        assert plugin.on_unload() == True

    def test_plugin_manager_load(self):
        """Test loading plugin via manager."""
        manager = PluginManager()
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
            hook_points=[HookType.METRICS_COLLECTED],
        )

        plugin = Plugin(metadata, {})
        success, msg = manager.load_plugin(plugin)

        assert success == True
        assert plugin.status == PluginStatus.ACTIVE

    def test_plugin_manager_unload(self):
        """Test unloading plugin via manager."""
        manager = PluginManager()
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
        )

        plugin = Plugin(metadata, {})
        manager.load_plugin(plugin)

        success, msg = manager.unload_plugin("test-plugin")
        assert success == True
        assert "test-plugin" not in manager.registry.plugins

    def test_hook_execution(self):
        """Test executing a hook across plugins."""
        manager = PluginManager()

        class TestPlugin(Plugin):
            def execute(self, hook_type, data):
                return True, {"processed": True}

        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
            hook_points=[HookType.METRICS_COLLECTED],
        )

        plugin = TestPlugin(metadata, {})
        manager.load_plugin(plugin)

        results = manager.execute_hook(
            HookType.METRICS_COLLECTED, {"metric": "cpu", "value": 50}
        )

        assert len(results) == 1
        assert results[0].success == True
        assert results[0].result == {"processed": True}

    def test_hook_execution_with_multiple_plugins(self):
        """Test hook execution with multiple plugins."""
        manager = PluginManager()

        class Plugin1(Plugin):
            def execute(self, hook_type, data):
                return True, "Plugin1"

        class Plugin2(Plugin):
            def execute(self, hook_type, data):
                return True, "Plugin2"

        for i, cls in enumerate([Plugin1, Plugin2]):
            metadata = PluginMetadata(
                plugin_id=f"plugin-{i}",
                name=f"Plugin {i}",
                version="1.0.0",
                author="Test",
                description="Test",
                plugin_type="monitoring",
                hook_points=[HookType.METRICS_COLLECTED],
            )
            manager.load_plugin(cls(metadata, {}))

        results = manager.execute_hook(HookType.METRICS_COLLECTED, {})
        assert len(results) == 2

    def test_plugin_validation(self):
        """Test plugin validation."""
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
        )

        plugin = Plugin(metadata, {})
        manager = PluginManager()

        valid, messages = manager.validator.validate(plugin)
        assert valid == True
        assert len(messages) > 0

    def test_plugin_configuration_validation(self):
        """Test plugin configuration validation."""
        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
            config_schema={"api_key": str, "timeout": int},
        )

        # Valid config
        plugin1 = Plugin(metadata, {"api_key": "test", "timeout": 30})
        assert plugin1.validate_config() == True

        # Invalid config
        plugin2 = Plugin(metadata, {"api_key": "test"})
        assert plugin2.validate_config() == False

    def test_plugin_statistics(self):
        """Test getting plugin system statistics."""
        manager = PluginManager()

        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
            hook_points=[HookType.METRICS_COLLECTED],
        )

        class TestPlugin(Plugin):
            def execute(self, hook_type, data):
                return True, None

        plugin = TestPlugin(metadata, {})
        manager.load_plugin(plugin)
        manager.execute_hook(HookType.METRICS_COLLECTED, {})

        stats = manager.get_statistics()
        assert stats["active_plugins"] == 1
        assert stats["total_hook_executions"] >= 1

    def test_hook_history(self):
        """Test hook execution history."""
        manager = PluginManager()

        class TestPlugin(Plugin):
            def execute(self, hook_type, data):
                return True, None

        metadata = PluginMetadata(
            plugin_id="test-plugin",
            name="Test",
            version="1.0.0",
            author="Test",
            description="Test",
            plugin_type="monitoring",
            hook_points=[HookType.METRICS_COLLECTED],
        )

        plugin = TestPlugin(metadata, {})
        manager.load_plugin(plugin)

        manager.execute_hook(HookType.METRICS_COLLECTED, {})
        manager.execute_hook(HookType.METRICS_COLLECTED, {})

        history = manager.get_hook_history(HookType.METRICS_COLLECTED)
        assert len(history) >= 2


class TestIntegrationMarketplace:
    """Test suite for integration marketplace."""

    def test_marketplace_initialization(self):
        """Test marketplace has default integrations."""
        marketplace = IntegrationMarketplace()
        assert len(marketplace.registry.integrations) > 0

    def test_search_integrations_by_name(self):
        """Test searching integrations by name."""
        marketplace = IntegrationMarketplace()
        results = marketplace.search_integrations(query="Datadog")
        assert len(results) > 0
        assert results[0]["name"] == "Datadog"

    def test_search_integrations_by_category(self):
        """Test searching integrations by category."""
        marketplace = IntegrationMarketplace()
        results = marketplace.search_integrations(
            category="APM & Monitoring"
        )
        assert len(results) > 0
        for integration in results:
            assert integration["category"] == "APM & Monitoring"

    def test_search_integrations_by_tags(self):
        """Test searching integrations by tags."""
        marketplace = IntegrationMarketplace()
        results = marketplace.search_integrations(tags={"metrics"})
        assert len(results) > 0

    def test_get_integration(self):
        """Test getting specific integration."""
        marketplace = IntegrationMarketplace()
        integration = marketplace.get_integration("datadog")
        assert integration is not None
        assert integration["name"] == "Datadog"

    def test_install_integration(self):
        """Test installing an integration."""
        marketplace = IntegrationMarketplace()

        # Add config schema to integration
        integration = marketplace.registry.get_integration("datadog")
        integration.configuration_schema = {"api_key": str}

        success, msg = marketplace.install_integration("datadog", {"api_key": "test-key"})
        assert success == True
        assert "datadog" in marketplace.installed_integrations

    def test_uninstall_integration(self):
        """Test uninstalling an integration."""
        marketplace = IntegrationMarketplace()
        integration = marketplace.registry.get_integration("datadog")
        integration.configuration_schema = {"api_key": str}

        marketplace.install_integration("datadog", {"api_key": "test-key"})
        success, msg = marketplace.uninstall_integration("datadog")

        assert success == True
        assert "datadog" not in marketplace.installed_integrations

    def test_rate_integration(self):
        """Test rating an integration."""
        marketplace = IntegrationMarketplace()
        success, msg = marketplace.rate_integration("datadog", "user1", 5, "Great!")
        assert success == True

        # Check rating was added
        integration = marketplace.registry.get_integration("datadog")
        assert len(integration.ratings) > 0
        assert integration.ratings[-1].rating == 5

    def test_get_average_rating(self):
        """Test getting average rating."""
        marketplace = IntegrationMarketplace()
        integration = marketplace.registry.get_integration("datadog")

        marketplace.rate_integration("datadog", "user1", 5, "Good")
        marketplace.rate_integration("datadog", "user2", 3, "OK")

        avg_rating = integration.get_average_rating()
        assert avg_rating == 4.0

    def test_get_compatibility(self):
        """Test checking version compatibility."""
        marketplace = IntegrationMarketplace()
        compatibility = marketplace.get_compatibility("datadog", "1.0.0")

        assert compatibility["compatible"] == True
        assert len(compatibility["compatible_versions"]) > 0

    def test_get_usage_stats(self):
        """Test getting integration usage statistics."""
        marketplace = IntegrationMarketplace()
        stats = marketplace.get_usage_stats("datadog")

        assert stats is not None
        assert "total_installations" in stats
        assert "success_rate" in stats

    def test_recommend_integrations(self):
        """Test getting integration recommendations."""
        marketplace = IntegrationMarketplace()
        recommendations = marketplace.recommend_integrations({"metrics", "apm"}, limit=5)

        assert len(recommendations) <= 5
        for rec in recommendations:
            assert "name" in rec

    def test_get_installed_integrations(self):
        """Test getting installed integrations."""
        marketplace = IntegrationMarketplace()
        integration = marketplace.registry.get_integration("datadog")
        integration.configuration_schema = {"api_key": str}

        marketplace.install_integration("datadog", {"api_key": "key"})
        installed = marketplace.get_installed_integrations()

        assert len(installed) == 1
        assert installed[0]["integration_id"] == "datadog"

    def test_marketplace_statistics(self):
        """Test getting marketplace statistics."""
        marketplace = IntegrationMarketplace()
        stats = marketplace.get_marketplace_statistics()

        assert stats["total_integrations"] > 0
        assert "categories" in stats
        assert "installed_count" in stats

    def test_integration_version_compatibility(self):
        """Test integration version compatibility checking."""
        version = IntegrationVersion(
            version="1.0.0",
            release_date=datetime.utcnow(),
            changelog="Initial",
            platform_min_version="1.0.0",
            platform_max_version="2.0.0",
        )

        assert version.is_compatible("1.5.0") == True
        assert version.is_compatible("0.9.0") == False
        assert version.is_compatible("2.1.0") == False

    def test_integration_to_dict(self):
        """Test converting integration to dictionary."""
        integration = Integration(
            integration_id="test",
            name="Test Integration",
            category=IntegrationCategory.APM_MONITORING,
            description="Test",
            author="Test",
            icon_url="/icon.svg",
            website="http://test.com",
            documentation_url="/docs",
        )

        data = integration.to_dict()
        assert data["integration_id"] == "test"
        assert data["name"] == "Test Integration"
        assert data["category"] == "APM & Monitoring"

    def test_integration_version_history(self):
        """Test integration version history."""
        integration = Integration(
            integration_id="test",
            name="Test",
            category=IntegrationCategory.APM_MONITORING,
            description="Test",
            author="Test",
            icon_url="",
            website="",
            documentation_url="",
            versions=[
                IntegrationVersion(
                    version="1.0.0",
                    release_date=datetime.utcnow() - timedelta(days=10),
                    changelog="Initial",
                    platform_min_version="1.0.0",
                ),
                IntegrationVersion(
                    version="1.1.0",
                    release_date=datetime.utcnow(),
                    changelog="Update",
                    platform_min_version="1.0.0",
                ),
            ],
        )

        latest = integration.get_latest_version()
        assert latest.version == "1.1.0"

    def test_marketplace_category_listing(self):
        """Test listing categories in marketplace."""
        marketplace = IntegrationMarketplace()
        categories = marketplace.registry.list_categories()

        assert len(categories) > 0
        assert "APM & Monitoring" in categories


class TestIntegrationPhase26A:
    """Integration tests between plugin architecture and marketplace."""

    def test_plugin_as_integration_extension(self):
        """Test using plugins to extend integrations."""
        marketplace = IntegrationMarketplace()
        manager = PluginManager()

        class IntegrationExtensionPlugin(Plugin):
            def execute(self, hook_type, data):
                if hook_type == HookType.METRICS_COLLECTED:
                    # Extend metrics with custom processing
                    return True, {"extended": True}
                return True, None

        metadata = PluginMetadata(
            plugin_id="extension",
            name="Integration Extension",
            version="1.0.0",
            author="Test",
            description="Extends marketplace integrations",
            plugin_type="extension",
            hook_points=[HookType.METRICS_COLLECTED],
        )

        plugin = IntegrationExtensionPlugin(metadata, {})
        manager.load_plugin(plugin)

        # Trigger hook when integration processes metrics
        results = manager.execute_hook(HookType.METRICS_COLLECTED, {})
        assert len(results) == 1
        assert results[0].result["extended"] == True

    def test_end_to_end_integration_workflow(self):
        """Test complete integration workflow."""
        marketplace = IntegrationMarketplace()

        # Search for integrations
        search_results = marketplace.search_integrations(query="Slack")
        assert len(search_results) > 0

        # Get integration details
        integration = marketplace.get_integration("slack")
        assert integration is not None

        # Rate the integration
        marketplace.rate_integration("slack", "user1", 5, "Perfect!")

        # Get recommendations
        recommendations = marketplace.recommend_integrations({"notifications"}, limit=5)
        assert len(recommendations) > 0

        # Check statistics
        stats = marketplace.get_marketplace_statistics()
        assert stats["total_integrations"] > 0
