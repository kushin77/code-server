# @file        policies/marketplace/marketplace-agents.rego
# @module      policies/marketplace
# @description OPA policy for marketplace agent sandbox restrictions
# @owner       Phase 4 — Ecosystem & Autonomy
# @status      active

# Marketplace Agent Isolation Policy
#
# Restricts what marketplace agents can do:
# - No filesystem access by default
# - No network access by default
# - Must declare capabilities before use
# - Reputation-based capability grants

package marketplace.agents

import data.kushnir.agents as agents
import data.kushnir.orgs as orgs

# ============================================================================
# Default Deny (Fail-Closed)
# ============================================================================

# All capabilities denied by default
deny[reason] {
    not allow[_]
    reason := "Marketplace agents are untrusted; all capabilities must be explicitly allowed"
}

# ============================================================================
# Core Rules
# ============================================================================

# Rule 1: Filesystem Access
#
# Marketplace agents cannot access host filesystem without explicit capability grant
deny[reason] {
    input.action == "filesystem.read"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    not agent.capabilities.filesystem
    reason := sprintf("Agent %s lacks filesystem.read capability", [input.agent_id])
}

deny[reason] {
    input.action == "filesystem.write"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    not agent.capabilities.filesystem
    reason := sprintf("Agent %s lacks filesystem.write capability", [input.agent_id])
}

# Rule 2: Network Access
#
# Marketplace agents cannot make network requests without approval
deny[reason] {
    input.action == "network.request"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    not agent.capabilities.network
    reason := sprintf("Agent %s lacks network capability", [input.agent_id])
}

# Restrict network to whitelisted hosts for agents with network capability
deny[reason] {
    input.action == "network.request"
    agent := agents.get[input.agent_id]
    agent.capabilities.network
    agent.network_whitelist
    not input.target_host in agent.network_whitelist
    reason := sprintf("Agent %s cannot access %s (not whitelisted)", [input.agent_id, input.target_host])
}

# Rule 3: Process Execution
#
# Marketplace agents can only execute pre-approved commands
deny[reason] {
    input.action == "process.exec"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    not agent.capabilities.exec
    reason := sprintf("Agent %s lacks execution capability", [input.agent_id])
}

deny[reason] {
    input.action == "process.exec"
    agent := agents.get[input.agent_id]
    agent.capabilities.exec
    agent.exec_whitelist
    not input.command in agent.exec_whitelist
    reason := sprintf("Agent %s cannot execute %s (not approved)", [input.agent_id, input.command])
}

# Rule 4: Secret Access
#
# Marketplace agents never have access to secrets
deny[reason] {
    input.action == "secret.read"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    reason := "Marketplace agents cannot access secrets"
}

# Rule 5: Reputation-Based Access
#
# Agents with low reputation scores have stricter restrictions
deny[reason] {
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    agent.reputation_score < 30
    input.action in ["network.request", "process.exec"]
    reason := sprintf("Agent %s has low reputation (%d); restricted actions denied", 
                     [input.agent_id, agent.reputation_score])
}

# ============================================================================
# Allowed Actions
# ============================================================================

# Marketplace agents can always perform these read-only operations
allow {
    input.action in ["read.metadata", "list.directory"]
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
}

# Agents with reputation >= 50 can write to sandbox directory
allow {
    input.action == "filesystem.write_sandbox"
    agent := agents.get[input.agent_id]
    agent.source == "marketplace"
    agent.reputation_score >= 50
}

# ============================================================================
# Audit Logging
# ============================================================================

audit[entry] {
    entry := {
        "timestamp": now,
        "agent_id": input.agent_id,
        "action": input.action,
        "decision": "denied",
        "reason": deny[_]
    }
}
