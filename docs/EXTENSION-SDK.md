# ElevatedIQ Extension SDK Documentation

## Overview

The ElevatedIQ Extension SDK enables third-party developers to build autonomous agents, models, and IDE panels that integrate seamlessly with the ElevatedIQ platform while maintaining strict security isolation.

**Key Features:**
- **Sandbox Isolation**: Extensions run in isolated Docker containers with network and capability gating
- **Capability-Based Security**: Manifest-driven capability declarations, OPA-enforced (fail-closed)
- **Event Bus Integration**: Subscribe/publish to Kafka topics for inter-service communication
- **Memory Engine Access**: Read-only access to organization memory (no pollution)
- **IDE Panel Support**: Render custom panels in VS Code via Webview API bridge
- **Marketplace Integration**: Package and distribute extensions through official marketplace

---

## Extension Types

### 1. Agent Extensions
Autonomous agents that subscribe to events and perform actions.

**Capabilities:**
- `read_files`: Read workspace files (readonly)
- `create_comments`: Post comments to issues/PRs
- `memory_read`: Read from organization memory
- `event_subscribe`: Subscribe to event topics
- `event_publish`: Publish events
- `ide_panel`: Display custom IDE panels

**Example:**
```python
from elevatediq_sdk import AgentExtension, EventBusClient

class ReviewAgent(AgentExtension):
    def __init__(self):
        super().__init__("review-agent", "0.1.0", "acme-corp")
        
        # Declare capabilities
        self.declare_capabilities({
            "read_files": ["*.py", "*.ts"],
            "create_comments": True,
            "event_subscribe": ["code.review"],
        })
        
        # Declare permissions
        self.declare_permissions({
            "event_bus": {
                "subscribe": ["code.review"],
                "publish": ["agent.audit"],
            }
        })

    async def on_event(self, event_type, event_data):
        if event_type == "code.review":
            # Process review event
            return {"status": "reviewed"}
    
    async def on_command(self, command, args):
        if command == "scan":
            return {"scan_id": "123"}
        return {}
```

### 2. Model Extensions
Custom model servers compatible with Ollama API.

**Capabilities:**
- `model_inference`: Run inference
- `gpu_access`: Use GPU (if available)
- `batch_processing`: Batch operations

**Example:**
```python
from elevatediq_sdk import ModelExtension

class CustomModel(ModelExtension):
    def __init__(self):
        super().__init__("custom-llm", "llm")
    
    async def infer(self, prompt, **kwargs):
        # Run inference on custom model
        return "Model response to: " + prompt
```

### 3. Panel Extensions
Custom IDE panels rendered in VS Code.

**Capabilities:**
- `ide_webview`: Render webview
- `event_publish`: Send events
- `memory_read`: Access memory

**Example:**
```python
from elevatediq_sdk import PanelExtension

class Dashboard(PanelExtension):
    def __init__(self):
        super().__init__("dashboard", "com.acme.dashboard")
    
    async def render(self):
        return """
        <div id="dashboard">
            <h1>Custom Dashboard</h1>
            <p>Extension data here</p>
        </div>
        """
    
    async def on_message(self, message):
        return {"ack": True}
```

---

## Installation & CLI

### Install Extension
```bash
elevatediq extension install acme/review-agent \
  --source https://registry.elevatediq.com/acme/review-agent-0.1.0.tar.gz
```

### List Extensions
```bash
elevatediq extension list

# Output:
# NAME                   VERSION  STATUS    TYPE
# acme/review-agent      0.1.0    active    agent
# custom/model-llm       1.0.0    active    model
```

### Uninstall Extension
```bash
elevatediq extension uninstall acme/review-agent
```

### Update Extensions
```bash
elevatediq extension upgrade --all
```

---

## Manifest Format

Every extension must include `extension.yaml`:

```yaml
name: acme/review-agent
version: 0.1.0
author: acme-corp
type: agent  # agent | model | panel | tool

capabilities:
  read_files: ["*.md"]
  create_comments: true
  memory_read: true
  event_subscribe: ["code.review"]

permissions:
  event_bus:
    subscribe: ["code.review"]
    publish: ["agent.audit"]
  
  ide_panel: "Custom Review Panel"

signatures:
  author_public_key: "ssh-rsa AAAA..."
  marketplace_signature: "sig_..."  # Required for distribution
```

---

## Isolation & Security

### Network Isolation
Extensions run in **separate Docker networks** (`extension-net-{id}`):
- Cannot reach primary services (`app-net`) by default
- Can only access services explicitly declared in manifest
- Network policy enforced by Docker daemon

### Capability Gating
All capabilities are **OPA-enforced** (fail-closed):

```rego
# ✅ ALLOWED: Declared in manifest
capability: read_files

# ❌ BLOCKED: Not declared
capability: write_workspace  # → OPA denial

# ❌ BLOCKED: Not in allowed list
capability: arbitrary_code_exec  # → OPA denial
```

### Resource Limits
- **CPU**: 0.5 cores per extension (configurable)
- **Memory**: 512 MB per extension (configurable)
- **Filesystem**: Read-only workspace mount (if `read_files` declared)
- **Network**: Whitelist-only (default deny all external)

---

## Event Bus Integration

### Subscribe to Events
```python
from elevatediq_sdk import EventBusClient

event_bus = EventBusClient()

async def handle_review(event_type, event_data):
    print(f"Got event: {event_data}")

await event_bus.subscribe("code.review", handle_review)
await event_bus.start()
```

### Publish Events
```python
await event_bus.emit_event(
    topic="agent.audit",
    event_type="review_completed",
    data={
        "pr_id": "1234",
        "status": "approved",
        "timestamp": "2026-04-23T10:00:00Z",
    }
)
```

**Available Topics:**
- `code.review` — PR review events
- `code.commit` — Commit events
- `agent.audit` — Agent activity log
- `system.health` — Health/status events

---

## Memory Engine Access

### Read from Memory (Read-Only)
```python
from elevatediq_sdk import MemoryClient

memory = MemoryClient()

# Read single value
past_reviews = await memory.read("agent/reviews/completed")

# List directory
all_reviews = await memory.read_directory("agent/reviews/")

# Query with pattern
pr_1234_data = await memory.query("pr:1234:*")
```

**Remember:** Extensions **cannot write** to organization memory (read-only enforced).

---

## IDE Panel Integration

### Register Custom Panel
```python
class StatusPanel(PanelExtension):
    async def render(self):
        return """
        <style>
            #status { color: green; }
        </style>
        <div id="status">
            <h2>Extension Status</h2>
            <p id="message">Ready</p>
        </div>
        <script>
            vscode.postMessage({ type: "getStatus" });
        </script>
        """
    
    async def on_message(self, msg):
        if msg["type"] == "getStatus":
            return {"status": "running"}
```

Panels appear in:
- VS Code Activity Bar (icon)
- VS Code Command Palette (`ext: open panel`)
- VS Code Sidebar (when activated)

---

## Publishing to Marketplace

### Build Extension Package
```bash
tar czf acme-review-agent-0.1.0.tar.gz \
  extension.yaml \
  src/ \
  README.md
```

### Sign for Distribution
```bash
elevatediq extension sign acme-review-agent-0.1.0.tar.gz \
  --private-key ~/.ssh/id_rsa \
  --marketplace-key /path/to/marketplace.key

# Generates: acme-review-agent-0.1.0.tar.gz.sig
```

### Publish
```bash
elevatediq extension publish acme-review-agent-0.1.0.tar.gz
# Published at: https://registry.elevatediq.com/acme/review-agent/0.1.0
```

---

## Example: "Hello World" Agent

**File: `extension.yaml`**
```yaml
name: acme/hello-world
version: 0.1.0
author: acme-corp
type: agent

capabilities:
  event_publish: true
  memory_read: true

permissions:
  event_bus:
    publish: ["agent.audit"]
```

**File: `hello_world.py`**
```python
#!/usr/bin/env python3
from elevatediq_sdk import AgentExtension, EventBusClient

class HelloWorld(AgentExtension):
    def __init__(self):
        super().__init__("hello-world", "0.1.0", "acme-corp")
        self.event_bus = EventBusClient()
        
        self.declare_capabilities({
            "event_publish": True,
            "memory_read": True,
        })
    
    async def on_event(self, event_type, event_data):
        print(f"Hello from agent! Event: {event_type}")
        await self.event_bus.emit_event(
            "agent.audit",
            "hello_world_executed",
            {"message": "Hello, ElevatedIQ!"}
        )
        return {"status": "done"}
    
    async def on_command(self, command, args):
        return {"message": "Hello, World!"}
```

**Test:**
```bash
elevatediq extension install acme/hello-world --source ./hello-world.tar.gz
elevatediq extension list  # Shows: acme/hello-world 0.1.0 active
```

---

## OPA Policy Reference

All extensions are evaluated against `policies/extensions/extension-policy.rego`:

| Rule | Enforcement | Fail-Closed |
|------|-------------|-------------|
| Type declared | ✅ Required | ❌ Deny if missing |
| Capabilities in allow-list | ✅ Enforced | ❌ Deny if invalid |
| No memory_write capability | ✅ Enforced | ❌ Deny if requested |
| Permission scopes match capabilities | ✅ Enforced | ❌ Deny if mismatch |
| Marketplace signature present | ✅ Required for install | ❌ Deny if missing |
| Author declared | ✅ Required | ❌ Deny if missing |
| Semantic versioning | ✅ Enforced | ❌ Deny if invalid |

---

## Troubleshooting

### Extension fails to load
```bash
# Check logs
docker logs extension-acme-review-agent

# Check OPA evaluation
elevatediq extension verify acme-review-agent-0.1.0.tar.gz --dry-run
```

### Capability denied
```
Error: Capability 'memory_write' not allowed for type 'agent'
Fix: Remove 'memory_write' from manifest (extensions are read-only)
```

### Network isolation issues
```bash
# Check extension network
docker network inspect extension-net-acme-review-agent

# Test connectivity from container
docker exec extension-acme-review-agent curl http://kafka:9092
```

---

## Links

- **Source**: `sdk/python/elevatediq_sdk/`
- **Runtime**: `apps/extension-runtime/`
- **Policy**: `policies/extensions/extension-policy.rego`
- **Marketplace**: https://registry.elevatediq.com
- **Issues**: https://github.com/kushin77/code-server/issues?label=extensions
