#!/usr/bin/env python3
# @file        sdk/python/elevatediq_sdk/agent.py
# @module      sdk/python/agent
# @description Base class for agent extensions

import logging
from typing import Dict, List, Any, Optional
from abc import ABC, abstractmethod
import json

logger = logging.getLogger(__name__)


class AgentExtension(ABC):
    """Base class for ElevatedIQ agent extensions."""

    def __init__(self, name: str, version: str, author: str):
        self.name = name
        self.version = version
        self.author = author
        self.capabilities: Dict[str, Any] = {}
        self.permissions: Dict[str, Any] = {}

    def declare_capabilities(self, capabilities: Dict[str, List[str]]):
        """Declare required capabilities (read_files, create_comments, etc.)."""
        self.capabilities = capabilities
        logger.info(f"Capabilities declared: {self.capabilities}")

    def declare_permissions(self, permissions: Dict[str, Any]):
        """Declare required permissions (event_bus, ide_panel, etc.)."""
        self.permissions = permissions
        logger.info(f"Permissions declared: {self.permissions}")

    @abstractmethod
    async def on_event(self, event_type: str, event_data: Dict) -> Optional[Dict]:
        """Handle event from event bus."""
        pass

    @abstractmethod
    async def on_command(self, command: str, args: Dict) -> Dict:
        """Handle IDE command."""
        pass

    def get_manifest(self) -> Dict:
        """Get extension manifest for registry."""
        return {
            "name": self.name,
            "version": self.version,
            "author": self.author,
            "capabilities": self.capabilities,
            "permissions": self.permissions,
            "type": "agent",
        }

    async def startup(self):
        """Called when extension is loaded."""
        logger.info(f"Extension {self.name} starting up")

    async def shutdown(self):
        """Called when extension is unloaded."""
        logger.info(f"Extension {self.name} shutting down")


class ModelExtension(ABC):
    """Base class for model extensions."""

    def __init__(self, name: str, model_type: str):
        self.name = name
        self.model_type = model_type  # llm, embedding, vision, etc.

    @abstractmethod
    async def infer(self, prompt: str, **kwargs) -> str:
        """Run inference on the model."""
        pass

    def get_manifest(self) -> Dict:
        """Get model extension manifest."""
        return {
            "name": self.name,
            "type": "model",
            "model_type": self.model_type,
        }


class PanelExtension(ABC):
    """Base class for IDE panel extensions."""

    def __init__(self, name: str, panel_id: str):
        self.name = name
        self.panel_id = panel_id

    @abstractmethod
    async def render(self) -> str:
        """Return HTML/React content for panel."""
        pass

    @abstractmethod
    async def on_message(self, message: Dict) -> Dict:
        """Handle message from webview."""
        pass

    def get_manifest(self) -> Dict:
        """Get panel extension manifest."""
        return {
            "name": self.name,
            "type": "panel",
            "panel_id": self.panel_id,
        }
