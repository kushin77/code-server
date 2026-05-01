# env.yaml CI Integration & Environment Parity Documentation

**Last Updated:** 2026-04-25T00:00:00Z  
**Status:** Production Ready  
**P0-1553 Phase 5 Deliverable**

## CI Integration

All CI jobs read `env.yaml` to provision their own environment, ensuring parity between local dev and CI.

### Workflow: env-yaml-ci-integration.yml

1. **Schema Validation** - Validates env.yaml against JSON schema
2. **Multi-Mode Provisioning** - Tests both `local` and `ci` runtime modes
3. **Environment Diff** - Tests diff between two env.yaml versions
4. **Fingerprinting** - Generates SHA256 hash for environment cache invalidation

### Build Matrix

CI runs tests across multiple environment variants:

```yaml
matrix:
  mode: [local, ci]
  postgres_version: [15, 16]
  redis_version: [7, 7.2]
```

Each combination gets its own CI job.

### Environment Cache Key

```bash
env-fingerprint-${{ hashFiles('env.yaml', 'docker-compose.yml') }}
```

Docker layer cache invalidates only when env.yaml changes.

## Environment Parity Checklist

- [x] Schema: env.yaml.v1.json defines all fields
- [x] Parser: provisioner.py reads and validates
- [x] Local: Docker Compose on developer machine
- [x] Remote: SSH provisioning to remote host
- [x] CI: GitHub Actions environment from same env.yaml
- [x] IDE: VS Code JSON schema real-time validation
- [x] Offline: Pre-pull mode for connectivity loss
- [x] Replay: Recreate failed CI environment locally
- [x] Diff: Show deltas between two env.yaml files
- [x] Promote: Move environment to production with approval

## Usage in CI

### Running tests in CI-specific environment:

```bash
# .github/workflows/test.yml
- name: Provision CI Environment
  run: |
    python3 apps/env-provisioner/provisioner.py provision env.yaml
  env:
    ENV_MODE: ci

- name: Run Tests
  run: |
    npm test
```

### Cache invalidation:

```bash
- name: Cache Docker layers
  uses: actions/cache@v3
  with:
    key: env-${{ hashFiles('env.yaml') }}
    path: ~/.docker
```

## Multi-Environment Test Matrix

```yaml
strategy:
  matrix:
    include:
      - env: env.yaml
        description: "Production-like"
      - env: env.yaml.staging
        description: "Staging variant"
      - env: env.yaml.minimal
        description: "Minimal dependencies"
```

## Result: Environment Parity Achieved

✅ **Local = Remote = CI = AI**

A single `env.yaml` file fully specifies the development environment across all platforms:
- Developers spin up identical local environments
- Remote environments provision identically
- CI jobs run with exact same service versions and configuration
- Offline mode works with no connectivity
- Failed CI builds reproducible locally
