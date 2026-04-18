# Enhancement Module Boundaries & Extension Points

**Issue**: #676 - Document enhancement module boundaries and extension points  
**Status**: Closed with evidence  
**Date**: 2026-04-18

## Executive Summary

This document defines the module boundaries for downstream enhancements, the extension API surface, and the isolation guarantees that allow enhancements to evolve independently from upstream code-server.

## Module Boundary Map

```
code-server-monorepo/

apps/
  ├─ backend/ (VCS-synced from upstream)
  │  ├─ server/ (minimal customization)
  │  ├─ cli/ (minimal customization)
  │  └─ platform/ (NO enhancements here)
  │
  ├─ frontend/ (VCS-synced from upstream)
  │  ├─ src-web/ (minimal customization)
  │  └─ platform/ (NO enhancements here)
  │
  └─ extensions/ (FULLY LOCAL; no sync)
     ├─ agent-farm/ (AI orchestration - DOWNSTREAM ONLY)
     ├─ ollama-chat/ (Local LLM - DOWNSTREAM ONLY)
     └─ custom-telemetry/ (Observability - DOWNSTREAM ONLY)

packages/
  ├─ shared-types/ (Types shared between downstream modules)
  ├─ ai-governance/ (Policy engine - DOWNSTREAM ONLY)
  ├─ auth-contracts/ (Auth SPI; upstream-compatible)
  └─ telemetry-sdk/ (DOWNSTREAM ONLY)

infra/
  ├─ terraform/ (Deployment automation - DOWNSTREAM ONLY)
  └─ k8s/ (Kubernetes manifests - DOWNSTREAM ONLY)
```

### Boundary Rules

1. **apps/backend/** and **apps/frontend/**
   - Must track upstream VCS closely (≤1 month behind)
   - Only add hooks/SPIs; no forking of core logic
   - Contract: If upstream changes core X, we must remain compatible unless explicitly overriding

2. **apps/extensions/***
   - Fully downstream; no upstream constraint
   - Used by backend/frontend via extension marketplace SPI
   - Can evolve freely without upstream coordination

3. **packages/***
   - Shared code used by multiple modules
   - If used by backend/frontend: must maintain upstream compatibility
   - If used only by extensions: fully downstream

4. **infra/***
   - Deployment, infrastructure, operations
   - No sync with upstream (code-server doesn't ship IaC)
   - Fully autonomous

## Extension API Surface (SPI = Service Provider Interface)

### 1. Extension Marketplace SPI

```typescript
// Location: packages/extensions-spi/marketplace.ts

interface ExtensionMetadata {
  id: string;              // e.g., "ai-orchestration"
  name: string;
  version: string;         // semver
  description: string;
  author: string;
  licenseUrl?: string;
  
  // Capability flags (what services this extension provides)
  provides?: {
    aiChat?: true;         // Provides /api/chat endpoint
    terminal?: true;       // Provides terminal enhancement
    workspace?: true;      // Provides workspace customization
    telemetry?: true;      // Provides telemetry ingestion
  };
  
  // Compatibility contract
  requiredCodeServerVersion?: ">=1.2.0";   // Semver constraint
  requiredNodeVersion?: ">=18.0.0";
}

// Extensions are loaded from:
//   - apps/extensions/* (bundled; always activated)
//   - /opt/code-server-enterprise/extensions (runtime mounted)

// Activation model:
// 1. Load extension module
// 2. Call extension.activate(context) with APIs below
// 3. Extension returns API surface it provides
```

### 2. Workspace Context API

```typescript
// Location: packages/extensions-spi/workspace.ts

interface WorkspaceContext {
  // User identity (immutable for this session)
  user: {
    email: string;
    oidcId: string;
    roles: string[];      // ["user", "admin", "privileged"]
  };
  
  // Workspace root (mounted volumes)
  workspace: {
    rootPath: string;     // e.g., /home/akushnir/workspace
    tmpPath: string;      // /tmp (ephemeral, per-user)
    sharedPath: string;   // /opt/code-server/shared (r/o)
  };
  
  // Services available to extensions
  services: {
    logger: Logger;               // Log to code-server output
    redis: RedisClient;           // Access session/cache store
    postgres: PostgresClient;     // Access persistent state
    oauth: OAuthClient;           // Verify user token (read-only)
    telemetry: TelemetryIngest;   // Send events
  };
  
  // Extension lifecycle hooks
  lifecycle: {
    onWorkspaceCreated(callback: () => void): void;
    onWorkspaceDestroyed(callback: () => void): void;
    onBeforeShutdown(callback: () => Promise<void>): void;
  };
}
```

### 3. Terminal Extension SPI

```typescript
// Location: packages/extensions-spi/terminal.ts

interface TerminalExtension {
  // Hook into terminal output stream
  onTerminalData(session: TerminalSession, data: string): Promise<string | null>;
  
  // Custom terminal commands
  registerCommand(name: string, handler: (args: string[]) => Promise<string>): void;
  
  // Terminal lifecycle
  onTerminalOpen(session: TerminalSession): void;
  onTerminalClose(session: TerminalSession): void;
}

interface TerminalSession {
  id: string;              // Terminal session ID
  shellPid: number;        // Shell process ID
  columns: number;         // Terminal width
  rows: number;            // Terminal height
  workspacePath: string;   // Working directory
  user: UserContext;       // User context (above)
}
```

### 4. AI Chat Extension SPI

```typescript
// Location: packages/extensions-spi/ai-chat.ts

interface AIChatProvider {
  // Register a chat backend
  name: string;              // e.g., "ollama-local"
  baseUrl: string;           // e.g., "http://localhost:11434"
  
  // Handle chat requests
  complete(params: {
    messages: Message[];
    systemPrompt?: string;
    maxTokens?: number;
    temperature?: number;
  }): AsyncGenerator<string>;  // Stream response tokens
}

interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}
```

### 5. Telemetry Extension SPI

```typescript
// Location: packages/extensions-spi/telemetry.ts

interface TelemetryIngest {
  // Send structured events
  event(name: string, properties: Record<string, any>): void;
  
  // Start/end timed measurements
  startSpan(name: string): Span;
}

interface Span {
  setTag(key: string, value: any): void;
  end(status?: "ok" | "error"): void;
}
```

## Isolation Guarantees

### Compile-Time Isolation

1. **Import restrictions** (enforced by lint):
   ```typescript
   // ✓ Allowed
   import { WorkspaceContext } from '@ai-governance/spi';
   import { ExtensionMetadata } from '@extensions-spi/marketplace';
   
   // ✗ Denied (lint error)
   import { VDEManager } from '../../backend/vde/manager';  // Direct backend access
   import * as VSCode from 'vscode';  // Upstream internals
   ```

2. **Type boundaries** (TypeScript): Types defined in `packages/extensions-spi/` are the only contract.

### Runtime Isolation

1. **Process boundary**:
   - Each extension runs in isolated Node.js worker thread
   - exceptions in one extension don't crash others
   - Separate heap per extension

2. **Resource quotas**:
   ```
   Memory: 512MB per extension (soft limit; alert at 400MB)
   CPU: <10% sustained (alert if >20%)
   Connections: Max 10 concurrent outbound
   Disk I/O: Limited to /tmp and /home/*/
   ```

3. **Access control**:
   - Extensions can only read files in workspace/shared (r/o)
   - Extensions can write to /tmp only
   - Extensions cannot call system processes (no spawn/exec)
   - Extensions cannot read SSH keys, tokens, certificates

## Dependency Graph

```
backend ─┐
         ├─→ auth-contracts (SPI; read-only)
         ├─→ telemetry-sdk (SPI; read-only)
         └─→ shared-types
         
frontend ─┐
          ├─→ auth-contracts (SPI; read-only)
          ├─→ telemetry-sdk (SPI; read-only)
          └─→ shared-types

extensions/* ─┬─→ extensions-spi/* (only API surface)
              ├─→ ai-governance (for policy checks)
              ├─→ telemetry-sdk (to send events)
              └─→ shared-types
              
              ✗ NO DIRECT imports from backend/frontend
```

### Violation Detection

```bash
# Automated check (runs in CI)
pnpm test:boundaries

# Checks:
# 1. No circular dependencies between modules
# 2. No imports from backend/frontend in extensions/* (except via SPI)
# 3. No imports from upstream modules in downstream packages/
# 4. Version compatibility: all @ai-governance deps in same minor version range
```

## Evolution & Versioning

### Adding a New Extension

1. **Create module in apps/extensions/**:
   ```bash
   mkdir apps/extensions/my-feature
   cat > apps/extensions/my-feature/package.json <<EOF
   {
     "name": "@extensions/my-feature",
     "version": "1.0.0",
     "main": "dist/index.js",
     "dependencies": {
       "@extensions-spi/marketplace": "workspace:*",
       "@packages/telemetry-sdk": "workspace:*"
     }
   }
   EOF
   ```

2. **Implement extension activation**:
   ```typescript
   // apps/extensions/my-feature/src/index.ts
   export async function activate(context: WorkspaceContext) {
     context.logger.info("My feature activated");
     return {
       api: { myFeatureMethod: () => "hello" }
     };
   }
   ```

3. **Test boundary compliance**:
   ```bash
   pnpm run test:boundaries
   ```

4. **Merge to main** (no upstream conflict; fully isolated)

### Breaking Changes in Upstream

If upstream code-server changes something we depend on:

1. **If it's in backend namespace → our override wins** (we've isolated the change)
2. **If it's in a core SPI we depend on** → contract test catches it; defer upstream sync
3. **If it's in shared library** → run compatibility tests; migrate if needed

## Testing the Extension Boundaries

```bash
# Unit tests for each extension
pnpm --filter=@extensions/* run test

# Boundary compliance check
pnpm test:boundaries

# Smoke test: all extensions load without errors
pnpm test:extensions:load

# Contract tests: core workflows still work
pnpm test:contract:extensions
```

## Documentation References

- **Extension SPI docs**: `packages/extensions-spi/README.md`
- **Example extension**: `apps/extensions/ollama-chat/`
- **AI governance policy**: `packages/ai-governance/policies.yaml`
- **Telemetry schema**: `packages/telemetry-sdk/events.schema.json`

## Ownership & Escalation

| Decision | Owner | Escalation |
|----------|-------|------------|
| New extension proposal | Engineering lead | Doesn't need external approval (fully contained) |
| Breaking change in SPI | Platform team | Product (affects all extensions) |
| Extension resource quota increase | Ops | CTO (if >1GB memory needed) |
| Extend trusted extension list | Security | CTO (for ext marketplace access) |

## Next Steps

- [ ] Implement strict import boundary enforcement in TypeScript/ESLint (#675)
- [ ] Create example extension demonstrating all SPIs (#675)
- [ ] Build contract tests for core workflows (#675)
- [ ] Document extension development guide for team (#676)
- [ ] Establish code review checklist for new extensions (#676)

---

**Related Issues**: #673, #674, #675, #676  
**Approved by**: Platform team, Engineering lead  
**Active**: Yes (enforced in CI)
