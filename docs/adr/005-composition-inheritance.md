# ADR-005: Composition Inheritance for Configuration Management

**Status**: Accepted
**Date**: April 14, 2026
**Supersedes**: N/A
**Related To**: ADR-004 (Consolidation Patterns)

## Context

After consolidating configuration into base files (docker-compose.base.yml, Caddyfile.base, alertmanager-base.yml), we needed a strategy for:
- **Variant management**: Production, development, on-premises, testing variants
- **Override precedence**: When base + variant conflict, which wins?
- **Composition semantics**: How should multiple files compose together?
- **Rollback safety**: Can we safely rollback variants without base?

Without clear composition rules, developers could:
- Accidentally override critical base settings
- Create conflicts between variants
- Duplicate base config again
- Introduce incompatibilities at deployment time

## Decision

We adopt **composition inheritance** as the primary pattern for managing configuration variants:

### Composition Rules

#### 1. Docker Compose File Composition (docker-compose)

**Precedence**: Later files override earlier files.

```bash
# Command line composition (left to right precedence)
docker compose \
  -f docker-compose.base.yml \      # Base definitions (lowest priority)
  -f docker-compose.yml \            # Production overrides (medium)
  -f docker-compose.secrets.yml \    # Secret references (highest priority)
  up -d
```

**Merge semantics**:
```yaml
# docker-compose.base.yml
services:
  code-server:
    image: codercom/code-server:4.115.0
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      - PASSWORD=base-default

# docker-compose.yml (production)
services:
  code-server:
    environment:
      - PASSWORD=${PASSWORD_PROD}  # Overrides base PASSWORD
      - DEBUG=false                 # New var added

# Result: Merged service
#   image: codercom/code-server:4.115.0 (from base)
#   ports: 127.0.0.1:8080:8080 (from base)
#   environment:
#     PASSWORD: ${PASSWORD_PROD} (from prod, not base)
#     DEBUG: false (from prod)
```

**Composition order** (establish standard order for consistency):
1. `docker-compose.base.yml` — Core definitions (read-only)
2. `docker-compose.yml` — Production environment
3. `docker-compose.dev.yml` — Development overrides (optional)
4. `docker-compose.local.yml` — Local machine overrides (optional, .gitignore)

#### 2. Caddyfile Composition (@import Pattern)

**Precedence**: Import order matters; later imports can reference earlier blocks.

```caddyfile
# Caddyfile (production)
@import Caddyfile.base

# Use named segments from base
:80 {
    header @import (security_headers)
    header @import (cache_control_rules)
}

:443 {
    header @import (security_headers_strict)
    reverse_proxy code-server:8080
}
```

**Named segment override** (declare new version if needed):
```caddyfile
# Caddyfile.new (new deployment variant)
@import Caddyfile.base

# Override (redefine segment with different settings)
(security_headers) {
    header X-Content-Type-Options nosniff
    header X-Frame-Options DENY  # More strict than base
}

:80 {
    header @import (security_headers)  # Uses overridden version
}
```

**Composition order**:
1. `Caddyfile.base` — Define all named segments
2. `Caddyfile` (import base) — Production-specific matchers
3. `Caddyfile.new` (import base + overrides) — New deployment variant
4. Optional: `Caddyfile.dev` (import base) — Development overrides

#### 3. AlertManager Configuration (include Pattern)

**Precedence**: Later receivers/routes override based on match criteria.

```yaml
# alertmanager-base.yml
global:
  resolve_timeout: 5m

route:
  receiver: default
  routes:
    - match:
        severity: critical
      receiver: critical-team

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: "<=high"

# alertmanager-production.yml
include: alertmanager-base.yml

receivers:
  - name: default
    slack_configs:
      - api_url: ${SLACK_DEFAULT_URL}

  - name: critical-team
    pagerduty_configs:
      - service_key: ${PAGERDUTY_KEY}

  - name: database-team
    email_configs:
      - to: database@company.com
```

**Composition order**:
1. `alertmanager-base.yml` — Routes, inhibit rules, global settings
2. `alertmanager.yml` (include base) — Simple variant with basic receivers
3. `alertmanager-production.yml` (include base) — Production receivers (PagerDuty, email)

#### 4. Terraform Locals Composition (inherit via reference)

**Precedence**: Locals define once, all resources reference.

```hcl
# terraform/locals.tf (single source of truth)
locals {
  docker_images = {
    code-server = "codercom/code-server:4.115.0"
  }
  resource_limits = {
    code-server = { memory = "4g" }
  }
}

# terraform/main.tf (production resource)
resource "docker_container" "code_server" {
  image = local.docker_images["code-server"]
  memory = 4096 * 1024 * 1024  # Parse from local.resource_limits["code-server"].memory
}

# terraform/dev.tf (development resource - uses same locals)
resource "docker_container" "code_server_dev" {
  image = local.docker_images["code-server"]  # Same image
  memory = 2048 * 1024 * 1024  # Override for dev (smaller)
}
```

**Composition order**:
1. `terraform/locals.tf` — All image versions and defaults
2. `terraform/*.tf` — All resources reference locals (never hardcoded)
3. `terraform.tfvars` (optional) — Environment-specific variable overrides

### Composition Safety Rules

**Rule 1: Immutable Base**
- Base files (docker-compose.base.yml, Caddyfile.base, etc.) should not be modified for variants.
- All variant differences are in override files.
- Benefits: Easy to understand what changed, safe to update base.

**Rule 2: Explicit Overrides**
- Only override settings that differ from base.
- Don't duplicate base settings in variant files.
- Benefits: Variant files are small, clear what's different.

**Rule 3: Order Matters**
- Document composition order in each variant (comment at top of file).
- Command-line / CI scripts use consistent order.
- Benefits: No surprises from unexpected override precedence.

**Rule 4: Validation Before Deployment**
- Compose/validate before deploying:
  - Docker: `docker-compose config` (shows merged result)
  - Caddyfile: `caddyfile fmt` and `caddyfile validate`
  - AlertManager: `amtool config routes` (validate routes)
  - Terraform: `terraform plan` (validate resource resolution)
- Benefits: Catch conflicts early, debug easily.

**Rule 5: Single Responsibility**
- Each variant file has one clear purpose:
  - `docker-compose.yml` — Production environment
  - `docker-compose.dev.yml` — Development tweaks
  - `docker-compose.local.yml` — Local machine (secrets, ports)
- Don't mix concerns in one variant.
- Benefits: Easy to enable/disable variants, clear intent.

## Composition Examples

### Example 1: Docker Compose Production Deployment

```bash
#!/bin/bash
# production-deploy.sh

COMPOSE_FILES=(
  "docker-compose.base.yml"      # Core definitions
  "docker-compose.yml"            # Production overrides
  "docker-compose.secrets.yml"    # Secrets from environment
)

# Validate composition
docker compose "${COMPOSE_FILES[@]/#/-f }" config > /tmp/merged.yml
echo "Merged config validated"

# Deploy with same file order
docker compose "${COMPOSE_FILES[@]/#/-f }" up -d
```

**Merged result** (conceptual):
```yaml
services:
  code-server:
    image: codercom/code-server:4.115.0             # From base
    ports:
      - "0.0.0.0:8080:8080"                        # From prod
    environment:
      PASSWORD: ${PASSWORD_PROD}                    # From secrets
      SUDO_PASSWORD: ${SUDO_PASSWORD_PROD}          # From secrets
      DEBUG: "false"                                 # From prod
```

### Example 2: Caddyfile Security Headers Composition

```caddyfile
# Caddyfile.base
(security_headers) {
    header X-Content-Type-Options nosniff
    header X-Frame-Options SAMEORIGIN
    header Strict-Transport-Security "max-age=31536000"
}

(security_headers_strict) {
    header X-Content-Type-Options nosniff
    header X-Frame-Options DENY              # More strict
    header Strict-Transport-Security "max-age=31536000; preload"
    header Content-Security-Policy "default-src 'self'"
}

# Caddyfile (standard production)
@import Caddyfile.base

:443 {
    header @import (security_headers)
    reverse_proxy code-server:8080
}

# Caddyfile.production (high security)
@import Caddyfile.base

:443 {
    header @import (security_headers_strict)  # Uses strict variant
    reverse_proxy code-server:8080
}
```

### Example 3: Terraform Development vs Production

```hcl
# terraform/locals.tf (shared)
locals {
  docker_images = {
    code-server = "codercom/code-server:4.115.0"
  }
  resource_limits_prod = {
    code-server = {
      cpu = "2.0"
      memory = "4g"
    }
  }
  resource_limits_dev = {
    code-server = {
      cpu = "1.0"
      memory = "2g"
    }
  }
}

# terraform/main.tf (production)
module "code_server_prod" {
  image = local.docker_images["code-server"]
  resources = local.resource_limits_prod["code-server"]
}

# terraform/dev.tf (development, in same workspace)
module "code_server_dev" {
  image = local.docker_images["code-server"]
  resources = local.resource_limits_dev["code-server"]
}

# Both use same image version, different resources
# To switch: terraform apply -target=module.code_server_prod (prod only)
```

## Consequences

### Positive
✅ **Clear invariants**: Base is immutable, variants are deltas
✅ **Safe updates**: Change base, all variants inherit automatically
✅ **Debuggable**: `docker-compose config`, `caddyfile fmt` show merged result
✅ **Familiar patterns**: Compose/override is standard Docker, Terraform pattern
✅ **Version control friendly**: Variants are small diffs, base is reference

### Considerations
⚠️ **Learning curve**: Developers must understand composition semantics
⚠️ **Debugging complexity**: May need to expand includes to understand conflicts
⚠️ **File ordering**: Must maintain consistent order across all scripts

### Mitigations
- **Documentation**: This ADR + CONTRIBUTING.md with examples
- **Validation scripts**: Always use `validate` before deploying
- **CI enforcement**: Validate all compositions in every PR
- **New contributor guide**: Clear onboarding on composition patterns

## Implementation Checklist

- [x] Create docker-compose.base.yml with anchors
- [x] Update docker-compose.yml to compose with base
- [x] Create Caddyfile.base with named segments
- [x] Update Caddyfile variants to import base
- [x] Create alertmanager-base.yml with shared route structure
- [x] Update alertmanager variants to include base
- [x] Centralize versions in terraform/locals.tf
- [x] Update all .tf resources to reference locals
- [ ] Add composition validation to CI pipeline
- [ ] Update deployment scripts with proper file ordering
- [ ] Document all variants with composition comment

## Related ADRs

- **ADR-004**: Configuration Consolidation Patterns (why we consolidate)
- **ADR-001**: Containerized Deployment (uses docker-compose)
- **ADR-003**: Terraform Infrastructure (uses locals)

## References

- [Docker Compose Multi-File Composition](https://docs.docker.com/compose/multiple-compose-files/)
- [Caddyfile Directives](https://caddyserver.com/docs/caddyfile/directives)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/)
- [Terraform Locals](https://www.terraform.io/language/values/locals)

---

**Status**: Accepted (April 14, 2026)
**Last Updated**: April 14, 2026
