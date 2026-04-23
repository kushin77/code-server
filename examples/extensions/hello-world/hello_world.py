#!/usr/bin/env python3
# @file        examples/extensions/hello-world/hello_world.py
# @module      extensions/examples/hello-world
# @description Hello World agent extension - demonstrates SDK usage

import sys
import asyncio
import logging

# Mock SDK for demo (real version would import from sdk/python/elevatediq_sdk)
sys.path.insert(0, "/opt/elevatediq/sdk/python")

from elevatediq_sdk import AgentExtension, EventBusClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class HelloWorldAgent(AgentExtension):
    """Simple Hello World agent demonstrating SDK capabilities."""

    def __init__(self):
        super().__init__(
            name="acme/hello-world-agent",
            version="0.1.0",
            author="acme-corp",
        )

        self.event_bus = EventBusClient()

        # Declare required capabilities
        self.declare_capabilities({
            "event_publish": True,
            "memory_read": True,
        })

        # Declare required permissions
        self.declare_permissions({
            "event_bus": {
                "subscribe": [],
                "publish": ["agent.audit"],
            },
        })

        logger.info(f"✅ {self.name} initialized")

    async def on_event(self, event_type: str, event_data: dict):
        """Handle event from event bus."""
        logger.info(f"🎯 Received event: {event_type}")
        logger.info(f"   Data: {event_data}")

        # Publish audit event
        await self.event_bus.emit_event(
            topic="agent.audit",
            event_type="hello_world_executed",
            data={
                "agent": self.name,
                "message": "Hello, ElevatedIQ!",
                "received_event": event_type,
            },
        )

        return {"status": "done", "message": "Hello World executed"}

    async def on_command(self, command: str, args: dict) -> dict:
        """Handle IDE command."""
        logger.info(f"📋 Command: {command} with args: {args}")

        if command == "hello":
            return {
                "status": "success",
                "message": "Hello, World!",
                "agent": self.name,
            }

        return {"status": "unknown", "command": command}

    async def startup(self):
        """Called when extension is loaded."""
        logger.info(f"🚀 {self.name} starting up")
        await self.event_bus.start()

    async def shutdown(self):
        """Called when extension is unloaded."""
        logger.info(f"🛑 {self.name} shutting down")
        await self.event_bus.stop()


async def main():
    """Main entry point for testing."""
    agent = HelloWorldAgent()

    # Startup
    await agent.startup()

    # Simulate events
    await agent.on_event(
        "test.event",
        {"source": "demo", "timestamp": "2026-04-23T10:00:00Z"},
    )

    # Test command
    result = await agent.on_command("hello", {})
    logger.info(f"✅ Command result: {result}")

    # Shutdown
    await agent.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
