# Application Library Migration Guide - Phase 2B

**Status**: In Progress  
**Target**: Migrate all Python apps to use `apps._shared.python.config.Config`  
**Timeline**: Ongoing (start Phase 2B, complete by end of Phase 2C)

---

## Migration Overview

### Current State
- 20+ Python apps using scattered `os.getenv()` calls
- No validation or type safety
- Configuration scattered across multiple files
- No centralized defaults or required var checking

### Target State
- All apps using `apps._shared.python.config.Config` class
- Type-safe configuration management
- Centralized SSOT: scripts/_common/config.env
- Automatic required variable validation
- Consistent error messages

---

## Priority Tiers

### Tier 1 (Critical - This Week)
Apps that handle secrets or are core infrastructure:
1. **apps/auth-server** - OAuth2, secrets handling
2. **apps/memory-engine** - Database credentials
3. **apps/control-plane** - Core orchestration

### Tier 2 (High - Next Week)
Core service applications:
4. **apps/activity_feed** - Core feature
5. **apps/agent-runtime** - Core runtime
6. **apps/reputation_engine** - Core analysis

### Tier 3 (Medium - Week After)
Supporting services:
7-20. Other Python apps (diagrams, voice, etc.)

---

## Step-by-Step Migration Template

### Before: Using os.getenv()

```python
import os

class MyService:
    def __init__(self):
        self.db_host = os.getenv("POSTGRES_HOST", "localhost")
        self.db_port = int(os.getenv("POSTGRES_PORT", "5432"))
        self.api_key = os.getenv("API_KEY")  # No error if missing!
        self.debug = os.getenv("DEBUG", "false").lower() == "true"
```

**Problems**:
- No validation if required vars missing
- Type conversions scattered throughout code
- No centralized defaults
- Inconsistent error handling

### After: Using Config Class

```python
from apps._shared.python.config import get_config

class MyService:
    def __init__(self):
        config = get_config()
        self.db_host = config.get("POSTGRES_HOST", "localhost")
        self.db_port = config.get_int("POSTGRES_PORT", 5432)
        self.api_key = config.get_required("API_KEY")  # Fails fast if missing
        self.debug = config.get_bool("DEBUG", False)
```

**Benefits**:
- Automatic validation via get_required()
- Type-safe getters (get_int, get_bool, etc.)
- Centralized defaults in config.py
- Consistent error messages

---

## Migration Checklist

### 1. Add Import
```python
# At top of file
from apps._shared.python.config import get_config, Config
```

### 2. Identify All os.getenv() Calls
```bash
# Find all usages in your app
grep -n "os.getenv\|os.environ" apps/myapp/*.py
```

### 3. Create Config Usage Pattern

**Option A: Singleton Pattern (Recommended)**
```python
# app.py or main.py - Initialize once
config = get_config()
API_HOST = config.get("API_HOST", "0.0.0.0")
API_PORT = config.get_int("API_PORT", 8000)
DB_PASSWORD = config.get_required("DB_PASSWORD")
```

**Option B: Per-Class Pattern**
```python
# In each class that needs config
class MyService:
    def __init__(self):
        self.config = get_config()
        self.host = self.config.get("API_HOST")
```

**Option C: Legacy Compatibility**
```python
# If you need gradual migration
from apps._shared.python.config import getenv_required, load_required_vars

# Old code: Still works during transition
api_key = getenv_required("API_KEY")
```

### 4. Replace os.getenv() Calls

**Simple string values**:
```python
# Before
host = os.getenv("API_HOST", "localhost")

# After
config = get_config()
host = config.get("API_HOST", "localhost")
```

**Integer values**:
```python
# Before
port = int(os.getenv("API_PORT", "8000"))

# After
config = get_config()
port = config.get_int("API_PORT", 8000)
```

**Boolean values**:
```python
# Before
debug = os.getenv("DEBUG", "false").lower() == "true"

# After
config = get_config()
debug = config.get_bool("DEBUG", False)
```

**Required values (fail-fast)**:
```python
# Before - No validation!
api_key = os.getenv("API_KEY")

# After - Fails at startup if missing
config = get_config()
api_key = config.get_required("API_KEY")
```

### 5. Update Imports

Remove the os import if no longer needed:
```python
# Remove this if only used for getenv
# import os

# Keep this if used for other purposes
import os  # Still needed for os.path, etc.
```

### 6. Update Tests

**Before**:
```python
import os
from myapp import MyService

def test_service(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    service = MyService()
    assert service.api_key == "test-key"
```

**After**:
```python
from unittest.mock import patch
from myapp import MyService

@patch.dict('os.environ', {'API_KEY': 'test-key'})
def test_service():
    service = MyService()
    assert service.api_key == "test-key"
```

Or better yet, inject config:
```python
from apps._shared.python.config import Config

def test_service():
    config = Config(
        validate_required=False,
        _test_overrides={'API_KEY': 'test-key'}
    )
    service = MyService(config=config)
    assert service.api_key == "test-key"
```

### 7. Verify Required Variables

Ensure all required variables are defined in scripts/_common/config.env:
```bash
# Check which vars your app needs
grep -h "get_required" apps/myapp/src/*.py | sed 's/.*get_required("\([^"]*\)".*/\1/'
```

Then add to config.env:
```bash
# scripts/_common/config.env
export MY_APP_API_KEY="default-value"
export MY_APP_SECRET="default-secret"
```

### 8. Test and Validate

```bash
# Test with config.env sourced
source scripts/_common/config.env
python3 -c "from apps.myapp.main import MyService; MyService()"

# Test with validation
python3 -c "from apps._shared.python.config import Config; config = Config(validate_required=True); print(config.get_environment())"
```

---

## OAuth2 Migration Example

### Before (auth-server)

```python
# apps/auth-server/src/oauth2_server.py
import os

class OAuthServerConfig:
    def __init__(self):
        self.github_client_id = os.getenv("GITHUB_CLIENT_ID", "test-client-id")
        self.github_client_secret = os.getenv("GITHUB_CLIENT_SECRET", "test-client-secret")
        self.google_client_id = os.getenv("GOOGLE_CLIENT_ID", "test-client-id")
        self.google_client_secret = os.getenv("GOOGLE_CLIENT_SECRET", "test-client-secret")
        self.oauth_cookie_secret = os.getenv("OAUTH_COOKIE_SECRET", "test-secret")
        self.api_port = int(os.getenv("PORT", 8001))
```

### After (auth-server)

```python
# apps/auth-server/src/oauth2_server.py
from apps._shared.python.config import get_config

class OAuthServerConfig:
    def __init__(self):
        config = get_config()
        self.github_client_id = config.get_required("OAUTH2_GITHUB_CLIENT_ID")
        self.github_client_secret = config.get_required("OAUTH2_GITHUB_CLIENT_SECRET")
        self.google_client_id = config.get_required("OAUTH2_GOOGLE_CLIENT_ID")
        self.google_client_secret = config.get_required("OAUTH2_GOOGLE_CLIENT_SECRET")
        self.oauth_cookie_secret = config.get_required("OAUTH2_COOKIE_SECRET")
        self.api_port = config.get_int("API_PORT", 8001)
```

### Environment Variables (config.env)

```bash
# scripts/_common/config.env
export OAUTH2_GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID}"
export OAUTH2_GITHUB_CLIENT_SECRET="${GITHUB_CLIENT_SECRET}"
export OAUTH2_GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}"
export OAUTH2_GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}"
export OAUTH2_COOKIE_SECRET="${OAUTH_COOKIE_SECRET}"
export API_PORT="${PORT:-8001}"
```

---

## Auth.py Integration

### Before: Scattered OAuth2 Implementations

```python
# apps/auth-server/src/oauth2_server.py
import requests
import json

class OAuth2Impl:
    def get_token(self):
        response = requests.post(
            f"{self.token_endpoint}",
            json={
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "grant_type": "client_credentials"
            }
        )
        return response.json()['access_token']
```

### After: Using auth.py

```python
# apps/auth-server/src/oauth2_server.py
from apps._shared.python.auth import OAuth2Provider, create_oauth_client

class OAuth2Impl:
    def __init__(self):
        # Use canonical OAuth2Provider
        self.oauth_provider = create_oauth_client()
    
    def get_token(self):
        # Automatic token caching and refresh
        return self.oauth_provider.get_token()
```

Benefits:
- Single implementation used everywhere
- Token caching reduces API calls
- Auto-refresh before expiration
- Consistent error handling
- Testable via dependency injection

---

## Batch Migration Script

For teams migrating multiple apps:

```bash
#!/bin/bash
# migrate-to-config-py.sh

APPS=(
    "auth-server"
    "memory-engine"
    "control-plane"
    "activity_feed"
    "agent-runtime"
    "reputation_engine"
)

for app in "${APPS[@]}"; do
    echo "=== Migrating apps/$app ==="
    
    # Find all python files using os.getenv
    find "apps/$app" -name "*.py" -exec grep -l "os.getenv" {} \;
    
    # Replace imports
    find "apps/$app" -name "*.py" -exec sed -i \
        '/^import os$/a from apps._shared.python.config import get_config' {} \;
    
    # Test syntax
    python3 -m py_compile "apps/$app"/*.py && echo "✓ Syntax valid" || echo "✗ Syntax error"
    
    echo ""
done
```

---

## Validation Checklist

- [ ] All os.getenv() calls replaced with config.get*()
- [ ] All required variables have defaults or use get_required()
- [ ] All tests updated to mock/patch config
- [ ] Scripts/_common/config.env has all new variables
- [ ] App runs without errors with sourced config.env
- [ ] Integration tests pass
- [ ] Performance is acceptable (minimal overhead)

---

## Rollback Plan

If migration breaks an app:

```bash
# Option 1: Git revert (immediate)
git revert <migration-commit>

# Option 2: Keep legacy compatibility
from apps._shared.python.config import getenv_required
# Old code still works during gradual migration
```

---

## Common Issues & Solutions

### Issue 1: ImportError for config

```
ModuleNotFoundError: No module named 'apps._shared.python.config'
```

**Solution**:
```bash
# Ensure PYTHONPATH includes workspace root
export PYTHONPATH=/home/akushnir/code-server:$PYTHONPATH
python3 apps/myapp/main.py
```

### Issue 2: Required variable missing

```
ConfigError: Required variable OAUTH2_CLIENT_SECRET not found
```

**Solution**:
```bash
# Source config.env first
source scripts/_common/config.env
python3 apps/myapp/main.py
```

### Issue 3: Type conversion errors

```
ValueError: invalid literal for int() with base 10: 'abc'
```

**Solution**:
```python
# Use get_int() which validates
config.get_int("PORT", 8000)  # Returns int, validates format
```

---

## Schedule

| Week | Apps | Status |
|------|------|--------|
| Week 1 | auth-server, memory-engine, control-plane | 🔄 In Progress |
| Week 2 | activity_feed, agent-runtime, reputation_engine | 📋 Planned |
| Week 3 | Remaining 10+ apps | 📋 Planned |
| Week 4 | Full validation, documentation | 📋 Planned |

---

## Success Metrics

- ✅ All 20+ Python apps using config.py
- ✅ 50+ os.getenv() calls eliminated
- ✅ 100% type-safe configuration
- ✅ Zero missing required variable errors in production
- ✅ Centralized SSOT in scripts/_common/config.env

---

**Related Documentation**:
- [apps/_shared/python/config.py](apps/_shared/python/config.py)
- [scripts/_common/config.env](scripts/_common/config.env)
- [SSOT_GOVERNANCE_INDEX.md](SSOT_GOVERNANCE_INDEX.md)

---

**Owner**: Infrastructure Audit Team  
**Phase**: 2B (Application Library Migration)  
**Status**: Ready for Tier 1 Migration  
**Start Date**: April 28, 2026
