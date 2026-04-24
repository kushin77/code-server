# Agent Marketplace SDK Documentation

**Version:** 0.1.0 (Phase 4 Preview)  
**Repository:** kushin77/code-server  
**Status:** ACTIVE

---

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Agent Package Format](#agent-package-format)
4. [Publishing to Marketplace](#publishing-to-marketplace)
5. [API Reference](#api-reference)
6. [Capabilities & Permissions](#capabilities--permissions)
7. [Security & Sandboxing](#security--sandboxing)
8. [Monetization](#monetization)
9. [Best Practices](#best-practices)

---

## Overview

The **Kushnir.cloud (KC) Agent Marketplace** is a platform for publishing, discovering, and executing AI agents. Agents are:

- **Autonomous programs** that can diagnose issues, perform fixes, generate code, etc.
- **Versioned & signed** with GPG signatures for integrity verification
- **Rated & reviewed** by community with reputation scoring
- **Monetizable** through usage-based or subscription pricing
- **Sandboxed** to prevent malicious code execution

This SDK helps you package, publish, and manage agents in the marketplace.

---

## Getting Started

### Prerequisites

- Python 3.9+
- `elevatediq` CLI tool (installed from KC)
- GPG key for signing packages
- Stripe account (if monetizing)

### Installation

```bash
# Install elevatediq CLI
curl -fsSL https://install.kushnir.cloud | bash

# Verify installation
elevatediq version
```

### Your First Agent

1. Create a Python package with your agent code
2. Define `metadata.yaml` with agent info
3. Package it as tarball
4. Publish to marketplace

---

## Agent Package Format

### Directory Structure

```
my-incident-responder/
├── metadata.yaml          # Agent metadata
├── requirements.txt       # Python dependencies
├── src/
│   └── agent.py          # Main agent code
├── tests/
│   └── test_agent.py
└── examples/
    └── response_example.json
```

### metadata.yaml

```yaml
# @file metadata.yaml
# Agent manifest for marketplace

namespace: "myorg/incident-responder"
version: "1.2.0"
description: "Auto-responds to common incidents (Caddy 502, database overload, etc.)"

author:
  name: "Alice Engineer"
  email: "alice@myorg.com"
  website: "https://myorg.com"

category: "incident-response"  # code-review | incident-response | documentation | testing | deployment | security

capabilities:
  - network              # Can make HTTP requests
  - exec                 # Can execute shell commands
  # - filesystem         # Can read/write filesystem (NOT available for marketplace agents initially)

exec_whitelist:          # Approved commands (fail-closed)
  - "curl"
  - "ps aux"
  - "systemctl status"
  - "journalctl -n 100"

network_whitelist:       # Approved hosts (fail-closed)
  - "api.kushnir.cloud"
  - "monitoring.kushnir.cloud"

pricing:
  tier: "usage"          # free | usage | subscription
  price_per_1k_tokens: 0.01  # $0.01 per 1000 tokens consumed

repository: "https://github.com/myorg/incident-responder"
documentation: "https://github.com/myorg/incident-responder/blob/main/README.md"
license: "Apache-2.0"
```

### src/agent.py

```python
#!/usr/bin/env python3
"""Incident responder agent"""

import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class IncidentResponderAgent:
    """Responds to common incidents"""
    
    def __init__(self):
        self.capabilities = {
            "network": True,
            "exec": True,
        }
    
    async def run(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Run the agent
        
        Args:
            context: Incident context (error logs, system state, etc.)
            
        Returns:
            Response with diagnosis and remediation steps
        """
        incident_type = context.get("type")
        
        if incident_type == "caddy_502":
            return await self.handle_caddy_502(context)
        elif incident_type == "database_overload":
            return await self.handle_database_overload(context)
        
        return {
            "status": "unknown_incident",
            "diagnosis": f"Unknown incident type: {incident_type}",
        }
    
    async def handle_caddy_502(self, context: Dict) -> Dict:
        """Handle Caddy 502 Bad Gateway errors"""
        # TODO: Implement diagnosis and remediation
        return {
            "status": "resolved",
            "diagnosis": "Upstream service was temporarily unavailable",
            "remediation": "Restarted upstream service",
            "time_to_fix_ms": 1200,
        }
    
    async def handle_database_overload(self, context: Dict) -> Dict:
        """Handle database overload incidents"""
        # TODO: Implement diagnosis and remediation
        return {
            "status": "resolved",
            "diagnosis": "Database connection pool exhausted",
            "remediation": "Increased connection pool size and restarted",
            "time_to_fix_ms": 3400,
        }
```

### requirements.txt

```
pydantic==2.4.0
httpx==0.24.0
pyyaml==6.0
```

---

## Publishing to Marketplace

### Step 1: Package Your Agent

```bash
# Build tarball
tar -czf my-incident-responder-1.2.0.tar.gz \
  src/ \
  metadata.yaml \
  requirements.txt

# Sign package with GPG
gpg --armor --sign --detach-sign my-incident-responder-1.2.0.tar.gz
# Creates my-incident-responder-1.2.0.tar.gz.asc
```

### Step 2: Publish to Marketplace

```bash
elevatediq agent publish \
  --package my-incident-responder-1.2.0.tar.gz \
  --signature my-incident-responder-1.2.0.tar.gz.asc \
  --metadata metadata.yaml
```

Response:
```json
{
  "status": "published",
  "agent_id": "a1b2c3d4e5f6",
  "namespace": "myorg/incident-responder",
  "version": "1.2.0",
  "url": "https://marketplace.kushnir.cloud/agents/myorg/incident-responder"
}
```

### Step 3: Verify Publication

```bash
elevatediq agent search "incident responder"
```

---

## API Reference

### Registry API Endpoints

#### Publish Agent
```
POST /registry/agents
Content-Type: application/json

{
  "metadata": { ... },
  "content": "<base64-encoded-tarball>"
}

Response:
{
  "status": "published",
  "agent_id": "a1b2c3d4",
  "version": "1.2.0"
}
```

#### List Agents
```
GET /registry/agents?category=incident-response&sort_by=reputation&limit=20

Response:
{
  "agents": [
    {
      "agent_id": "a1b2c3d4",
      "namespace": "myorg/incident-responder",
      "version": "1.2.0",
      "rating": 4.8,
      "install_count": 342,
      "reputation_score": 92
    }
  ],
  "total_count": 1247
}
```

#### Search Agents
```
GET /registry/search?query=caddy 502&limit=10

Response:
{
  "query": "caddy 502",
  "results": [...],
  "total_count": 45
}
```

#### Install Agent
```
POST /registry/agents/{agent_id}/install?org_id=myorg

Response:
{
  "status": "ready_for_install",
  "download_url": "https://registry.kushnir.cloud/download/a1b2c3d4",
  "install_command": "elevatediq agent install myorg/incident-responder:1.2.0"
}
```

---

## Capabilities & Permissions

### Available Capabilities

| Capability | Description | Restrictions |
|-----------|-----------|---|
| `network` | Make HTTP/TCP requests | Must whitelist target hosts |
| `exec` | Execute shell commands | Must whitelist allowed commands |
| `filesystem` | Read/write files | NOT available for marketplace agents (Phase 5+) |
| `secrets` | Access org secrets | NEVER available for marketplace agents |

### Whitelisting Pattern

Marketplace agents operate under **fail-closed** policy:

```yaml
# Declare capabilities
capabilities:
  - network
  - exec

# Whitelist specific resources
network_whitelist:
  - "api.kushnir.cloud"
  - "*.monitoring.kushnir.cloud"

exec_whitelist:
  - "curl"
  - "systemctl"
```

Any action outside the whitelist is **automatically denied**.

---

## Security & Sandboxing

### Sandbox Layers

1. **Container Isolation** — Agents run in separate Docker containers
2. **Network Policy** — Whitelist-only network access via OPA policies
3. **Signature Verification** — GPG signature checked on every download
4. **Reputation Gating** — Agents with reputation < 50 cannot be published
5. **Capability Declarations** — Capabilities must be declared (fail-closed)

### Signature Verification

```bash
# User downloads agent
elevatediq agent install myorg/incident-responder:1.2.0

# System verifies signature
# 1. Fetch agent from registry
# 2. Download GPG signature
# 3. Verify against author's public key
# 4. Reject if tampered
# 5. Extract and run in sandbox
```

### Reputation Scoring

```
reputation = 0.5 × install_count_normalized +
            0.3 × avg_user_rating +
            0.2 × incident_detection_rate
```

---

## Monetization

### Pricing Tiers

| Tier | Cost | Use Case |
|-----|------|----------|
| `free` | Free | Open-source agents, community projects |
| `usage` | $0.01 / 1000 tokens | Per-call billing model |
| `subscription` | $9.99 / month | Premium agents with SLA |

### Setting Price Tier

```yaml
# metadata.yaml
pricing:
  tier: "usage"
  price_per_1k_tokens: 0.01
```

### Revenue Model

```
Total Agent Revenue: $100
  → 70% to Agent Author: $70
  → 30% to Platform: $30
```

Authors receive monthly payouts to registered Stripe account.

### Monitoring Earnings

```bash
elevatediq agent earnings --agent myorg/incident-responder

Output:
Agent: myorg/incident-responder
Period: April 2026
Usage: 523,412 tokens
Revenue: $5.23
Author Share (70%): $3.66
Platform Share (30%): $1.57
```

---

## Best Practices

### 1. Security-First

- Always sign packages with GPG
- Whitelist strictly (deny-by-default)
- Never request unnecessary capabilities
- Test in sandbox before publishing

### 2. Documentation

- Write clear README with examples
- Document all capabilities and whitelists
- Provide example usage in docs
- Link to repository and issues

### 3. Versioning

- Follow semantic versioning (MAJOR.MINOR.PATCH)
- Document breaking changes in release notes
- Keep old versions available for rollback

### 4. Error Handling

- Log all errors with context
- Return clear diagnosis to users
- Suggest remediation steps
- Measure time-to-fix for reputation

### 5. Performance

- Optimize token consumption (affects user cost)
- Cache results when possible
- Profile token usage in tests
- Document expected token cost per execution

### 6. Testing

```bash
# Test locally in sandbox
elevatediq agent test my-incident-responder/

# Dry-run before publishing
elevatediq agent publish --dry-run

# Monitor after publishing
elevatediq agent monitor myorg/incident-responder
```

---

## Example: Publish & Install End-to-End

### As Author

```bash
# Clone template
git clone https://github.com/kushin77/agent-template my-agent
cd my-agent

# Implement your agent
vim src/agent.py

# Test locally
python -m pytest tests/

# Package
tar -czf my-agent-1.0.0.tar.gz src/ metadata.yaml requirements.txt
gpg --armor --sign --detach-sign my-agent-1.0.0.tar.gz

# Publish
elevatediq agent publish --package my-agent-1.0.0.tar.gz

# Verify
elevatediq agent search "my agent"
```

### As User

```bash
# Find agent
elevatediq agent search "incident responder"

# Install
elevatediq agent install myorg/incident-responder:1.2.0

# Configure capabilities (approve sandbox access)
# System prompts: "Allow network access to api.kushnir.cloud?" → y

# Use in IDE
# Incident triggers → Agent runs → Displays result
```

---

## Support

- **Documentation:** https://docs.kushnir.cloud/agents
- **Examples:** https://github.com/kushin77/agent-examples
- **Community:** https://github.com/kushin77/code-server/discussions
- **Issues:** https://github.com/kushin77/code-server/issues

---

**Last Updated:** April 23, 2026  
**Phase:** 4 — Ecosystem & Autonomy  
**Status:** Active
