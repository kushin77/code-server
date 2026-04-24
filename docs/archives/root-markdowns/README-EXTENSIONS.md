# Extension Framework README

This directory contains the ElevatedIQ Extension Framework for third-party agent development.

## Directory Structure

```
apps/extension-runtime/          # Extension lifecycle manager
  main.py                        # Runtime manager
  installer.py                   # Install/verify extensions
  isolation.py                   # Network + capability isolation

sdk/python/elevatediq_sdk/       # Python SDK for extensions
  __init__.py                    # Package exports
  agent.py                       # AgentExtension, ModelExtension, PanelExtension base classes
  events.py                      # EventBusClient for Kafka integration
  memory.py                      # MemoryClient for org memory access

policies/extensions/
  extension-policy.rego          # OPA fail-closed extension security policy

examples/extensions/hello-world/ # Example extension (Hello World agent)
  extension.yaml                 # Manifest with capability declarations
  hello_world.py                 # Implementation

docs/EXTENSION-SDK.md            # Full SDK documentation
```

## Quick Start

### 1. Install an Extension

```bash
elevatediq extension install acme/hello-world \
  --source examples/extensions/hello-world/
```

### 2. List Installed Extensions

```bash
elevatediq extension list
# Output:
# NAME                     VERSION  STATUS  TYPE
# acme/hello-world-agent   0.1.0    active  agent
```

### 3. Test Event Handling

```bash
elevatediq event emit code.review --data '{"pr": 1234}'
# Triggers all extensions subscribed to code.review
```

### 4. View Logs

```bash
docker logs extension-acme-hello-world-agent
```

## Key Features

### ✅ Capability-Based Security
All extension capabilities are declared in `extension.yaml` and enforced by OPA (fail-closed):

```yaml
capabilities:
  read_files: ["*.md"]
  event_publish: true
  memory_read: true
  # ❌ Cannot declare arbitrary capabilities
```

### ✅ Network Isolation
Extensions run in isolated Docker networks:
- Cannot reach primary services by default
- Can only communicate with explicitly declared services
- Resource limits: 0.5 CPU cores, 512 MB memory

### ✅ Event Bus Integration
Subscribe to platform events and publish audit logs:

```python
# Subscribe
await event_bus.subscribe("code.review", handle_review)

# Publish
await event_bus.emit_event("agent.audit", "review_done", {...})
```

### ✅ Memory Engine Access
Read-only access to organization memory:

```python
reviews = await memory.read("agent/reviews/completed")
```

## SDK Modules

### `agent.py`
- `AgentExtension` — Base class for autonomous agents
- `ModelExtension` — Base class for model servers
- `PanelExtension` — Base class for IDE panels

### `events.py`
- `EventBusClient` — Kafka client for event pub/sub

### `memory.py`
- `MemoryClient` — Read-only memory engine client

## OPA Security Policy

All extensions are evaluated against `policies/extensions/extension-policy.rego`:

| Rule | Status | Consequence |
|------|--------|-------------|
| Type declared | Required | Deny if missing |
| Capabilities in allow-list | Enforced | Deny if invalid |
| Permission scopes match | Enforced | Deny if mismatch |
| Marketplace signature | Required | Deny if unsigned |
| Semantic version | Enforced | Deny if invalid |

**Default: DENY** (fail-closed security model)

## Testing

### Test Hello World Extension

```bash
# Run locally
cd examples/extensions/hello-world
python3 hello_world.py

# Install and test
elevatediq extension install acme/hello-world --source ./
elevatediq event emit code.review --data '{"pr": 1234}'

# Check logs
docker logs extension-acme-hello-world-agent
```

### Validate OPA Policy

```bash
elevatediq extension verify examples/extensions/hello-world/ --dry-run

# Output:
# ✅ Type: agent
# ✅ Capabilities: event_publish, memory_read
# ✅ Permissions: event_bus.publish
# ✅ Policy: ALLOWED
```

## Publishing to Marketplace

### Build Extension Package

```bash
tar czf acme-hello-world-0.1.0.tar.gz \
  examples/extensions/hello-world/
```

### Sign for Distribution

```bash
elevatediq extension sign acme-hello-world-0.1.0.tar.gz \
  --private-key ~/.ssh/id_rsa
```

### Publish

```bash
elevatediq extension publish acme-hello-world-0.1.0.tar.gz
```

Available at: `https://registry.elevatediq.com/acme/hello-world-agent/0.1.0`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ ElevatedIQ Platform                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Extension Runtime (apps/extension-runtime/)             │  │
│  │ - Load/unload extensions                                │  │
│  │ - Route events to extensions                            │  │
│  │ - Enforce OPA policies                                  │  │
│  └─────────────────────────────────────────────────────────┘  │
│                          │                                      │
│  ┌───────────────────────┴───────────────────────────────────┐ │
│  │ Extension Containers (Docker)                           │ │
│  │ ┌─────────────────┐ ┌──────────────────┐ ┌───────────┐ │ │
│  │ │ hello-world    │ │ review-agent     │ │ custom-llm│ │ │
│  │ │ (network-iso)  │ │ (network-iso)    │ │ (isolated)│ │ │
│  │ └─────────────────┘ └──────────────────┘ └───────────┘ │ │
│  └──────────┬─────────────────────────────────┬────────────┘ │
│             │                                 │              │
│  ┌──────────┴─────────┐        ┌──────────────┴─────┐        │
│  │ Kafka Event Bus    │        │ OPA Gatekeeper      │        │
│  │ (code.review,      │        │ (extension-policy)  │        │
│  │  agent.audit)      │        └────────────────────┘        │
│  └────────────────────┘                                       │
│             │                                                 │
│  ┌──────────┴──────────────────────────────────────────────┐ │
│  │ Core Services                                           │ │
│  │ - Memory Engine (read-only)                             │ │
│  │ - IDE Panels                                            │ │
│  │ - Model Router                                          │ │
│  │ - Audit Logging                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Links

- **Documentation**: [docs/EXTENSION-SDK.md](../../docs/EXTENSION-SDK.md)
- **Policy**: [policies/extensions/extension-policy.rego](../../policies/extensions/extension-policy.rego)
- **SDK**: [sdk/python/elevatediq_sdk/](../../sdk/python/elevatediq_sdk/)
- **Marketplace**: https://registry.elevatediq.com
- **Issues**: https://github.com/kushin77/code-server/issues?label=extensions

