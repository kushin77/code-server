# @file        policies/edge/edge-node.rego
# @module      edge-policies
# @description OPA policy for edge node task execution governance

package edge.execution

import future.keywords.contains
import future.keywords.if

# Default deny - fail-closed
default allow = false

# Allow task execution if all conditions pass
allow if {
    task_type_eligible
    node_trust_sufficient
    sandbox_available
    resource_available
}

# Task types eligible for edge execution
task_type_eligible if {
    input.task_type in ["test_suite", "lint", "doc_generation", "build"]
}

# Deny GPU-intensive and security-sensitive tasks on edge
task_type_eligible if not {
    input.task_type in ["ai_inference", "deploy", "secret_access"]
}

# Node reputation must be >= 70 to execute code tasks
node_trust_sufficient if {
    input.node_reputation >= 70
}

# For lint tasks, allow nodes with reputation >= 50
node_trust_sufficient if {
    input.task_type == "lint"
    input.node_reputation >= 50
}

# Sandbox must be verified as working
sandbox_available if {
    input.sandbox_verified == true
}

# Resources must be available
resource_available if {
    cpu_available
    memory_available
}

# CPU availability check
cpu_available if {
    input.node_cpu_available > 0
}

# Memory availability check  
memory_available if {
    input.node_memory_available_mb > 512
}

# Block tasks if battery is critically low
deny["battery_critical"] if {
    input.node_battery_percent < 20
}

# Block tasks if node is in degraded state
deny["node_degraded"] if {
    input.node_health_score < 50
}

# Allow execution decision
allow_reason[reason] if {
    allow
    reason := "task_eligible_on_trusted_node"
}

# Explain denials
denial_reason[reason] if {
    deny[reason]
}

# Audit logging
audit if {
    {
        "timestamp": now,
        "node_id": input.node_id,
        "task_id": input.task_id,
        "task_type": input.task_type,
        "decision": "allowed" if allow else "denied",
        "reason": allow_reason[_] if allow else denial_reason[_],
    }
}
