#!/usr/bin/env python3
# @file        apps/extension-runtime/main.py
# @module      extension-runtime/manager
# @description Extension lifecycle manager and router

import logging
import yaml
import asyncio
from pathlib import Path
from typing import Dict, List, Optional
import importlib.util
import sys

logger = logging.getLogger(__name__)


class ExtensionRuntime:
    """Manages extension lifecycle and isolation."""

    def __init__(self, config_path: str = "config/extensions.yaml"):
        self.config_path = Path(config_path)
        self.extensions: Dict[str, any] = {}
        self.network_isolate = True  # Enable network isolation by default

    async def load_extensions(self):
        """Load all registered extensions from config."""
        if not self.config_path.exists():
            logger.warning(f"No extensions config found: {self.config_path}")
            return

        try:
            with open(self.config_path) as f:
                config = yaml.safe_load(f)

            for ext_name, ext_config in (config.get("extensions") or {}).items():
                await self.load_extension(ext_name, ext_config)

        except Exception as e:
            logger.error(f"Failed to load extensions: {e}")

    async def load_extension(self, name: str, config: Dict):
        """Load a single extension."""
        try:
            logger.info(f"Loading extension: {name}")

            # Load extension module
            module_path = config.get("path")
            if not module_path:
                logger.error(f"No path specified for extension {name}")
                return

            spec = importlib.util.spec_from_file_location(name, module_path)
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            spec.loader.exec_module(module)

            # Get extension class
            extension_class = getattr(module, config.get("class", "Extension"))
            extension = extension_class()

            # Store extension
            self.extensions[name] = {
                "instance": extension,
                "config": config,
                "status": "loaded",
            }

            # Call startup hook
            if hasattr(extension, "startup"):
                await extension.startup()

            logger.info(f"✅ Extension loaded: {name}")

        except Exception as e:
            logger.error(f"❌ Failed to load extension {name}: {e}")

    async def unload_extension(self, name: str) -> bool:
        """Unload an extension."""
        if name not in self.extensions:
            logger.warning(f"Extension not found: {name}")
            return False

        try:
            extension = self.extensions[name]["instance"]

            # Call shutdown hook
            if hasattr(extension, "shutdown"):
                await extension.shutdown()

            # Remove extension
            del self.extensions[name]
            logger.info(f"✅ Extension unloaded: {name}")
            return True

        except Exception as e:
            logger.error(f"❌ Failed to unload extension {name}: {e}")
            return False

    async def handle_event(self, event_type: str, event_data: Dict) -> List[Dict]:
        """Route event to all subscribed extensions."""
        results = []

        for ext_name, ext_info in self.extensions.items():
            try:
                extension = ext_info["instance"]

                # Check if extension handles this event type
                if hasattr(extension, "on_event"):
                    result = await extension.on_event(event_type, event_data)
                    if result:
                        results.append({
                            "extension": ext_name,
                            "result": result,
                        })

            except Exception as e:
                logger.error(f"Extension {ext_name} error handling {event_type}: {e}")

        return results

    def get_extension_status(self) -> Dict:
        """Get status of all loaded extensions."""
        return {
            ext_name: {
                "status": ext_info["status"],
                "config": ext_info["config"],
            }
            for ext_name, ext_info in self.extensions.items()
        }

    def list_extensions(self) -> List[str]:
        """List all loaded extension names."""
        return list(self.extensions.keys())


# Singleton instance
_runtime: Optional[ExtensionRuntime] = None


async def initialize_runtime(config_path: str = "config/extensions.yaml") -> ExtensionRuntime:
    """Initialize extension runtime."""
    global _runtime
    _runtime = ExtensionRuntime(config_path)
    await _runtime.load_extensions()
    return _runtime


def get_runtime() -> Optional[ExtensionRuntime]:
    """Get the runtime instance."""
    return _runtime
