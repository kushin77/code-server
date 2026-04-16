#
# P1 #388 - Phase 2: Service-to-Service Authentication
# Workload Federation, mTLS, and API Token Management
#

version: "1.0"
iam_issue: "P1 #388"
phase: 2

---

# Service-to-Service Authentication Overview
# Phase 2 enables identity and authorization for inter-service communication
# across three authentication mechanisms: Workload Federation (OIDC), mTLS, and API tokens

---

# 1. WORKLOAD FEDERATION (OIDC for GitHub Actions & K8s)
# Allows GitHub Actions workflows and K8s pods to obtain JWT tokens
# without storing long-lived secrets

workload_federation:
  
  # GitHub Actions CI/CD Workflow Federation
  github_actions:
    provider: "github"
    oidc_issuer: "https://token.actions.githubusercontent.com"
    
    # Subject claim format: repo:kushin77/code-server:ref:refs/heads/main
    subject_pattern: "repo:kushin77/code-server:ref:*"
    
    workflows:
      # Main branch deployments (highest privilege)
      - name: "deploy-prod"
        subject: "repo:kushin77/code-server:ref:refs/heads/main"
        role: "automation/operator"
        permissions:
          - "terraform:apply"
          - "docker:push"
          - "kubernetes:deployments"
          - "backstage:catalog"
        token_ttl_seconds: 900  # 15 minutes max
        audience: "kushin77/code-server"
      
      # Pull request workflows (limited privilege)
      - name: "ci-pull-request"
        subject: "repo:kushin77/code-server:pull_request"
        role: "automation/viewer"
        permissions:
          - "terraform:plan"
          - "docker:build"
          - "security:scan"
        token_ttl_seconds: 300  # 5 minutes max
        audience: "kushin77/code-server"
      
      # Release workflows
      - name: "release"
        subject: "repo:kushin77/code-server:ref:refs/tags/v*"
        role: "automation/operator"
        permissions:
          - "docker:push"
          - "github:releases"
          - "terraform:apply"
        token_ttl_seconds: 600  # 10 minutes max
        audience: "kushin77/code-server"
  
  # Kubernetes Workload Identity (Pod OIDC)
  kubernetes:
    provider: "kubernetes"
    
    # K8s OIDC issuer URL (self-hosted or cloud provider)
    oidc_issuer: "https://oidc.192.168.168.31.nip.io"
    
    # Service account to role mappings
    service_accounts:
      
      # Code-Server IDE (user sessions)
      - namespace: "prod"
        name: "code-server"
        role: "workload/viewer"
        permissions:
          - "code-server:execute"
          - "logs:write"
          - "metrics:export"
        identity_type: "workload"
        token_ttl_seconds: 3600  # 1 hour (long-lived for interactive sessions)
      
      # Backstage (software catalog)
      - namespace: "prod"
        name: "backstage"
        role: "workload/operator"
        permissions:
          - "backstage:catalog"
          - "github:api"
          - "kubernetes:services"
          - "metrics:read"
        identity_type: "workload"
        token_ttl_seconds: 3600
      
      # Appsmith (operational workflows)
      - namespace: "prod"
        name: "appsmith"
        role: "workload/operator"
        permissions:
          - "appsmith:workflows"
          - "deployments:execute"
          - "incidents:view"
        identity_type: "workload"
        token_ttl_seconds: 3600
      
      # Ollama (AI inference)
      - namespace: "prod"
        name: "ollama"
        role: "workload/viewer"
        permissions:
          - "ollama:inference"
          - "metrics:export"
        identity_type: "workload"
        token_ttl_seconds: 7200  # 2 hours
      
      # Prometheus (metrics collection)
      - namespace: "monitoring"
        name: "prometheus"
        role: "workload/viewer"
        permissions:
          - "prometheus:scrape"
          - "kubernetes:pods"
        identity_type: "workload"
        token_ttl_seconds: 3600
      
      # Loki (log aggregation)
      - namespace: "monitoring"
        name: "loki"
        role: "workload/viewer"
        permissions:
          - "loki:write"
          - "kubernetes:pods"
        identity_type: "workload"
        token_ttl_seconds: 3600

---

# 2. MTLS (Mutual TLS for Pod-to-Pod Communication)
# Optional layer for high-security service-to-service encryption
# Uses SPIFFE/SVID certificates issued automatically by control plane

mtls:
  
  enabled: true
  
  # Certificate management
  certificates:
    
    # CA certificate (root of trust)
    ca:
      subject: "CN=kushin-code-server-ca,O=kushin"
      validity_days: 3650  # 10 years
      issuer: "self-signed"  # or use external PKI
      storage: "kubernetes-secret:code-server-ca"
    
    # Workload certificates (auto-generated per pod)
    workload_cert:
      subject: "CN={{namespace}}/{{service_account}}"
      validity_days: 90
      auto_rotation_days: 30
      rotation_mechanism: "cert-manager or Spire controller"
      storage: "kubernetes-secret:{{pod-name}}-cert"
  
  # Service mesh configuration (Istio, Linkerd optional)
  service_mesh: "optional"
  
  # Pod-to-pod TLS enforcement matrix
  enforcement:
    
    # High-security paths (always require mTLS)
    - from: ["backstage", "appsmith"]
      to: ["code-server", "ollama", "kubernetes"]
      tls_required: true
      cipher_suites: ["TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"]
    
    # Medium-security paths (mTLS recommended)
    - from: ["prometheus", "loki"]
      to: ["all"]
      tls_required: false
      tls_recommended: true
    
    # Trust on first use (TOFU) for new services
    - from: "new-service"
      to: "all"
      tls_required: false
      comment: "Auto-upgrade to mTLS after first connection"

---

# 3. API TOKENS (Long-lived tokens for webhook integrations)
# Used for GitHub webhooks, Slack integrations, external API calls

api_tokens:
  
  # Token management
  management:
    
    # Token generation
    generation:
      algorithm: "HMAC-SHA256"  # or use JWTs
      length_bytes: 32
      encoding: "base64url"
    
    # Token storage
    storage:
      backend: "kubernetes-secret"
      encryption: "AES-256-GCM at rest"
      access_control: "RBAC"
    
    # Token rotation
    rotation:
      enabled: true
      schedule: "monthly"
      notification_days_before: 7
      old_token_grace_period: 24  # hours
  
  # Token types and scopes
  token_types:
    
    # GitHub Webhook Token
    github_webhook:
      name: "GitHub Webhook Auth"
      scope: ["github:webhook:verify"]
      validity_days: 365
      issuer: "code-server-iam"
      example_use: "HMAC signature verification for GitHub push/PR webhooks"
    
    # Slack Webhook Token
    slack_webhook:
      name: "Slack Webhook Auth"
      scope: ["slack:webhook"]
      validity_days: 90
      issuer: "code-server-iam"
      example_use: "Authentication for Slack app event callbacks"
    
    # DataDog Integration Token
    datadog:
      name: "DataDog Integration"
      scope: ["datadog:events", "datadog:metrics"]
      validity_days: 365
      issuer: "code-server-iam"
      example_use: "Send custom metrics to DataDog"
    
    # PagerDuty Integration Token
    pagerduty:
      name: "PagerDuty Integration"
      scope: ["pagerduty:incidents"]
      validity_days: 90
      issuer: "code-server-iam"
      example_use: "Trigger incidents from Appsmith"
    
    # External Service Token
    external_api:
      name: "External API Token"
      scope: ["external:api"]
      validity_days: 180
      issuer: "code-server-iam"
      example_use: "Partner API integrations"

---

# 4. SERVICE-TO-SERVICE CALL AUTHENTICATION FLOW

service_call_flows:
  
  # Example 1: Backstage → GitHub API
  backstage_github_api:
    flow:
      1: "Backstage pod starts (K8s service account: backstage)"
      2: "Kubernetes OIDC controller injects OIDC token into pod"
      3: "Backstage calls GitHub API with OIDC token"
      4: "IAM verifies token (issuer, subject, audience, signature)"
      5: "IAM checks role permissions (backstage SA has github:api permission)"
      6: "If authorized, token exchanged for GitHub token"
      7: "GitHub token used for REST API calls"
    
    implementation:
      - library: "google-auth Python library"
        config: "Application Default Credentials (ADC)"
      - or: "golang.org/x/oauth2/google"
    
    latency_sla: "p95 < 100ms"
  
  # Example 2: GitHub Actions → Deploy to Production
  github_actions_deploy:
    flow:
      1: "GitHub Actions workflow starts (repo:kushin77/code-server:ref:refs/heads/main)"
      2: "Workflow requests OIDC token from GitHub token endpoint"
      3: "GitHub issues token with subject claim = workflow identifier"
      4: "Workflow sends token to Terraform Cloud (or direct deployment)"
      5: "IAM validates token (GitHub OIDC issuer, subject pattern)"
      6: "Checks role (automation/operator) for terraform:apply permission"
      7: "If authorized, Terraform plan/apply proceeds"
    
    implementation:
      - action: "actions/github-script@v7"
        code: |
          const token = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
          const response = await fetch(process.env.ACTIONS_ID_TOKEN_REQUEST_URL);
          const oidc_token = await response.json();
          // Use oidc_token for authentication
    
    latency_sla: "p95 < 50ms (pre-auth token generation)"
  
  # Example 3: Appsmith → Kubernetes Deployments
  appsmith_k8s:
    flow:
      1: "Appsmith pod starts (K8s service account: appsmith)"
      2: "K8s OIDC injects token into pod"
      3: "Appsmith calls Kubernetes API (GET /api/v1/namespaces/*/deployments)"
      4: "K8s API server validates token (JWT signature, claims)"
      5: "RBAC policy checked: appsmith role has kubernetes:deployments permission"
      6: "If authorized, deployment list returned"
    
    implementation:
      - library: "kubernetes Python client"
        auth: "service_account_token"
      - mount_path: "/var/run/secrets/kubernetes.io/serviceaccount"
    
    latency_sla: "p95 < 150ms (includes K8s API latency)"

---

# 5. TOKEN VALIDATION ENDPOINTS

token_validation:
  
  # JWT Validation (for OIDC tokens)
  jwt_validation:
    endpoint: "http://iam-service:9000/validate/jwt"
    method: "POST"
    request:
      token: "eyJhbGciOiJSUzI1NiIsImtpZCI6In..."
      expected_issuer: "https://accounts.google.com"
      expected_audience: "kushin77-code-server"
    response:
      valid: true
      claims:
        sub: "user@example.com"
        iss: "https://accounts.google.com"
        aud: "kushin77-code-server"
        identity_type: "human"
        roles: ["operator"]
        mfa_verified: true
    
    validation_checks:
      - signature: "verify RSA signature with OIDC provider's public key"
      - issuer: "match expected iss claim"
      - audience: "match expected aud claim"
      - expiry: "check exp claim > current time"
      - nbf: "check nbf claim <= current time (not-before)"
      - identity_type: "verify identity_type claim"
  
  # Token Introspection (for opaque tokens)
  token_introspection:
    endpoint: "http://iam-service:9000/introspect"
    method: "POST"
    request:
      token: "hmac-sha256-token-abc123xyz"
      token_type: "api_token"
    response:
      active: true
      token_type: "github_webhook"
      exp: 1703030400
      iat: 1672430400
      scope: "github:webhook:verify"
    
    cache: "5 minutes (optional for performance)"

---

# 6. PHASE 2 IMPLEMENTATION CHECKLIST

implementation:
  
  step_1_github_oidc:
    - [ ] Register OIDC provider in Terraform (github_oidc_provider)
    - [ ] Configure subject claim patterns for main/PR/release workflows
    - [ ] Test token issuance from GitHub Actions
    - [ ] Validate token signature with GitHub's JWKS endpoint
  
  step_2_kubernetes_oidc:
    - [ ] Deploy Kubernetes OIDC controller (e.g., cert-manager or Spire)
    - [ ] Configure OIDC issuer URL (192.168.168.31 or cloud provider)
    - [ ] Create ServiceAccount → role mappings
    - [ ] Test pod OIDC token injection
    - [ ] Verify token structure and claims
  
  step_3_mtls:
    - [ ] Deploy cert-manager (or Spire for SPIFFE certificates)
    - [ ] Create CA certificate
    - [ ] Configure auto-rotation policy
    - [ ] Deploy mTLS enforcement policies (Istio/Linkerd optional)
    - [ ] Test pod-to-pod encrypted communication
  
  step_4_api_tokens:
    - [ ] Implement token generation/storage in secrets manager
    - [ ] Create Kubernetes Secret for GitHub webhook token
    - [ ] Test GitHub webhook signature verification
    - [ ] Implement token rotation cron job
    - [ ] Add token expiration alerts
  
  step_5_token_validation:
    - [ ] Deploy token validation microservice
    - [ ] Implement JWT validation endpoint
    - [ ] Implement token introspection endpoint
    - [ ] Add caching layer (Redis)
    - [ ] Load test: validate latency < 100ms p95
  
  step_6_service_call_testing:
    - [ ] Test Backstage → GitHub API call with OIDC token
    - [ ] Test GitHub Actions → Terraform deployment with OIDC
    - [ ] Test Appsmith → K8s API calls with K8s OIDC token
    - [ ] Test mTLS encryption for inter-pod calls
    - [ ] End-to-end latency testing
  
  step_7_audit_logging:
    - [ ] Log all token generation events (who, when, for which service)
    - [ ] Log token validation results (accepted/rejected, reason)
    - [ ] Log token rotation events
    - [ ] Log service-to-service call traces (correlation ID)
  
  step_8_documentation:
    - [ ] How to add a new service-to-service authentication
    - [ ] How to rotate tokens/certificates
    - [ ] How to troubleshoot authentication failures
    - [ ] Emergency break-glass token access procedure

---

# 7. ARCHITECTURE DIAGRAM

#
#  GitHub Actions                K8s Cluster (192.168.168.31)
#  ───────────────               ────────────────────────────
#
#  [CI/CD Workflow]              [Backstage] ──OIDC──> [IAM Service]
#       │                              │                    │
#       │ requests OIDC token          │                    │ validates JWT
#       │                              │                    │
#       v                              v                    v
#  [GitHub OIDC]     (1)          [K8s OIDC Controller]  [Token Validation]
#       │                              │
#       │ issues token                 │ injects token
#       v                              v
#  [Token]                         [Pod OIDC Token]
#       │                              │
#       │ deploy to K8s                │ call IAM service
#       v                              v
#  [K8s API] ◄──────────────────────────────────────────────┘
#       │
#       │ RBAC enforcement
#       v
#  [Deployment Update]

---

# 8. EFFORT ESTIMATE

effort:
  
  step_1_github_oidc: "2-3 hours"
  step_2_kubernetes_oidc: "3-4 hours"
  step_3_mtls: "4-6 hours (depends on cert-manager/Spire choice)"
  step_4_api_tokens: "2-3 hours"
  step_5_token_validation: "3-4 hours"
  step_6_service_call_testing: "4-5 hours"
  step_7_audit_logging: "2-3 hours"
  step_8_documentation: "1-2 hours"
  
  total: "21-30 hours (2-3 days)"
  
  blockers:
    - "cert-manager or Spire deployment complexity"
    - "K8s OIDC issuer URL configuration (cloud-provider specific)"
    - "Token validation service latency testing"

---

# 9. RISKS & MITIGATION

risks:
  
  high_latency_token_validation:
    risk: "Token validation adds 100-500ms latency per service call"
    mitigation: "Implement caching (Redis), async validation, or pre-validation"
  
  token_expiration_storms:
    risk: "All tokens expire at once, causing thundering herd"
    mitigation: "Implement staggered token expiration times"
  
  certificate_rotation_failure:
    risk: "Old certificate expired before new one distributed"
    mitigation: "Overlap rotation window (30 days), automated rollout with health checks"
  
  oidc_provider_outage:
    risk: "If GitHub or cloud OIDC provider is down, can't get tokens"
    mitigation: "Local Keycloak fallback, cache recently validated tokens"

---

# 10. SUCCESS CRITERIA

success:
  - [ ] All 5 service-to-service authentication pairs working (Backstage→GitHub, Appsmith→K8s, etc.)
  - [ ] Token validation latency < 100ms p95 (with caching)
  - [ ] Zero authentication failures in staging for 48 hours
  - [ ] Audit logs show 100% of service calls with correlation IDs
  - [ ] Automatic token/certificate rotation working without manual intervention
  - [ ] Break-glass token access documented and tested
  - [ ] Load test: 1000 concurrent service calls authenticated successfully
