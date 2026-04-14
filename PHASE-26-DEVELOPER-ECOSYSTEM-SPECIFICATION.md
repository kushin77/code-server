# PHASE 26: Developer Ecosystem - Complete Specification

**Status**: 🔴 BLOCKED (awaiting Phase 22-E baseline - July 22, 2026)  
**Timeline**: July 22 - August 12, 2026 (3 weeks, 40-50 hours)  
**Priority**: P0 - Final infrastructure completion  
**Owner**: Infrastructure + Developer Tools Team

---

## EXECUTIVE SUMMARY

Phase 26 represents the **FINAL comprehensive phase** delivering a complete developer ecosystem on top of production-ready infrastructure built by Phases 22-B through 22-E.

**Mission**: Enable developers to build, deploy, and monetize applications on code-server through unified REST/GraphQL APIs, multi-language SDKs, powerful CLI tools, and AI-assisted code generation.

**Blocking Dependency**: Phase 22-E (Compliance Automation) must complete baseline deployment (July 22, 2026).

---

## PHASE DEPENDENCIES (ALL COMPLETE ✅)

| Phase | Category | Component | Status | Delivery |
|-------|----------|-----------|--------|----------|
| 22-A | Kubernetes | EKS on-prem cluster | ✅ COMPLETE | Core foundation |
| 22-B | Networking | Istio service mesh + CloudFlare CDN | ✅ COMPLETE | API gateway integration |
| 22-C | Database | PostgreSQL Citus sharding (4 shards) | ✅ COMPLETE | API metadata storage |
| 22-D | ML/AI | GPU + MLFlow + Seldon + Ray + JupyterHub | ✅ COMPLETE | AI suggestion models |
| 22-E | Compliance | OPA/Gatekeeper (15 policies, 13 constraints) | ✅ COMPLETE | Policy enforcement for all APIs |
| 24-25 | Observability | Prometheus + Grafana + Jaeger + OTEL | ✅ COMPLETE | API metrics + tracing |

**Critical Path**:
```
22-B ✅ → 22-C ✅ → 22-D ✅ → 22-E ✅ → [July 22] → 26-A/B/C/D/E
         (all integrated and baseline stable)
```

---

## 26-A: REST & GraphQL API Surface (12 hours)

### REST API Design

**Base URL**: `https://code-server.example.com/api/v1`  
**Authentication**: OAuth2 + API Key (90-day rotation)  
**Rate Limiting**: Dynamic quotas (Phase 25-A integration)

#### Core Endpoints

**Workspace Management**:
```
POST   /workspaces                    # Create workspace
GET    /workspaces                    # List workspaces (paginated)
GET    /workspaces/:id                # Get workspace details
PUT    /workspaces/:id                # Update workspace
DELETE /workspaces/:id                # Delete workspace
POST   /workspaces/:id/invite         # Invite collaborators
```

**File Operations**:
```
GET    /workspaces/:id/files          # List files (recursive)
GET    /workspaces/:id/files/:path    # Get file content
POST   /workspaces/:id/files/:path    # Create file
PUT    /workspaces/:id/files/:path    # Update file content
DELETE /workspaces/:id/files/:path    # Delete file
POST   /workspaces/:id/files/sync     # Sync with local filesystem
```

**User Management**:
```
GET    /users/me                      # Current user profile
PUT    /users/me                      # Update profile
GET    /users/:id                     # Get public user profile
POST   /users/api-keys                # Create API key
GET    /users/api-keys                # List API keys
DELETE /users/api-keys/:id            # Revoke API key
```

**Team/Organization**:
```
POST   /organizations                 # Create org
GET    /organizations                 # List user's orgs
GET    /organizations/:id             # Get org details
PUT    /organizations/:id             # Update org
POST   /organizations/:id/members     # Add member
DELETE /organizations/:id/members/:uid # Remove member
GET    /organizations/:id/members     # List members
```

**AI Suggestions** (Phase 26-D integration):
```
POST   /ai/suggest                    # Generate code suggestions
POST   /ai/generate                   # Full function generation
POST   /ai/refactor                   # Suggest refactoring
GET    /ai/completions               # Get inline completions
```

**ML Models** (Phase 22-D integration):
```
GET    /models                        # List deployed models
GET    /models/:id                    # Get model metadata
POST   /models/:id/infer              # Run inference
GET    /models/:id/metrics            # Get model performance
```

### GraphQL Schema Design

```graphql
type Query {
  # Workspace queries
  workspace(id: ID!): Workspace
  workspaces(first: Int, after: String): WorkspaceConnection!
  
  # File queries  
  file(id: ID!): File
  files(workspaceId: ID!, pattern: String): [File!]!
  
  # User queries
  me: User!
  user(id: ID!): User
  
  # Team queries
  organization(id: ID!): Organization
  organizations: [Organization!]!
  
  # AI queries
  aiSuggestions(context: CodeContext!): [AISuggestion!]!
  
  # Model queries
  models(namespace: String): [MLModel!]!
  model(id: ID!): MLModel
  modelMetrics(id: ID!): ModelMetrics!
}

type Mutation {
  # Workspace mutations
  createWorkspace(input: CreateWorkspaceInput!): Workspace!
  updateWorkspace(id: ID!, input: UpdateWorkspaceInput!): Workspace!
  deleteWorkspace(id: ID!): Boolean!
  
  # File mutations
  createFile(input: CreateFileInput!): File!
  updateFile(id: ID!, input: UpdateFileInput!): File!
  deleteFile(id: ID!): Boolean!
  
  # Team mutations
  createOrganization(input: CreateOrgInput!): Organization!
  inviteMember(orgId: ID!, email: String!): Invitation!
  
  # AI mutations
  acceptSuggestion(id: ID!): Boolean!
  rejectSuggestion(id: ID!): Boolean!
}

type Subscription {
  workspaceUpdated(id: ID!): Workspace!
  fileChanged(id: ID!): File!
  collaboratorJoined(workspaceId: ID!): User!
}

# Core types
type Workspace {
  id: ID!
  name: String!
  description: String
  owner: User!
  members: [User!]!
  files: [File!]!
  createdAt: DateTime!
  updatedAt: DateTime!
  isPublic: Boolean!
  language: String  # python, typescript, go, java
}

type File {
  id: ID!
  path: String!
  content: String!
  language: String!
  lastModifiedBy: User!
  lastModifiedAt: DateTime!
  size: Int!
  history: [FileVersion!]!
}

type User {
  id: ID!
  email: String!
  name: String
  organization: Organization
  apiQuota: APIQuota!
  createdAt: DateTime!
}

type Organization {
  id: ID!
  name: String!
  members: [OrganizationMember!]!
  tier: BillingTier!  # free, pro, enterprise
  apiKeyQuota: Int!
  userLimit: Int!
}

enum BillingTier {
  FREE
  PRO
  ENTERPRISE
}

type AIModel {
  id: ID!
  name: String!
  version: String!
  accuracy: Float!
  latency: Int!  # ms
  costPer1kTokens: Float
}

type MLModel {
  id: ID!
  name: String!
  framework: String!  # tensorflow, pytorch, sklearn
  deployedAt: DateTime!
  replicas: Int!
  endpoint: String!
  metrics: ModelMetrics!
}

type ModelMetrics {
  accuracy: Float
  latency: ModelLatencyPercentiles!
  throughput: Float  # requests/sec
  errorRate: Float
}

type ModelLatencyPercentiles {
  p50: Int
  p95: Int
  p99: Int
}
```

### API Response Standards

**Success Response** (200 OK):
```json
{
  "data": {
    "workspace": {
      "id": "ws_123",
      "name": "my-project",
      "createdAt": "2026-07-22T10:30:00Z"
    }
  },
  "meta": {
    "requestId": "req_456",
    "timestamp": "2026-07-22T10:31:00Z"
  }
}
```

**Error Response** (4xx/5xx):
```json
{
  "error": {
    "code": "WORKSPACE_NOT_FOUND",
    "message": "Workspace with id 'ws_999' does not exist",
    "details": {
      "workspaceId": "ws_999"
    }
  },
  "meta": {
    "requestId": "req_456",
    "timestamp": "2026-07-22T10:31:00Z"
  }
}
```

**Rate Limit Headers**:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1626960600
X-RateLimit-Tier: pro
```

### Documentation & Discovery

- **OpenAPI 3.0 Specification**: Complete spec at `/api/v1/openapi.json`
- **GraphQL Introspection**: Available at `/graphql` (Playground + Introspection enabled)
- **Interactive Docs**: Swagger UI at `/api-docs`, GraphQL Playground at `/graphql`
- **Code Examples**: [GitHub Examples Repository](https://github.com/kushin77/code-server-examples)

### Success Criteria

- ✅ All REST endpoints documented with request/response examples
- ✅ GraphQL schema complete, introspectable, and queryable
- ✅ Query latency <50ms p99 (cached) / <200ms p99 (uncached)
- ✅ Mutation latency <500ms p99
- ✅ API key support on 100% of endpoints
- ✅ Rate limit headers on all responses (within 1ms calculation)
- ✅ Error responses follow RFC 7807 (problem+json)
- ✅ CORS headers properly configured for browser clients
- ✅ 100% test coverage (unit + integration)

---

## 26-B: Multi-Language SDKs (14 hours total)

### Python SDK (5 hours)

**Package**: `code-server-sdk` (PyPI)  
**Python Version**: 3.8+  
**Repository**: https://github.com/kushin77/code-server-py

**Installation**:
```bash
pip install code-server-sdk
```

**Core API**:
```python
from code_server import CodeServerClient, CodeServerAsyncClient

# Sync client
client = CodeServerClient(
    api_key="csk_xxx...",
    base_url="https://code-server.example.com",
    timeout=30
)

# Create workspace
workspace = client.workspaces.create(
    name="my-project",
    description="Python ML project",
    language="python"
)

# List files
files = client.files.list(workspace_id=workspace.id)

# Get file content
content = client.files.get_content(
    workspace_id=workspace.id,
    path="src/main.py"
)

# AI suggestions
suggestions = client.ai.suggest(
    workspace_id=workspace.id,
    file_path="src/main.py",
    line_number=42,
    context_lines=10
)

# Async support
async with CodeServerAsyncClient(api_key="...") as aclient:
    workspace = await aclient.workspaces.create(...)
    files = await aclient.files.list(...)
```

**Error Handling**:
```python
from code_server import (
    CodeServerClient,
    WorkspaceNotFound,
    RateLimitExceeded,
    AuthenticationError
)

try:
    workspace = client.workspaces.get("ws_999")
except WorkspaceNotFound:
    print("Workspace doesn't exist")
except RateLimitExceeded:
    print("Rate limit reached, retry after", client.rate_limit_reset)
except AuthenticationError:
    print("Invalid API key")
```

**Type Hints**:
```python
# Full type support for mypy
workspaces: List[Workspace] = client.workspaces.list(
    limit=10,
    offset=0
)
```

### TypeScript SDK (4 hours)

**Package**: `@code-server/sdk` (npm)  
**Node Version**: 14+  
**Repository**: https://github.com/kushin77/code-server-ts

**Installation**:
```bash
npm install @code-server/sdk
# or
yarn add @code-server/sdk
```

**Core API**:
```typescript
import {
  CodeServerClient,
  Workspace,
  File,
  APIError
} from '@code-server/sdk';

const client = new CodeServerClient({
  apiKey: 'csk_xxx...',
  baseUrl: 'https://code-server.example.com'
});

// Create workspace
const workspace = await client.workspaces.create({
  name: 'web-app',
  language: 'typescript'
});

// List files
const files = await client.files.list(workspace.id);

// Update file
await client.files.update(
  workspace.id,
  'src/index.ts',
  { content: 'export const main = () => {};' }
);

// AI suggestions
const suggestions = await client.ai.suggest({
  workspaceId: workspace.id,
  filePath: 'src/index.ts',
  contextLines: 10
});
```

**React Hooks**:
```typescript
import { useCodeServer, useWorkspace, useFiles } from '@code-server/sdk/react';

export function App() {
  const client = useCodeServer('csk_xxx...');
  const { workspace, loading } = useWorkspace(client, 'ws_123');
  const { files } = useFiles(client, workspace?.id);

  return (
    <div>
      {loading ? 'Loading...' : workspace?.name}
      <FileList files={files} />
    </div>
  );
}
```

### Go SDK (3 hours)

**Package**: `github.com/kushin77/code-server-go`  
**Go Version**: 1.18+  
**Repository**: https://github.com/kushin77/code-server-go

**Installation**:
```bash
go get github.com/kushin77/code-server-go
```

**Core API**:
```go
package main

import (
    "context"
    cs "github.com/kushin77/code-server-go"
)

func main() {
    client := cs.NewClient(
        cs.WithAPIKey("csk_xxx..."),
        cs.WithBaseURL("https://code-server.example.com"),
    )

    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    // Create workspace
    workspace, err := client.Workspaces.Create(ctx, &cs.CreateWorkspaceInput{
        Name:     "go-app",
        Language: "go",
    })
    if err != nil {
        log.Fatal(err)
    }

    // List files
    files, err := client.Files.List(ctx, workspace.ID)
    
    // Get file content
    content, err := client.Files.GetContent(ctx, workspace.ID, "main.go")
}
```

### Java SDK (2 hours)

**GAV**: `com.codeserver:code-server-client:1.0.0` (Maven Central)  
**Java Version**: 11+  
**Repository**: https://github.com/kushin77/code-server-java

**Installation**:
```xml
<dependency>
    <groupId>com.codeserver</groupId>
    <artifactId>code-server-client</artifactId>
    <version>1.0.0</version>
</dependency>
```

**Core API**:
```java
import com.codeserver.CodeServerClient;
import com.codeserver.models.Workspace;

CodeServerClient client = CodeServerClient.builder()
    .apiKey("csk_xxx...")
    .baseUrl("https://code-server.example.com")
    .build();

// Create workspace
Workspace workspace = client.workspaces()
    .create(CreateWorkspaceInput.builder()
        .name("java-app")
        .language("java")
        .build())
    .blockingGet();

// List files
List<File> files = client.files()
    .list(workspace.getId())
    .blockingGet();

// Async with callbacks
client.files().list(workspace.getId(), new Callback<List<File>>() {
    @Override
    public void onSuccess(List<File> files) {
        System.out.println("Got " + files.size() + " files");
    }

    @Override
    public void onError(Exception e) {
        e.printStackTrace();
    }
});
```

### SDK Publishing & Versioning

**Semantic Versioning**: All SDKs follow semver (1.0.0 minimum on launch)  
**Release Schedule**: Monthly patch updates, quarterly feature releases  
**Backward Compatibility**: Guaranteed minor/patch versions  

**SDK Metrics**:
- ✅ 95%+ API endpoint coverage in each SDK
- ✅ <100ms p99 latency (network + serialization)
- ✅ Zero external dependency conflicts
- ✅ Full type safety (TS strict mode, Go interfaces, Java generics)

---

## 26-C: CLI Tool (10 hours)

### Installation & Distribution

**Platforms**: Linux x64, macOS x64/arm64, Windows x86/x64  
**Package Managers**:
- **macOS**: Homebrew (`brew install code-server-cli`)
- **Linux**: APT (`apt-get install code-server-cli`)
- **Windows**: Chocolatey (`choco install codesever-cli`)
- **Universal**: Direct binary download from GitHub releases

**Docker**: `docker run code-server-cli:latest config list`

### Command Structure

```
code-server [GLOBAL_FLAGS] COMMAND [SUBCOMMAND] [FLAGS]
```

### Core Commands

#### Authentication
```bash
# Login with API key
code-server login \
  --host https://code-server.example.com \
  --api-key csk_xxx...

# Login interactively (OAuth flow)
code-server login --interactive

# Logout
code-server logout

# Show current authentication status
code-server auth status
```

#### Workspace Management
```bash
# Create workspace
code-server workspace create \
  --name "project-x" \
  --language python \
  --description "ML training project"

# List workspaces
code-server workspace list [--limit 10] [--json]

# Get workspace details
code-server workspace get <workspace-id>

# Delete workspace
code-server workspace delete <workspace-id> [--force]

# Invite collaborator
code-server workspace invite \
  --workspace <id> \
  --email user@example.com \
  --role collaborator

# Check workspace status
code-server workspace status <workspace-id>
```

#### File Operations
```bash
# Upload single file
code-server file upload \
  --workspace <id> \
  --source ./src/main.py \
  --dest src/main.py

# Download file
code-server file download \
  --workspace <id> \
  --path src/main.py \
  --output ./main.py

# Sync local directory with workspace
code-server file sync \
  --workspace <id> \
  --local-dir ./project \
  --remote-dir / \
  --watch  # continuous sync mode

# List files in workspace
code-server file list <workspace-id> [--pattern "*.py"]

# Delete file
code-server file delete <workspace-id> <path>
```

#### AI Features
```bash
# Generate code suggestions
code-server ai suggest \
  --workspace <id> \
  --file src/main.py \
  --line 42 \
  --count 5  # return 5 suggestions

# Generate complete function
code-server ai generate \
  --prompt "create async auth middleware" \
  --language typescript \
  --model gpt4  # or gpt35, claude

# Refactor code
code-server ai refactor \
  --workspace <id> \
  --file src/util.py \
  --suggestion "extract duplicate logic"

# Explain code
code-server ai explain --file src/complex.py
```

#### Team Management (Phase 22-E integration: RBAC)
```bash
# Create organization
code-server org create --name "acme-corp"

# List organizations
code-server org list

# Add member to organization
code-server org member add \
  --org <org-id> \
  --email developer@acme.com \
  --role developer

# List organization members
code-server org member list <org-id>

# Remove member
code-server org member remove <org-id> <user-id>

# Update member role
code-server org member update <org-id> <user-id> --role admin
```

#### ML Model Operations (Phase 22-D integration)
```bash
# List available models
code-server model list [--workspace <id>]

# Deploy model
code-server model deploy \
  --model <model-id> \
  --workspace <id> \
  --replicas 2 \
  --name "suggestion-v2"

# Run inference
code-server model infer \
  --workspace <id> \
  --deployment <id> \
  --input '{"code": "def hello"}'

# Get model metrics
code-server model metrics <model-id>

# Undeploy model
code-server model undeploy <deployment-id>
```

#### API Key Management
```bash
# Create API key
code-server apikey create \
  --name "CI/CD key" \
  --scopes "read,write" \
  --expires 90d

# List API keys
code-server apikey list

# Revoke API key
code-server apikey revoke <key-id>

# Rotate API key (revoke old, create new)
code-server apikey rotate <key-id>
```

#### Configuration
```bash
# Show current configuration
code-server config view

# Edit configuration
code-server config edit  # opens in $EDITOR

# Set configuration value
code-server config set key.subkey value

# Reset to defaults
code-server config reset --confirm
```

### Global Flags

```bash
--debug             # Enable debug logging
--json              # Output in JSON format
--quiet             # Suppress progress messages
--timeout 30s       # Request timeout
--host <url>        # Override configured host
--api-key <key>     # Override configured API key
--version           # Show version
--help, -h          # Show help
```

### Configuration File

Location: `~/.code-server/config.yaml`

```yaml
# Authentication
host: https://code-server.example.com
api_key: csk_xxx...

# Default workspace
default_workspace: ws_123

# Sync settings
sync:
  auto_sync: false
  watch_interval: 5s

# CLI behavior
output:
  format: json  # or text
  no_color: false
  verbosity: info  # debug, info, warn, error

# Proxy (optional)
proxy:
  http: http://proxy.example.com:8080
  https: https://proxy.example.com:8080
```

### Shell Completion

```bash
# Bash
code-server completion bash | sudo tee /usr/share/bash-completion/completions/code-server
source ~/.bashrc

# Zsh
code-server completion zsh | sudo tee /usr/share/zsh/site-functions/_code-server
exec zsh

# Fish
code-server completion fish | sudo tee /usr/share/fish/vendor_completions.d/code-server.fish
```

### Success Criteria

- ✅ All commands functional and tested
- ✅ Comprehensive help text (`--help` on all commands)  
- ✅ Error messages actionable and clear
- ✅ <2s execution latency per command (network + API)
- ✅ Configuration persisted across sessions
- ✅ Shell tab completion working (bash, zsh, fish)
- ✅ JSON output option available for scripting
- ✅ Works offline with cached configurations

---

## 26-D: AI-Powered Code Generation (10 hours)

### Architecture

**Diagram**:
```
IDE Extension / Web Editor
         ↓
   AI Request Handler
         ↓
  Prompt Formatter → Context Extractor (current file, imports, types)
         ↓
   Ray Cluster (Phase 22-D)
         ↓
   Fine-tuned LLM (GPT-3.5-turbo or local Mistral-7B)
         ↓
   Post-processor (syntax validation, formatting)
         ↓
   Suggestion Engine (ranking, deduplication)
         ↓
   IDE Extension / Web UI
```

**Components**:
1. **Prompt Formatter**: Convert code context → LLM prompt
2. **Context Extractor**: Analyze AST for relevant context  
3. **Ray Worker Pool**: Distributed inference on GPU (Phase 22-D)
4. **Ranking Engine**: Score suggestions by relevance/quality
5. **Analytics**: Track acceptance rate, latency, cost

### Feature 26-D1: Inline Autocomplete (3 hours)

**Trigger**: User types or requests suggestions

**Flow**:
1. Extract 50-line context before cursor + 10-line context after
2. Identify completion point (method call, variable reference, etc.)
3. Send prompt to Ray cluster with GPT-3.5-turbo model  
4. Receive suggestions within 500ms (<100ms for cached context)
5. Return top 3 suggestions with syntax highlighting

**Example**:
```python
# User types: client.files. [Ctrl+Space]
# Suggestions returned:
#   1. list(workspace_id)
#   2. create(workspace_id, path, content)
#   3. delete(workspace_id, path)
```

**Latency Target**: <500ms end-to-end (network + inference + post-processing)

### Feature 26-D2: Full Function Generation (3 hours)

**Trigger**: User writes comment + triggers generation (Alt+G)

**Example**:
```python
# User writes:
def calculate_metrics(predictions, labels):
    # Generate a function that calculates precision, recall, f1
    [User: Alt+G → "calculate precision, recall, f1"]

# AI generates:
def calculate_metrics(predictions, labels):
    """Calculate precision, recall, F1 score"""
    tp = sum(1 for p, l in zip(predictions, labels) if p == l == 1)
    fp = sum(1 for p, l in zip(predictions, labels) if p == 1 and l == 0)
    fn = sum(1 for p, l in zip(predictions, labels) if p == 0 and l == 1)
    
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    
    return {"precision": precision, "recall": recall, "f1": f1}
```

**Language Support**: Python, TypeScript, Go, Java, Rust

**Latency Target**: <1s for generation

### Feature 26-D3: Comment → Code (2 hours)

**Automatically** convert comments into implementation:

```typescript
// User writes comment:
// TODO: Validate user email format

// AI converts to:
function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}
```

### Feature 26-D4: Code Refactoring (2 hours)

**Patterns Supported**:
- Extract duplicate logic into reusable function
- Simplify complex conditionals  
- Optimize time complexity
- Add error handling
- Add unit tests
- Add documentation

**Example**:
```python
# Original:
def process_data(items):
    result = []
    for item in items:
        if item > 0 and item < 100:
            result.append(item * 2)
    return result

# Refactored suggestion:
def process_data(items):
    """Process items within valid range and double them."""
    return [item * 2 for item in items if 0 < item < 100]
```

### Integration with code-server IDE

**Keyboard Shortcuts**:
- `Cmd+Shift+\` (macOS) / `Ctrl+Shift+\` (Linux/Windows): Open AI panel
- `Alt+A`: Add suggestion to document
- `Cmd+Shift+G`: Generate function
- `Shift+F1`: Explain code

**UI Components**:
- AI suggestion panel (right sidebar)
- Inline suggestion hover popup
- AI chat interface (bottom panel)
- Function generation dialog
- Refactoring options context menu

**Analytics Tracked**:
- Suggestion shown
- Suggestion accepted/rejected
- Time to acceptance
- Code quality metrics (post-merge)
- User feedback rating

### Model Selection

**Available Models**:
- **OpenAI GPT-4**: Highest quality, $0.03/1K tokens input
- **OpenAI GPT-3.5-turbo**: Cost-effective, $0.0005/1K tokens  
- **Claude 3 Haiku**: Fast + cheap, $0.00005/1K tokens input
- **Mistral-7B** (self-hosted): Free, runs on Ray cluster

**Default**: GPT-3.5-turbo (balanced quality + cost)  
**Enterprise**: Self-hosted Mistral-7B on Ray workers

### Success Criteria

- ✅ AI suggestions 80%+ peer-reviewed code quality
- ✅ <1s latency for code generation
- ✅ 70%+ suggestion acceptance rate
- ✅ <2% syntax error rate in generated code
- ✅ Type safety validated (mypy, eslint, etc.)
- ✅ <$0.10 cost per suggestion
- ✅ Bias/safety: Human-in-the-loop for critical suggestions

---

## 26-E: Developer Portal (4 hours)

### Pages & Features

**Dashboard** (home page):
- Account summary (name, org, API quota)
- Quick stats (requests/day, error rate, costs)
- Recent workspaces list
- Onboarding guide for new users
- Recent suggestions (if AI enabled)

**API Documentation**:
- Interactive Swagger UI (REST endpoints)
- GraphQL Playground (schema explorer)
- Code examples in all 4 SDK languages
- cURL examples for every endpoint
- Real-time API sandbox

**SDKs & Downloads**:
- Links to GitHub repositories
- Package manager installation instructions  
- Version history with changelog
- Dependencies and compatibility matrix
- Direct download links for binaries

**API Keys Management**:
- Create new API key (with custom name)
- Scopes: `read`, `write`, `admin`
- Expiration: 30d, 90d, 1y, never
- Last used timestamp
- IP allowlist (optional, comma-separated)
- One-click revoke
- Rotation workflow (create new, deprecate old)

**Team Management**:
- Organization members list
- Role management (admin, developer, auditor, viewer)
- Member invitation emails
- Usage per member (requests, storage)
- Audit logs (who did what, when)

**AI Code Generation**:
- Interactive chat interface for prompts
- Suggestion history with accept/reject stats
- Accepted suggestions counter  
- ModelMetrics display (accuracy, latency)
- Session saving/loading
- Code output copy-to-clipboard

**Settings**:
- User profile (name, email, avatar)
- OAuth integrations (GitHub, Google)
- Notification preferences (email, webhook)
- Webhook configuration for events
- Timezone and language preferences
- Two-factor authentication setup
- Session management (revoke tokens)

### Technical Stack

**Frontend**:
- **Framework**: React 18+ with TypeScript
- **Styling**: Tailwind CSS + custom component library
- **State**: React Query (server state) + Zustand (client state)
- **API Client**: Custom wrapper around `@code-server/sdk`
- **Build**: Vite with HMR
- **Testing**: Vitest + React Testing Library
- **Deployment**: Kubernetes service (Phase 22-B integrated)

**Backend** (Portal API):
- **Framework**: Fastify or Express
- **Database**: PostgreSQL (Phase 22-C sharded)
- **Cache**: Redis (via Phase 22-B networking)
- **ORM**: Prisma or SQLAlchemy
- **Auth**: JWT + OAuth2
- **Rate Limiting**: Token bucket (Phase 25-A)

**Deployment**:
- **Port**: 3001 (http://192.168.168.31:3001)
- **Replicas**: 3 for HA
- **Health Check**: `/health` → `{ status: "ok" }`
- **Readiness Check**: `/ready` → database connectivity
- **Kubernetes Namespace**: `portal` (isolated from other services)

### Sample Pages

**Dashboard Example**:
```
┌─ Code-Server Developer Portal ─────────────────────┐
│ Account: user@example.com                  Settings │
├────────────────────────────────────────────────────┤
│                                                    │
│ API Usage This Month                              │
│ Requests: 125,342 / 500,000 (25%)                 │
│ Storage: 2.3 GB / 10 GB (23%)                     │
│ Cost: $12.50 / $50.00 budget                      │
│                                                    │
│ Recent Workspaces                                  │
│ • python-ml-v3        Updated 2h ago              │
│ • web-app-prod        Updated 4h ago              │
│ • data-processing     Updated 1d ago              │
│                                                    │
│ [Create Workspace]  [View All]                    │
│                                                    │
│ Organization                                       │
│ ACME Corp (5 members)    [Manage Team]             │
│ Tier: Pro                [Upgrade]                 │
└────────────────────────────────────────────────────┘
```

**API Keys Page**:
```
┌─ API Keys ────────────────────────────────────────┐
│ [+ Create New Key]                                │
├────────────────────────────────────────────────────┤
│ Key Name     │ Scopes  │ Created    │ Last Used   │
├────────────────────────────────────────────────────┤
│ prod-deploy  │ r,w,a   │ 3 days ago │ 10m ago     │
│ ci-cd        │ r,w     │ 2 weeks ago│ 2h ago      │
│ analytics    │ r       │ 1 month ago│ Never       │
│                                    [Revoke] [Rotate]
└────────────────────────────────────────────────────┘
```

### Success Criteria

- ✅ Dashboard loads in <2s (including data fetching)
- ✅ All pages functional and tested
- ✅ Responsive design (mobile, tablet, desktop)
- ✅ 99.95% uptime SLA
- ✅ <100ms API response time (portal endpoints)
- ✅ Accessibility: WCAG 2.1 AA compliant
- ✅ OAuth integration working with GitHub/Google
- ✅ Real-time notifications for events

---

## INTEGRATION MAP

### Phase 22-B (Networking) ← Phase 26 APIs

**Integration Points**:
- Phase 26 API gateway deployed as Istio virtual service
- Traffic splitting: Canary deployments (10% → 50% → 100%)
- Circuit breakers: Fail open if backend down >5 errors/30s
- Load balancing: Round-robin across 3 API replicas
- mTLS: All inter-service communication encrypted
- Rate limiting: Enforced at ingress gateway level (Phase 25-A)

### Phase 22-C (Database) ← Phase 26 Data Storage

**Schema**:
```sql
-- User shards (hash: user_id)
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  org_id UUID,
  created_at TIMESTAMP,
  CONSTRAINT users_org_fk FOREIGN KEY (org_id) REFERENCES organizations(id)
);

-- Workspace table (distributed by user_id)
CREATE TABLE workspaces (
  id UUID PRIMARY KEY,
  user_id UUID,  -- shard key
  name VARCHAR(255),
  language VARCHAR(50),
  created_at TIMESTAMP,
  CONSTRAINT ws_user_fk FOREIGN KEY (user_id) REFERENCES users(id)
);

-- File table (distributed by user_id via workspace)
CREATE TABLE files (
  id UUID PRIMARY KEY,
  workspace_id UUID,
  user_id UUID,  -- shard key (inherited from workspace)
  path VARCHAR(512),
  content TEXT,
  language VARCHAR(50),
  created_at TIMESTAMP,
  CONSTRAINT files_ws_fk FOREIGN KEY (workspace_id) REFERENCES workspaces(id)
);

-- API keys (distributed by user_id)
CREATE TABLE api_keys (
  id UUID PRIMARY KEY,
  user_id UUID,  -- shard key
  key_hash VARCHAR(256),  -- hashed secure
  scopes JSONB,  -- ["read", "write"]
  created_at TIMESTAMP,
  expires_at TIMESTAMP,
  CONSTRAINT apikeys_user_fk FOREIGN KEY (user_id) REFERENCES users(id)
);
```

**Queries**:
- User workspace list: Single-shard query (user_id filter)
- All user files: Single-shard query (user_id inherited)
- Cross-org reporting: Multi-shard aggregation (slow, cached)

### Phase 22-D (ML/AI) ← Phase 26 AI Features

**Integration**:
- AI suggestion service calls Seldon endpoints (Phase 22-D)
- Model registry API at Seldon inference service (Istio-exposed)
- Ray cluster for distributed model serving
- MLFlow artifact store for model versions
- Cost tracking: Tokens consumed → Phase 25-A cost model

**REST Endpoint**:
```
GET /models
POST /models/:id/infer
  Input: {"context": "...", "prompt": "..."}
  Output: {"suggestions": [...], "tokens_used": 150}
```

### Phase 22-E (Compliance) ← Phase 26 Governance

**Policies Enforced**:
- API endpoints must be in `code-server-api` namespace
- All API requests logged (audit policy)
- AI suggestions must validate HIPAA compliance (if enabled)
- API key operations require 2FA (security policy)
- Resources labeled with team/cost-center (labeling policy)

**Constraint Example**:
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: api-required-labels
spec:
  match:
    namespaces:
      - code-server-api
  parameters:
    labels: ["team", "cost-center", "api-version"]
```

### Phase 24 (Observability) ← Phase 26 Metrics

**Metrics Exported** (Prometheus):
- `api_request_duration_seconds` (histogram)
- `api_requests_total` (counter, by endpoint, method, status)
- `api_errors_total` (counter, by error type)
- `ai_suggestions_generated` (counter)
- `ai_suggestions_accepted` (counter)
- `ai_suggestion_latency_seconds` (histogram)
- `sdk_calls_total` (counter, by language, operation)

**Grafana Dashboards**:
- API Performance: Request rates, latency, error rates
- AI Metrics: Suggestion accuracy, acceptance rate, cost
- SDK Usage: Calls by language, adoption trends
- Business Metrics: API keys created, organizations, revenue

**Jaeger Tracing**:
- Trace API calls from client SDK through API gateway, database, backend
- Identify bottlenecks (network, database, model inference)
- Debug distributed failures

---

## DEPLOYMENT ROADMAP

### Week 1: REST/GraphQL APIs (July 22-26)

**Mon-Tue**: API & Schema Design
- Review OpenAPI spec  
- Finalize GraphQL schema
- Design data models

**Wed-Thu**: Implementation
- REST endpoint implementation (Fastify)
- GraphQL resolver implementation
- Unit tests (50+ test cases)

**Fri**: Integration Testing
- Full stack testing (API → DB → response)
- Load testing (100 req/s)
- Documentation complete

**Deliverable**: Deployable API service ready for staging

### Week 2: SDKs & CLI (July 29-Aug 2)

**Mon-Wed**: SDK Implementation
- Python SDK (PyPI ready)
- TypeScript SDK (npm ready)
- Go SDK (pkg.go.dev ready)
- Java SDK (Maven Central ready)

**Thu-Fri**: CLI Tool
- Core commands implemented
- Testing (all platforms)
- Documentation complete

**Deliverable**: All SDKs/CLI published and functional

### Week 3: AI & Portal (Aug 5-12)

**Mon-Tue**: AI Code Generation
- Prompt formatting + context extraction
- Model inference integration (Ray)
- Inline autocomplete + function generation
- Validation (syntax, type checking)

**Wed-Thu**: Developer Portal
- React UI components
- API integration
- User testing
- Performance optimization

**Fri-Sat**: Testing & Launch
- E2E testing (all features)
- Load testing (1000+ users)
- Security audit
- Production deployment

**Deliverable**: Production-ready Phase 26 complete

---

## SUCCESS METRICS

### API Metrics
- ✅ REST query latency: <100ms p99
- ✅ GraphQL query latency: <50ms p99 (cached)
- ✅ Mutation latency: <500ms p99
- ✅ API availability: 99.95% SLA
- ✅ Error rate: <0.1%

### SDK Metrics  
- ✅ All 4 SDKs published to package managers
- ✅ SDK adoption: 1000+ downloads/month
- ✅ API coverage: 95%+
- ✅ SDK latency: <100ms p99

### CLI Metrics
- ✅ <2s execution latency per command
- ✅ 100+ test cases passing
- ✅ Cross-platform tested (Linux, macOS, Windows)
- ✅ Shell completion working

### AI Metrics
- ✅ Suggestion accuracy: 80%+
- ✅ Latency: <1s for generation
- ✅ Acceptance rate: 70%+
- ✅ Cost: <$0.10/suggestion

### Portal Metrics
- ✅ Dashboard load time: <2s
- ✅ Page response time: <500ms
- ✅ Uptime: 99.95%
- ✅ User engagement: >70% DAU

---

## DEPENDENCIES CHECKLIST

**Must be complete BEFORE Phase 26 starts (July 22)**:

- ✅ Phase 22-A: Kubernetes cluster (ALL phases leverage this)
- ✅ Phase 22-B: Istio service mesh (API gateway, routing)
- ✅ Phase 22-C: PostgreSQL sharding (API data storage)
- ✅ Phase 22-D: ML/AI infrastructure (AI suggestion models)
- ✅ Phase 22-E: Compliance automation (Policy enforcement)
- ✅ Phase 24-25: Observability (Metrics, tracing, cost tracking)

**All prerequisites verified COMPLETE and baseline-stable (July 22, 2026)**

---

## DELIVERABLES FINAL CHECKLIST

**Code & Infrastructure**:
- [ ] REST API service + Kubernetes manifest
- [ ] GraphQL API service + Kubernetes manifest
- [ ] Python SDK (PyPI package + source)
- [ ] TypeScript SDK (npm package + source)
- [ ] Go SDK (GitHub package + source)
- [ ] Java SDK (Maven Central + source)
- [ ] CLI tool (distributable binaries)
- [ ] AI service (Ray cluster integration)
- [ ] Developer portal (React SPA + backend API)
- [ ] Terraform IaC (terraform/phase-26.tf)

**Documentation**:
- [ ] OpenAPI 3.0 specification (for SDK generation)
- [ ] GraphQL schema documentation
- [ ] REST API examples (cURL, Python, TS, Go, Java)
- [ ] SDK getting-started guides (per language)
- [ ] CLI manual pages
- [ ] AI features tutorial  
- [ ] Deployment runbook (PHASE-26-DEPLOYMENT-RUNBOOK.md)
- [ ] Troubleshooting guide

**Testing & Validation**:
- [ ] API integration tests (100+ scenarios)
- [ ] SDK compatibility tests (all languages)
- [ ] CLI cross-platform tests
- [ ] Load testing (1000 concurrent users)
- [ ] Security audit (OWASP top 10)
- [ ] AI accuracy benchmarks
- [ ] Portal E2E tests

---

## FINAL NOTES

**Phase 26 is the FINAL phase** completing code-server infrastructure.

**After Phase 26 is complete**:
- All developer-facing APIs available
- Multi-language SDKs in all major package managers
- Powerful CLI for on-prem management
- AI-assisted coding for all languages  
- Complete observability + governance

**No additional phases required**. Phase 26 achievement = **PRODUCTION-READY CODE-SERVER ENTERPRISE PLATFORM**.

---

**Document Status**: Complete specification for Phase 26 implementation  
**Last Updated**: April 14, 2026  
**Owner**: Infrastructure + Developer Tools Team  
**Next Review**: Upon Phase 22-E baseline completion (July 22, 2026)
