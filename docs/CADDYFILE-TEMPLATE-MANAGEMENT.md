# Caddyfile Template Management (P2 #373)

## Overview

The Caddyfile is a **generated artifact** — never commit rendered variants directly to the repository. Instead, maintain a **single source of truth** template (`Caddyfile.tpl`) and render variants on-demand for different deployment environments.

## Architecture

### Single Source of Truth
- **`Caddyfile.tpl`** — Template file with environment variable placeholders (committed to repo)
- **Rendered variants** (NOT committed):
  - `Caddyfile` — Production (HTTPS via Let's Encrypt / internal TLS)
  - `Caddyfile.onprem` — On-premises (HTTP only, no TLS)
  - `Caddyfile.simple` — Development/testing (HTTP + debug logging)

### Build-Time Rendering
Rendered files are **generated at build/deployment time** using `envsubst`, ensuring:
- ✅ Environment variables are interpolated at deployment time
- ✅ No hardcoded values in repository
- ✅ Single source of truth prevents configuration drift
- ✅ Easy to add new variants for new environments

## Usage

### Render All Variants (Development)

```bash
make render-caddy-all
```

**Output:**
```
Rendering Caddyfile (production) from Caddyfile.tpl...
✅ Caddyfile rendered (production)
Rendering Caddyfile.onprem from Caddyfile.tpl...
✅ Caddyfile.onprem rendered (on-premises HTTP)
Rendering Caddyfile.simple from Caddyfile.tpl...
✅ Caddyfile.simple rendered (simple dev mode)
✅ All Caddyfile variants rendered from template
```

### Render Individual Variants

```bash
# Production
make render-caddy-prod

# On-premises
make render-caddy-onprem

# Development/simple
make render-caddy-simple
```

### Validate Caddyfile Syntax

```bash
make caddy-validate
```

**Output:**
```
Validating rendered Caddyfile syntax...
✅ Caddyfile is valid
```

### Docker Deployment

The deployment process handles rendering automatically:

1. **Template parameters** are passed via environment variables (`.env`)
2. **Caddyfile is rendered** during container build (Dockerfile.caddy)
3. **Rendered file is injected** into the container at runtime

```dockerfile
# Example from Dockerfile.caddy
RUN envsubst < /etc/caddy/Caddyfile.tpl > /etc/caddy/Caddyfile
```

## Template Variables

### Common Variables (All Variants)

| Variable | Example | Required | Purpose |
|----------|---------|----------|---------|
| `CADDY_DOMAIN` | `ide.kushnir.cloud` | Yes | Reverse proxy domain |
| `CADDY_TLS_BLOCK` | `tls internal` | No | TLS configuration (empty for HTTP) |
| `CADDY_LOG_LEVEL` | `info` | Yes | Caddy logging level (debug, info, warn, error) |
| `CODE_SERVER_UPSTREAM` | `oauth2-proxy:4180` | Yes | Upstream service for code-server |
| `GRAFANA_PORT` | `3000` | Yes | Grafana reverse proxy port |
| `PROMETHEUS_PORT` | `9090` | Yes | Prometheus reverse proxy port |
| `ALERTMANAGER_PORT` | `9093` | Yes | AlertManager reverse proxy port |
| `JAEGER_PORT` | `16686` | Yes | Jaeger UI reverse proxy port |

### Pre-Configured Defaults (via Makefile)

**Production (`make render-caddy-prod`)**:
- Domain: `${CADDY_DOMAIN:-ide.kushnir.cloud}`
- TLS: `tls internal`
- Log Level: `info`
- Upstream: `oauth2-proxy:4180`

**On-Premises (`make render-caddy-onprem`)**:
- Domain: `:80` (HTTP only)
- TLS: (none)
- Log Level: `info`
- Upstream: `oauth2-proxy:4180`

**Development/Simple (`make render-caddy-simple`)**:
- Domain: `:80` (HTTP only)
- TLS: (none)
- Log Level: `debug`
- Upstream: `code-server:8080`

## Preventing Accidental Commits

### Git Configuration

**`.gitignore`** — Prevents rendered files from being accidentally staged:
```
# Only Caddyfile.tpl is committed (single source of truth)
Caddyfile
Caddyfile.onprem
Caddyfile.simple
```

### Pre-Commit Hook

**`.pre-commit-hooks.yaml`** — Blocks commits of rendered files:

```yaml
- id: no-rendered-caddyfiles
  name: Prevent committing rendered Caddyfile variants
  entry: bash -c '
    rendered_files=(Caddyfile Caddyfile.onprem Caddyfile.simple)
    for file in "${rendered_files[@]}"; do
      if git diff --cached --name-only | grep -q "^$file$"; then
        echo "❌ ERROR: Cannot commit $file (rendered artifact from Caddyfile.tpl)"
        exit 1
      fi
    done
  '
```

If you accidentally try to commit a rendered file:

```bash
$ git commit -m "Add Caddyfile"
❌ ERROR: Cannot commit Caddyfile (rendered artifact from Caddyfile.tpl)
FIX: Remove from staging with: git reset Caddyfile
```

**Fix:** Remove the file from staging:
```bash
git reset Caddyfile
```

## Troubleshooting

### "Caddyfile not found" in Docker container

**Cause:** Rendering step was skipped during build.

**Fix:**
```bash
# Local testing
make render-caddy-all
docker-compose up -d

# Production
# Ensure Dockerfile.caddy includes: RUN envsubst < Caddyfile.tpl > Caddyfile
```

### Variables not interpolating (showing `$VARIABLE_NAME` in output)

**Cause:** Template file has unescaped `$` characters or `envsubst` is missing.

**Fix:**
1. Check `.env` file exists and variables are exported:
   ```bash
   source .env
   echo $CADDY_DOMAIN  # Should print the value
   ```

2. Run rendering manually:
   ```bash
   make render-caddy-prod
   cat Caddyfile | grep "example.com"  # Verify interpolation
   ```

### Caddyfile syntax errors after rendering

**Cause:** Invalid variable values causing malformed Caddy config.

**Fix:**
1. Validate syntax:
   ```bash
   make caddy-validate
   ```

2. Check rendered file:
   ```bash
   cat Caddyfile
   ```

3. Verify environment variables:
   ```bash
   env | grep CADDY  # Check exported variables
   ```

## Development Workflow

### Adding a New Environment Variant

1. **Add new Makefile target** in `Makefile`:
   ```makefile
   render-caddy-staging:
   	@echo "Rendering Caddyfile.staging from Caddyfile.tpl..."
   	@CADDY_DOMAIN=staging.example.com \
   	  CADDY_TLS_BLOCK="tls /etc/caddy/certs/staging.crt /etc/caddy/certs/staging.key" \
   	  CADDY_LOG_LEVEL=warn \
   	  CODE_SERVER_UPSTREAM=oauth2-proxy:4180 \
   	  ... envsubst ... < Caddyfile.tpl > Caddyfile.staging
   ```

2. **Add to `render-caddy-all` dependency**:
   ```makefile
   render-caddy-all: render-caddy-prod render-caddy-onprem render-caddy-simple render-caddy-staging
   ```

3. **Update `.gitignore`** to exclude the new variant:
   ```
   Caddyfile.staging
   ```

4. **Test locally**:
   ```bash
   make render-caddy-staging
   cat Caddyfile.staging
   make caddy-validate
   ```

### Updating the Template

1. **Edit `Caddyfile.tpl`** with new configuration
2. **Test all variants**:
   ```bash
   make render-caddy-all
   make caddy-validate
   ```
3. **Verify each variant works**:
   ```bash
   docker-compose -f docker-compose.yml up -d caddy
   curl -I http://localhost  # Test on-prem variant
   ```
4. **Commit only the template**:
   ```bash
   git add Caddyfile.tpl
   git commit -m "chore(caddy): Update Caddyfile template for new feature"
   ```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Render Caddyfile variants
  run: make render-caddy-all

- name: Validate Caddy configuration
  run: make caddy-validate

- name: Build Docker images
  run: docker-compose build

- name: Deploy to production
  run: docker-compose up -d
```

## Best Practices

✅ **DO:**
- Commit **only `Caddyfile.tpl`** to the repository
- Use template variables for all environment-specific values
- Render variants **at build/deployment time**
- Validate syntax **before deployment** with `make caddy-validate`
- Document new variants in this guide

❌ **DON'T:**
- Commit rendered `Caddyfile`, `Caddyfile.onprem`, `Caddyfile.simple`
- Hardcode domain names, ports, or TLS settings
- Manually edit rendered files (they will be regenerated)
- Store credentials or secrets in templates (use environment variables or external secret stores)

## References

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddyfile Syntax](https://caddyserver.com/docs/caddyfile/concepts)
- [Template Variable Substitution (envsubst)](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html)
- [Makefile Targets](../Makefile) — Lines 1000–1050
- [Pre-commit Hooks](../.pre-commit-hooks.yaml) — `no-rendered-caddyfiles` rule
