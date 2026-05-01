# OPA Policy Engine Guide

## Overview

The **Open Policy Agent (OPA)** is the authoritative policy enforcement layer for ElevatedIQ DevOS. All critical decisions—from production deployments to AI model access—flow through OPA's Rego-based policy engine before execution.

**Status**: ✅ **Deployed**  
**Deployment Date**: April 24, 2026  
**Policy Coverage**: Core (3) + AI (3) + Identity (3) + Infrastructure (3) policies  
**Enforcement Points**: 5+ (Caddy, Agent Runtime, Terraform, CI/CD, Prompt Gateway)

---

## Quick Start

### 1. Start OPA Locally

```bash
# Start all services including OPA
docker-compose up -d

# Verify OPA is running
curl http://localhost:8181/health

# Check policy bundles loaded
curl http://localhost:8181/v1/data/core
```

### 2. Test a Policy Decision

```bash
# Test production gate policy
curl -X POST http://localhost:8181/v1/data/core/production_gate -d '{
  "input": {
    "action": "deploy",
    "target_env": "production",
    "human_approved": false,
    "approval_required": true
  }
}'

# Response will include deny/allow rules
```

### 3. Write Your First Policy

```bash
# Create a new Rego policy file
vi policies/custom/my-policy.rego

# Add policy logic
package custom.my_policy

deny[msg] {
    input.action == "forbidden_action"
    msg := "This action is forbidden"
}

# Reload OPA to apply (or wait for auto-reload)
curl -X POST http://localhost:8181/v1/system/policies/my_policy
```

---

## Policy Organization

```
policies/
├── core/                          # Core governance policies
│   ├── audit.rego                # Audit logging enforcement
│   ├── least_privilege.rego       # ABAC enforcement
│   ├── production_gate.rego       # Production deployment approval
│   └── secrets.rego               # Secret protection
├── ai/                            # AI/ML policies
│   ├── agent_budget.rego          # Agent cost/compute limits
│   ├── model_allowlist.rego       # Approved model gating
│   └── prompt_safety.rego         # PII/secret detection in prompts
├── identity/                      # Authentication & authorization
│   ├── device_trust.rego          # Device compliance checks
│   ├── reputation_gate.rego       # Reputation-based access
│   └── sso_required.rego          # SSO enforcement
├── infrastructure/                # Infrastructure governance
│   ├── drift_prevention.rego      # Infrastructure drift detection
│   ├── immutable_infra.rego       # Immutability enforcement
│   └── no_hardcoded_ips.rego      # IaC hardcoded value prevention
└── tests/                         # Policy test suite
    ├── core_test.rego
    ├── ai_test.rego
    ├── identity_test.rego
    └── infrastructure_test.rego
```

---

## Policy Reference

### Core Policies

#### `production_gate.rego` - Production Deployment Approval
**Purpose**: No production deployments without human approval  
**Enforcement Points**: CI/CD pipeline, Terraform, kubectl  
**Key Rules**:
- ❌ Deny: Automated deploy to production without explicit token
- ✅ Allow: Deploy if `human_approved=true` and audit trail exists

**Example**:
```bash
curl -X POST http://localhost:8181/v1/data/core/production_gate -d '{
  "input": {
    "action": "deploy",
    "target_env": "production",
    "human_approved": true,
    "approved_by": "architect",
    "approval_timestamp": "2026-04-24T10:00:00Z",
    "audit_id": "PR-1234"
  }
}'
# Returns: allow["Production deployment approved..."]
```

#### `secrets.rego` - Secret Protection
**Purpose**: Prevent secrets from leaving the security boundary  
**Enforcement Points**: Logging, HTTP calls, CI/CD  
**Key Rules**:
- ❌ Deny: Secret patterns in logs (password, token, api_key, etc.)
- ❌ Deny: Secrets transmitted over unencrypted HTTP
- ✅ Allow: HTTPS requests without secrets

#### `least_privilege.rego` - ABAC (Attribute-Based Access Control)
**Purpose**: Enforce minimum required permissions  
**Enforcement Points**: All resource access, high-privilege operations  
**Key Attributes**:
- `actor_reputation_score` (0-100)
- `actor_tier` (1-4, where 4=admin)
- `resource_classification` (public, internal, confidential, restricted)
- `operation_type` (read, write, delete, modify_policy)

**Example**:
```bash
# User with reputation 50 cannot delete (requires 85)
curl -X POST http://localhost:8181/v1/data/core/least_privilege -d '{
  "input": {
    "action": "delete_resource",
    "actor_reputation_score": 50
  }
}'
# Returns: deny["High-privilege operation 'delete_resource' denied..."]
```

#### `audit.rego` - Audit Trail
**Purpose**: All sensitive actions are logged for compliance  
**Enforcement Points**: All decision points  
**Audit Fields**: timestamp, actor, action, resource, result

### AI Policies

#### `model_allowlist.rego` - Approved Model Gating
**Purpose**: Only approved models can be invoked, with reputation gating  
**Approved Models**:
- `llama3:8b` (min reputation: 40)
- `claude-3-opus` (min reputation: 70)
- `gpt-4` (min reputation: 80)

**Key Rules**:
- ❌ Deny: Unapproved model requests
- ❌ Deny: Insufficient reputation for model tier
- ✅ Allow: Reputation >= minimum threshold

#### `agent_budget.rego` - Agent Cost Control
**Purpose**: Agents have monthly budgets to prevent runaway costs  
**Agent Tiers & Budgets**:
- Default: 1,000 credits/month
- Trusted: 5,000 credits/month
- Enterprise: 50,000 credits/month

**Operation Costs**:
- `model_inference`: 10 credits
- `vector_search`: 5 credits
- `terraform_apply`: 50 credits
- `ci_job`: 25 credits

**Example**:
```bash
# Agent approaching budget limit (80%+ usage)
curl -X POST http://localhost:8181/v1/data/ai/agent_budget -d '{
  "input": {
    "action": "check_budget",
    "actor_type": "agent",
    "agent_tier": "default",
    "current_spend": 850
  }
}'
# Returns: budget_warning["Agent approaching budget limit: 85% used"]
```

#### `prompt_safety.rego` - PII/Secret Detection
**Purpose**: Scan prompts for PII and secrets before LLM invocation  
**Patterns Detected**:
- Email addresses, phone numbers, SSN patterns
- API keys, credentials, tokens
- Classified data markers

### Identity Policies

#### `sso_required.rego` - SSO Enforcement
**Purpose**: All user-facing services require authentication  
**Enforcement Points**: Caddy middleware, oauth2-proxy  
**Supported Providers**:
- GitHub OAuth2
- Keycloak
- oauth2-proxy (generic)

#### `device_trust.rego` - Device Compliance
**Purpose**: Enforce device trust scores for sensitive operations  
**Trust Score Thresholds**:
- `read_data`: 0+ (any device)
- `write_data`: 30+
- `delete_data`: 60+
- `access_secrets`: 80+
- `deploy_prod`: 90+

**Trust Score Adjustments**:
- +5 points: Successful secure operation
- -20 points: Suspicious activity
- -50 points: Security incident

#### `reputation_gate.rego` - Reputation-Based Access
**Purpose**: Use actor reputation score to gate sensitive operations  
**Reputation Tiers**:
- 0-30: Basic operations only
- 30-50: Config modifications
- 50-80: Non-prod deployments
- 80-90: Prod deployments
- 90+: Policy modifications

**Reputation Gains/Losses**:
- +5: Successful prod deployment
- +10: Bug fix or security patch
- -5: Failed operation
- -25: Policy violation
- -50: Security incident

### Infrastructure Policies

#### `immutable_infra.rego` - Immutability Enforcement
**Purpose**: All infrastructure changes must go through IaC (Terraform/Docker Compose)  
**Key Rules**:
- ❌ Deny: SSH modifications to production hosts
- ❌ Deny: Direct `docker exec` modifications
- ❌ Deny: Floating image tags (`:latest`, `:main`) in production
- ✅ Allow: Changes from Git commits with immutable digests

#### `drift_prevention.rego` - Drift Detection
**Purpose**: Detect and prevent infrastructure drift  
**Key Rules**:
- ❌ Deny: Deploy if drift check not run (>24h old)
- ❌ Deny: Manual changes to IaC-managed resources
- ❌ Deny: Unreconciled drift detected
- ✅ Allow: Drift-free state with recent check
- 🚨 Alert: Drift >10% triggers P1 alert

**Drift Detection Workflow**:
```
1. Run drift detection: scripts/ops/detect-drift.sh
2. OPA evaluates: infrastructure.drift_prevention
3. If drift > 5%: Auto-reconciliation or manual approval required
4. On reconcile: Changes go through terraform apply + git commit
5. Audit logged with commit SHA
```

---

## Integration Points

### 1. Caddy Gateway Integration

**File**: `config/caddy/Caddyfile`

OPA middleware validates every incoming request:

```caddy
# All requests to protected endpoints require valid JWT
@protected_endpoints path /api/* /admin/*

handle @protected_endpoints {
    # Validate SSO token via OPA
    forward_auth http://opa:8181 {
        uri /v1/data/identity/sso_required?input={...}
        copy_headers Authorization
    }
    # If OPA denies, forward_auth returns 401
}
```

### 2. Agent Runtime Integration

**File**: `apps/execution-scheduler/main.py`

Before agent execution:

```python
import requests

def check_policy(action, context):
    """Query OPA before agent action"""
    response = requests.post(
        "http://opa:8181/v1/data/ai/agent_budget",
        json={"input": context}
    )
    
    if response.json().get("result", {}).get("deny"):
        raise PermissionError(response.json()["result"]["deny"][0])
    
    return True  # Action approved
```

### 3. Terraform Integration

**File**: `terraform/.conftest`

OPA policies validated before apply:

```bash
# In CI: conftest test terraform/
conftest test terraform/environments/production/main.tf

# Tests all infrastructure policies
# Returns: PASS if no violations
```

### 4. CI/CD Integration

**File**: `.github/workflows/policy-check.yml`

Every PR validates policies:

```yaml
- name: Validate OPA Policies
  run: |
    conftest test policies/
    # Runs all *_test.rego files
    # Fails if any test fails
```

---

## Decision Log & Observability

### Viewing Decision Logs

```bash
# Stream OPA decisions in real-time
docker logs -f opa-service

# Query decision history
curl http://localhost:8181/v1/logs

# Export to Loki (already configured in docker-compose)
# Access via Grafana: http://localhost:3000
# Dashboard: OPA Decisions → Allow/Deny Rate by Policy
```

### Prometheus Metrics

OPA exposes Prometheus metrics:

```
# Policy evaluation latency
opa_compiler_compile_duration_ns
opa_eval_op_builtin_duration_ns

# Decision outcomes
opa_eval_decision_results

# Bundle loading
opa_bundle_load_duration_ns
```

**View in Grafana**:
- Dashboard: "OPA Policy Metrics"
- Panels: Decision rate, latency, policy violations

### Alerts

Pre-configured alerts in `monitoring/prometheus-rules.yaml`:

| Alert | Condition | Action |
|-------|-----------|--------|
| `OPAPolicyDenySpike` | Deny rate > 2x baseline | Investigate misconfiguration |
| `OPAEvalLatencyHigh` | Eval latency > 100ms | Optimize policies |
| `OPABundleLoadFailed` | Bundle reload fails | Manual intervention |

---

## Common Scenarios

### Scenario 1: Deploy to Production

**Workflow**:
1. Engineer creates PR with Terraform changes
2. CI runs: `conftest test terraform/` → infrastructure policies checked
3. CI runs: Policy validation → `production_gate` checked
4. PR requires code review + approval
5. On merge: GitHub Actions triggers `apply-terraform.yml`
6. OPA checks: `input.human_approved=true` (from PR approval)
7. Terraform apply executes
8. Audit logged with commit SHA, reviewer, timestamp

**OPA Query**:
```bash
curl -X POST http://localhost:8181/v1/data/core/production_gate -d '{
  "input": {
    "action": "deploy",
    "target_env": "production",
    "human_approved": true,
    "approved_by": "lead-architect",
    "approval_timestamp": "2026-04-24T15:30:00Z",
    "audit_id": "gh-pr-4521"
  }
}'
```

### Scenario 2: Agent Requests Model Access

**Workflow**:
1. Agent `researcher-v2` wants to call `claude-3-opus` model
2. Execution scheduler queries OPA: `model_allowlist`
3. OPA checks: Agent reputation score = 65, model requires 70
4. OPA denies with message: "Insufficient reputation: 65 (required 70)"
5. Agent escalates to human for approval or downgrades to `llama3:8b`
6. Audit logged with agent ID, requested model, reason

**OPA Query**:
```bash
curl -X POST http://localhost:8181/v1/data/ai/model_allowlist -d '{
  "input": {
    "action": "invoke_model",
    "model_name": "claude-3-opus",
    "actor_id": "researcher-v2",
    "actor_reputation_score": 65,
    "current_concurrent_count": 0
  }
}'
# Returns: deny["Model 'claude-3-opus' requires minimum reputation 70..."]
```

### Scenario 3: Drift Detection

**Workflow**:
1. Scheduled job runs: `scripts/ops/detect-drift.sh`
2. Compares: Terraform state vs. actual infrastructure
3. Drift detected: 3 security groups have manual rules
4. OPA evaluates: `drift_prevention` policy
5. OPA generates alerts: "Drift detected: 5% (3/60 resources)"
6. Escalation: Create issue for manual reconciliation
7. Engineer runs: `terraform apply` (updates state)
8. Reconciliation logged with engineer ID, reason, commit SHA

**OPA Query**:
```bash
curl -X POST http://localhost:8181/v1/data/infrastructure/drift_prevention -d '{
  "input": {
    "action": "deploy",
    "target_env": "production",
    "drift_report": {
      "drift_free": false,
      "drift_percentage": 5,
      "unreconciled_resources": []
    },
    "last_drift_check_age_hours": 2
  }
}'
# Returns: deny["Terraform state drift exceeds 5%..."]
```

---

## Policy Development Guide

### Writing a New Policy

1. **Create policy file**:
```bash
vi policies/custom/my_policy.rego
```

2. **Define package and imports**:
```rego
package custom.my_policy

import future.keywords.if
import future.keywords.contains
```

3. **Write deny and allow rules**:
```rego
# Deny rules return violation messages
deny[msg] {
    input.action == "forbidden"
    msg := "This action is forbidden"
}

# Allow rules return approval messages
allow[msg] {
    input.action == "permitted"
    msg := "Action approved"
}
```

4. **Write tests**:
```bash
vi policies/tests/custom_test.rego
```

```rego
package custom.my_policy_test

test_deny_forbidden {
    deny[msg] with input as {"action": "forbidden"}
    count(deny) > 0
}

test_allow_permitted {
    allow[msg] with input as {"action": "permitted"}
    count(allow) > 0
}
```

5. **Run tests**:
```bash
conftest test policies/
```

6. **Deploy**:
```bash
git add policies/
git commit -m "feat(policies): Add custom policy"
git push origin main
# OPA auto-loads from git on next sync
```

### Testing Locally

```bash
# Run all tests
conftest test policies/

# Run specific policy tests
conftest test policies/tests/core_test.rego

# Test against specific input
conftest test -d input.json policies/

# Verbose output
conftest test -v policies/
```

---

## Troubleshooting

### OPA Not Responding

```bash
# Check if running
docker ps | grep opa

# Check logs
docker logs opa-service

# Verify health
curl http://localhost:8181/health
```

### Policy Not Enforced

```bash
# Verify policy bundle loaded
curl http://localhost:8181/v1/data/core

# Check policy syntax
conftest test policies/

# Verify integration point calling OPA
# E.g., check Caddy config is routing to OPA
grep "opa:8181" config/caddy/Caddyfile
```

### Test Failures

```bash
# Run tests with full output
conftest test -v policies/

# Check policy logic
vi policies/core/your_policy.rego

# Update test expectations
vi policies/tests/your_test.rego
```

---

## Security Considerations

### ✅ What OPA Provides

- **Centralized policy**: Single source of truth for all governance rules
- **Audit trail**: Every decision logged with context
- **Atomic enforcement**: Deny by default, allow only approved actions
- **Human-in-the-loop**: Integration with approval workflows
- **Reputation system**: Actors build trust over time

### ⚠️ What OPA Does NOT Provide

- **Encryption**: Use TLS for OPA network communication
- **Authentication**: Use Caddy middleware for user auth (OPA validates access)
- **Secret storage**: Use GSM/HashiCorp Vault for secrets (OPA protects against leakage)
- **Physical security**: Infrastructure must be physically secure

### Best Practices

1. **Always have deny rules first**: Default-deny, then explicitly allow
2. **Test policies thoroughly**: Run conftest before merging policy changes
3. **Review policy changes**: All policy changes require peer review (branch protection)
4. **Monitor alerts**: Set up Slack/PagerDuty notifications for policy violations
5. **Audit logs**: Export decision logs to Loki for long-term retention
6. **Version control**: All policies in Git, never inline configurations

---

## Next Steps

- [ ] Deploy OPA to production hosts (192.168.168.31/42)
- [ ] Integrate with all services (Caddy, Agent Runtime, Terraform, Prompt Gateway)
- [ ] Set up monitoring dashboards in Grafana
- [ ] Configure alerting (Slack notifications for policy violations)
- [ ] Run end-to-end tests (e.g., verify prod deploy is blocked without approval)
- [ ] Document runbooks for policy violations
- [ ] Schedule quarterly policy audits

---

**Last Updated**: April 24, 2026  
**Document Owner**: Enterprise Architecture  
**Feedback**: Create issue in kushin77/code-server with label `[OPA-Policy]`
