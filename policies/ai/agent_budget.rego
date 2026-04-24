# @file agent_budget.rego
# @module policies/ai
# @description Enforce compute/cost budget limits for autonomous agents
# @governance GOV-003 - Cost Management

package ai.agent_budget

import future.keywords.if
import future.keywords.contains

# Agent monthly budgets (in credits)
agent_budgets := {
    "default": 1000,
    "trusted": 5000,
    "enterprise": 50000,
}

# Agent cost per operation
operation_costs := {
    "model_inference": 10,
    "vector_search": 5,
    "terraform_apply": 50,
    "ci_job": 25,
}

# Deny operation if agent budget exhausted
deny[msg] {
    input.action == "execute_operation"
    input.actor_type == "agent"
    input.agent_tier
    agent_budgets[input.agent_tier]
    budget := agent_budgets[input.agent_tier]
    input.current_spend >= budget
    msg := sprintf("Agent budget exhausted: %d/%d credits used", 
        [input.current_spend, budget])
}

# Deny operation if would exceed remaining budget
deny[msg] {
    input.action == "execute_operation"
    input.actor_type == "agent"
    input.agent_tier
    input.operation_type
    operation_costs[input.operation_type]
    cost := operation_costs[input.operation_type]
    budget := agent_budgets[input.agent_tier]
    input.current_spend + cost > budget
    remaining := budget - input.current_spend
    msg := sprintf("Operation would exceed budget: costs %d credits, only %d remaining", 
        [cost, remaining])
}

# Deny high-cost operations for low-tier agents
deny[msg] {
    input.action == "execute_operation"
    input.actor_type == "agent"
    input.agent_tier == "default"
    input.operation_type == "terraform_apply"
    msg := "High-cost operation 'terraform_apply' restricted to trusted+ agents"
}

# Allow operation if within budget
allow[msg] {
    input.action == "execute_operation"
    input.actor_type == "agent"
    input.agent_tier
    input.operation_type
    operation_costs[input.operation_type]
    budget := agent_budgets[input.agent_tier]
    cost := operation_costs[input.operation_type]
    input.current_spend + cost <= budget
    remaining := budget - input.current_spend - cost
    msg := sprintf("Operation approved: %d credits used, %d remaining", 
        [cost, remaining])
}

# Track budget usage for alert thresholds
budget_warning[msg] {
    input.action == "check_budget"
    input.actor_type == "agent"
    input.agent_tier
    budget := agent_budgets[input.agent_tier]
    input.current_spend > budget * 0.8
    percent := (input.current_spend * 100) / budget
    msg := sprintf("Agent approaching budget limit: %d%% used", [percent])
}
