# Federation Service — Federated Trust Exchange

## Overview

The Federation Service enables secure cross-organization collaboration for ElevatedIQ instances. Two or more organizations can establish cryptographic trust relationships and delegate agent execution across boundaries while maintaining data sovereignty and compliance requirements.

**Key Features:**
- **Cryptographic Trust**: Signed JWT challenges and mutual trust ceremonies
- **Delegated Execution**: Agents with dual identity (source org + remote org context)
- **Dual Policy Enforcement**: Both source and remote OPA policies must approve
- **Data Boundary Protection**: Confidential data never crosses org boundaries
- **Reputation Portability**: Engineer/agent scores partially transferable (70% default)
- **Trust Revocation**: Immediate propagation with 60-second SLA

---

## Architecture

```
Organization A (Source)          Organization B (Target)
┌─────────────────────────┐     ┌─────────────────────────┐
│ Agent Registry          │     │ OPA Gatekeeper          │
│ • review-agent-1        │     │ • federation.rego       │
└──────────┬──────────────┘     └──────────┬──────────────┘
           │                               │
           │   1. Challenge-Response       │
           ├──────────────────────────────┤
           │   2. Trust Certificate JWT   │
           │                               │
       ┌───▼──────────────────────────────▼───┐
       │ Federation Service (Port 8081)       │
       │ ├─ /federation/trust/initiate        │
       │ ├─ /federation/trust/confirm         │
       │ ├─ /federation/agent/delegate       │
       │ ├─ /federation/reputation/transfer  │
       │ ├─ /federation/trust/revoke         │
       │ └─ /federation/health               │
       └───┬───────────────────────────────────┘
           │
           │  3. Delegation Creation
           │     (dual policy check)
           │
       ┌───▼──────────────────────────────┐
       │ Delegation Engine                │
       │ • Dual OPA enforcement           │
       │ • Audit logging (both orgs)      │
       │ • Agent context management       │
       └────────────────────────────────────┘
```

---

## Trust Establishment Protocol

### Step 1: Initiate Trust
**Request (Org A):**
```bash
curl -X POST http://federation-b:8081/federation/trust/initiate \
  -H "Content-Type: application/json" \
  -d '{"remote_org": "org-a", "remote_endpoint": "https://federation-a.example.com"}'
```

**Response:**
```json
{
  "status": "challenge_created",
  "challenge": "eyJhbGciOiJSUzI1NiIs...",
  "expires_in_seconds": 300
}
```

### Step 2: Confirm Trust
**Request (Org B):** Sign challenge with org B private key, send back

```bash
curl -X POST http://federation-a:8081/federation/trust/confirm \
  -H "Content-Type: application/json" \
  -d {
    "remote_org": "org-b",
    "signed_challenge": "eyJhbGciOiJSUzI1NiIs...",
    "capabilities": ["delegation", "reputation_transfer"]
  }
```

**Response:**
```json
{
  "status": "trust_established",
  "org_id": "org-b",
  "certificate": "eyJhbGciOiJSUzI1NiIs...",
  "expires_at": "2026-07-23T10:00:00Z"
}
```

**Result:** Bidirectional trust established for 90 days

---

## Cross-Org Agent Delegation

### Create Delegation

**Request:**
```bash
curl -X POST http://federation:8081/federation/agent/delegate \
  -H "Content-Type: application/json" \
  -d '{
    "remote_org": "partner-inc",
    "agent_id": "review-agent-1",
    "task": {
      "type": "code_review",
      "pr_id": 1234,
      "repository": "main"
    },
    "org_policies": {...}  # Partner's OPA policy
  }'
```

**Response:**
```json
{
  "status": "delegated",
  "delegation_id": "del-uuid-1234",
  "remote_execution_id": "exec-uuid-5678"
}
```

### Dual OPA Enforcement

Delegated agent subject to **both** policies:

1. **Source Org Policy** (where agent originated)
   - Controls which tasks agents can execute
   - Enforces org's compliance requirements

2. **Target Org Policy** (where agent executes)
   - Controls which capabilities agent can use
   - Enforces target org's security boundaries

**Both policies must approve**, or delegation is blocked:

```rego
# Example: Source org blocks credential access
deny[msg] {
    input.task_type == "credential_access"
    msg := "Credential access not allowed by source org"
}

# Example: Target org blocks external API calls
deny[msg] {
    input.capability == "external_api_call"
    msg := "External API calls not allowed in target org"
}
```

### Delegation Audit Logging

Every delegation triggers audit events in **both** orgs:

```json
{
  "event_type": "delegation_created",
  "delegation_id": "del-uuid-1234",
  "source_org": "elevatediq",
  "remote_org": "partner-inc",
  "agent_id": "review-agent-1",
  "status": "approved",
  "timestamp": "2026-04-23T10:00:00Z"
}
```

Logged to Kafka topic: `federation.audit`

---

## Reputation Portability

### Engineer Reputation Transfer (Partial)

**Formula:**
```
transferred_score = home_score × FEDERATION_TRUST_WEIGHT
```

**Default:** `FEDERATION_TRUST_WEIGHT = 0.7` (70%)

**Example:**
```
Engineer "alice" in Org A:
  home_score = 85/100
  transferred_score = 85 × 0.7 = 59.5/100

Alice joins Org B:
  starting_score = 59.5/100 (from transfer)
  later builds to 80/100 through work
```

### Agent Reputation Transfer (Fully Portable)

**Formula:**
```
agent_transferred_score = agent_score × 1.0  # 100% portable
```

Agent reputation is objective (based on task success) and fully portable:

```
Agent "review-agent-1" in Org A:
  success_rate = 0.95 (95%)
  agent_score = 95/100
  transferred_score = 95/100 (no reduction)

Agent deployed to Org B:
  starting_score = 95/100
```

### Anomaly Detection

Automatic flagging of suspicious transfers:

- **Multiple transfers within 1 hour** → suspicious
- **Score jump > 50 points** → suspicious
- **Transfer to untrusted org** → suspicious

Marked transfers available in audit log:

```python
anomalies = reputation_sync.detect_anomalies()
# Returns: [
#   {"engineer_id": "alice", "home_score": 10, "transferred_score": 90},  # Flagged!
# ]
```

---

## Data Boundary Enforcement

### Classification Levels

| Level | Portability | Rule |
|-------|-------------|------|
| **public** | ✅ Auto-portable | No restrictions |
| **internal** | ⚠️ Declared only | Must explicitly declare cross-org sharing |
| **confidential** | ❌ Blocked | Requires human approval to transfer |

### Configuration

```yaml
# config/federation.yaml
data_classifications:
  public:
    - README files
    - Architecture docs
  
  internal:
    - Proprietary algorithms
    - Internal documentation
  
  confidential:
    - Customer data
    - Trade secrets
    - Security keys
    - Employee records

cross_org_shares:
  - source: elevatediq
    target: partner-inc
    allows_internal: true  # Can share internal data
    requires_approval: false
```

### OPA Enforcement

```rego
# DENY: Confidential data cannot cross boundary
deny[msg] {
    input.data_classification == "confidential"
    msg := "Confidential data transfer blocked by OPA"
}

# DENY: Internal data requires explicit declaration
deny[msg] {
    input.data_classification == "internal"
    not declared_cross_org_share(input.source_org, input.target_org)
    msg := "Internal data sharing not declared"
}

# ALLOW: Public data always portable
allow {
    input.data_classification == "public"
}
```

---

## Trust Revocation

### Immediate Revocation

```bash
curl -X POST http://federation:8081/federation/trust/revoke \
  -H "Content-Type: application/json" \
  -d '{"remote_org": "partner-inc"}'
```

**Response:**
```json
{
  "status": "trust_revoked",
  "org_id": "partner-inc",
  "delegations_cancelled": 3
}
```

### Revocation Effects

1. ✅ Trust record marked `revoked`
2. ✅ All delegations immediately cancelled
3. ✅ Running agents terminated (within 60s)
4. ✅ Reputation transfers stopped
5. ✅ Audit event published to both orgs

### Revocation SLA

- **Challenge Response**: < 5 seconds
- **Trust Establishment**: < 30 seconds
- **Delegation Creation**: < 10 seconds
- **Revocation Propagation**: < 60 seconds

---

## API Reference

### POST /federation/trust/initiate

Initiate trust with remote organization.

**Parameters:**
- `remote_org` (string): Target org ID
- `remote_endpoint` (string): Federation service URL

**Returns:** Challenge JWT (valid 5 minutes)

---

### POST /federation/trust/confirm

Confirm trust by signing challenge.

**Parameters:**
- `remote_org` (string): Org that sent challenge
- `signed_challenge` (string): Challenge signed with org's private key
- `capabilities` (array): Allowed capabilities (delegation, etc.)

**Returns:** Trust certificate JWT (valid 90 days)

---

### POST /federation/agent/delegate

Delegate agent to remote organization.

**Parameters:**
- `remote_org` (string): Target org
- `agent_id` (string): Agent to delegate
- `task` (object): Task to execute
- `org_policies` (object): Target org's OPA policies

**Returns:** Delegation ID + remote execution ID

---

### POST /federation/reputation/transfer

Transfer engineer reputation score.

**Parameters:**
- `engineer_id` (string): Engineer ID
- `remote_org` (string): Target org
- `home_score` (float): Score in home org (0-100)

**Returns:** Transferred score (home_score × trust_weight)

---

### POST /federation/trust/revoke

Revoke trust relationship.

**Parameters:**
- `remote_org` (string): Org to revoke

**Returns:** Count of cancelled delegations

---

### GET /federation/trust/list

List all active trusts.

**Returns:** Array of trust records

---

### GET /federation/delegations/active

List all active delegations.

**Returns:** Array of delegation records

---

### GET /federation/health

Health check.

**Returns:** Service status + active counts

---

## Testing

### Run Test Suite

```bash
pytest apps/federation/test_federation.py -v
```

### Test Coverage

- ✅ Trust establishment and verification
- ✅ Challenge-response protocol
- ✅ Trust expiration
- ✅ Delegation creation and execution
- ✅ Dual OPA policy enforcement
- ✅ Reputation portability
- ✅ Anomaly detection
- ✅ Trust revocation and cleanup
- ✅ Full federation workflow

---

## Deployment

### Docker Compose

```yaml
federation:
  image: elevatediq/federation:latest
  ports:
    - "8081:8081"
  environment:
    ORG_ID: elevatediq
    ORG_PRIVATE_KEY: ${ORG_PRIVATE_KEY}
    ORG_PUBLIC_KEY: ${ORG_PUBLIC_KEY}
    FEDERATION_TRUST_WEIGHT: 0.7
  volumes:
    - ./policies/federation:/opt/policies:ro
  depends_on:
    - kafka
    - opa
```

### Environment Variables

- `ORG_ID`: Organization identifier
- `ORG_PRIVATE_KEY`: RSA private key (PEM format)
- `ORG_PUBLIC_KEY`: RSA public key (PEM format)
- `FEDERATION_TRUST_WEIGHT`: Score reduction factor (default: 0.7)
- `TRUST_EXPIRY_DAYS`: Trust certificate lifetime (default: 90)

---

## Security Considerations

### Cryptography
- ✅ JWT signing: RS256 (RSA 2048-bit minimum)
- ✅ Data encryption: TLS 1.3 end-to-end
- ✅ Challenge replay protection: Expiry + one-time use

### Data Boundaries
- ✅ Confidential data never crosses without approval
- ✅ All transfers encrypted with org public key
- ✅ End-to-end encryption (no plaintext in federation service)

### Audit Trail
- ✅ Every delegation logged
- ✅ Both orgs receive audit events
- ✅ Tamper-proof: signed by federation service

### OPA Policies
- ✅ Fail-closed: default deny
- ✅ Dual enforcement: both policies must approve
- ✅ Capability whitelist: only declared capabilities allowed

---

## Links

- **Source**: `apps/federation/`
- **Policy**: `policies/federation/cross-org.rego`
- **Tests**: `apps/federation/test_federation.py`
- **Issue**: #1564 (Federated Trust Exchange)
- **Epic**: #1563 (Phase 3 — Federation & Enterprise Scale)

