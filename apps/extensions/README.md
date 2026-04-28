# Extensions Service

Plugin ecosystem and extension management system for Code Server Enterprise. Provides extension marketplace, lifecycle management, dependency resolution, and secure plugin execution.

## Architecture Overview

Extensions Service provides:

- **Extension Marketplace**: Centralized repository of vetted extensions
- **Lifecycle Management**: Install, update, enable, disable extensions
- **Dependency Resolution**: Automatic dependency management and conflict detection
- **Version Management**: Support multiple versions per extension
- **Security Scanning**: Vulnerability scanning before installation
- **Permission Management**: Granular permission model for extensions
- **Sandboxing**: Isolated execution environment for untrusted extensions
- **Performance Monitoring**: Track extension impact on system resources

## Core Components

### 1. Extension Registry

```python
# Example: Register new extension
POST /extensions/register
{
    "name": "code-review-assistant",
    "version": "1.0.0",
    "author": "developer@company.com",
    "description": "AI-powered code review suggestions",
    "repository": "https://github.com/company/code-review-assistant",
    "tags": ["code-review", "ai", "productivity"],
    "permissions": ["read:code", "write:suggestions", "access:api"],
    "dependencies": {
        "prompt-gateway": "^1.0.0",
        "memory-engine": "^1.0.0"
    },
    "activation_events": ["onCommand:codeReview.start"]
}

Response:
{
    "extension_id": "ext-001",
    "version": "1.0.0",
    "status": "registered",
    "security_scan": "passed",
    "marketplace_url": "/marketplace/extensions/code-review-assistant"
}
```

### 2. Extension Manager

```python
# Example: Install extension
POST /extensions/install
{
    "extension_id": "ext-001",
    "version": "1.0.0",
    "user_id": "user-001",
    "auto_update": true
}

Response:
{
    "extension_id": "ext-001",
    "status": "installing",
    "progress": 0,
    "estimated_duration_seconds": 15,
    "installation_id": "inst-001"
}
```

### 3. Permission Manager

```python
# Example: Grant extension permissions
POST /extensions/{ext_id}/permissions
{
    "permissions": ["read:code", "write:suggestions"],
    "resources": ["workspace/*", "git/*"],
    "expiration_days": 30
}

Response:
{
    "extension_id": "ext-001",
    "permissions_granted": 2,
    "resources": ["workspace/*", "git/*"],
    "expires_at": "2026-05-28T10:00:00Z"
}
```

### 4. Marketplace

```python
# Example: Search marketplace
GET /marketplace/extensions?search=code+review&category=productivity&sort=rating

Response:
{
    "total": 47,
    "results": [
        {
            "extension_id": "ext-001",
            "name": "code-review-assistant",
            "version": "1.0.0",
            "author": "developer@company.com",
            "rating": 4.8,
            "downloads": 2345,
            "description": "AI-powered code review suggestions"
        }
    ]
}
```

## API Endpoints

### Extension Management

```bash
# List installed extensions
GET /extensions?user_id=user-001&status=active

# Get extension details
GET /extensions/{ext_id}

# Install extension
POST /extensions/install
{...}

# Uninstall extension
DELETE /extensions/{ext_id}

# Update extension
PUT /extensions/{ext_id}/update

# Enable/disable extension
PUT /extensions/{ext_id}/status
{
    "status": "enabled|disabled"
}
```

### Marketplace

```bash
# Search marketplace
GET /marketplace/extensions?search=...&category=...&sort=...

# Get extension details from marketplace
GET /marketplace/extensions/{ext_id}

# Get categories
GET /marketplace/categories

# Get featured extensions
GET /marketplace/featured
```

### Permissions

```bash
# List permissions
GET /extensions/{ext_id}/permissions

# Grant permissions
POST /extensions/{ext_id}/permissions

# Revoke permissions
DELETE /extensions/{ext_id}/permissions/{permission_id}

# Request permissions (extension initiated)
POST /extensions/{ext_id}/request-permissions
{
    "permissions": ["read:code"]
}
```

### Health & Metrics

```bash
# Get extension health
GET /extensions/{ext_id}/health

Response:
{
    "status": "healthy",
    "cpu_usage_percent": 2.3,
    "memory_usage_mb": 45,
    "activation_count": 1234,
    "error_rate": 0.01,
    "last_error": null
}
```

## Configuration

### Environment Variables

```bash
# Extension Registry
EXTENSIONS_REGISTRY_DB_URL=postgresql://...
EXTENSIONS_MARKETPLACE_URL=https://marketplace.code-server.com

# Security
EXTENSIONS_SECURITY_SCAN_ENABLED=true
EXTENSIONS_SANDBOX_ENABLED=true
EXTENSIONS_PERMISSIONS_STRICT_MODE=true

# Performance
EXTENSIONS_MAX_MEMORY_MB=500
EXTENSIONS_MAX_CPU_PERCENT=50
EXTENSIONS_EXECUTION_TIMEOUT_SECONDS=300

# Versioning
EXTENSIONS_ALLOW_PRERELEASE=false
EXTENSIONS_AUTO_UPDATE_ENABLED=true
```

### Docker Compose Configuration

```yaml
extensions:
  image: kushin77/code-server-extensions@sha256:vwx234...
  ports:
    - "8016:8000"
  environment:
    - EXTENSIONS_REGISTRY_DB_URL=postgresql://postgres:password@postgres:5432/extensions_db
    - EXTENSIONS_SANDBOX_ENABLED=true
  depends_on:
    - postgres
    - redis
  volumes:
    - /var/lib/extensions:/var/lib/extensions
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 30s
```

## Extension Lifecycle

### States

```
Draft → Submitted → Scanning → Approved → Published
    ↓
   Rejected → Revisions Needed
```

### Installation Lifecycle

```
Available → Installing → Extracting Dependencies 
  ↓
Installed → Enabling → Activating → Active
  ↓         (Error) → Failed
  
Active → Disabling → Disabled
```

## Permission Model

### Standard Permissions

```
read:code           - Read code from workspace
write:code          - Modify code in workspace
read:config         - Read configuration
write:config        - Modify configuration
access:api          - Access Code Server API
access:filesystem   - Access filesystem
access:git          - Access git operations
access:terminal     - Run terminal commands
access:debug        - Run debugger
```

## Built-in Extensions

### Code Formatter

```yaml
name: Code Formatter
description: Automatic code formatting with prettier/black
version: 1.0.0
permissions:
  - read:code
  - write:code
supported_languages:
  - javascript
  - python
  - typescript
  - go
```

### Git Integration

```yaml
name: Git Integration
description: Enhanced Git operations and visualizations
version: 1.0.0
permissions:
  - access:git
  - read:code
  - read:filesystem
features:
  - branch visualization
  - commit history
  - merge conflict resolution
```

### Debugger

```yaml
name: Advanced Debugger
description: Enhanced debugging capabilities
version: 1.0.0
permissions:
  - access:debug
  - read:code
  - write:code
supported_languages:
  - python
  - javascript
  - go
  - rust
```

## Security Model

### Extension Scanning

1. **Static Analysis**: Check for malicious patterns
2. **Dependency Audit**: Scan dependencies for vulnerabilities
3. **Permission Review**: Verify requested permissions are reasonable
4. **Code Review**: Manual review for high-permission extensions
5. **Sandbox Testing**: Run in isolated environment

### Runtime Protection

```python
{
    "sandbox": {
        "enabled": true,
        "filesystem_access": "restricted",
        "network_access": "monitored",
        "cpu_limit_percent": 50,
        "memory_limit_mb": 500,
        "execution_timeout_seconds": 300
    }
}
```

## Monitoring & Observability

### Key Metrics

```
extensions_installed_total
extensions_active_count
extensions_errors_total
extensions_cpu_usage_percent
extensions_memory_usage_mb
extensions_activation_events_total
extensions_security_violations_total
marketplace_search_requests_total
marketplace_downloads_total
```

## Production Deployment Checklist

- [ ] PostgreSQL database for registry
- [ ] Redis for caching
- [ ] Security scanning service operational
- [ ] Sandbox runtime configured
- [ ] Marketplace UI deployed
- [ ] Extension signing keys configured
- [ ] Backup procedures tested
- [ ] Monitoring configured
- [ ] Documentation complete

## Related Services

- **control-plane**: Extension lifecycle orchestration
- **event-bus**: Extension event publishing
- **reputation_engine**: Extension author reputation

## Support & Documentation

For additional support, see:

- [Extension Development Guide](../../COMPLETE_35_SERVICE_REFERENCE.md)
- [GitHub Issues](https://github.com/kushin77/code-server/issues) - Tag: extensions

---

**Status**: Production Ready  
**Last Updated**: April 28, 2026
