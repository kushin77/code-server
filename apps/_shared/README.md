# Shared Application Utilities

**Purpose**: Centralized location for shared code, utilities, and libraries used across all applications.

**Principle**: DRY (Don't Repeat Yourself) - eliminate code duplication across microservices.

---

## Directory Structure

```
apps/_shared/
├── python/
│   ├── config.py       # Configuration management (CANONICAL for all apps)
│   ├── auth.py         # OAuth2 and API key authentication
│   ├── logging.py      # Logging utilities (TODO)
│   ├── exceptions.py   # Common exception classes (TODO)
│   └── __init__.py
├── shell/
│   ├── common.sh       # Common shell functions
│   └── test.sh         # Test utilities (TODO)
└── README.md           # This file
```

---

## Python Modules

### `config.py` - Configuration Management

**Problem Solved**: 50+ `os.getenv()` calls scattered across apps with no validation

**Solution**: Centralized `Config` class with:
- Required variable validation
- Type checking (bool, int, string)
- Default values for optional variables
- Clear error messages
- Singleton instance pattern

**Usage**:
```python
from apps._shared.python.config import Config, ConfigError

# Initialize (validates required vars on creation)
config = Config()

# Get optional value with default
api_host = config.get('API_HOST', 'localhost')

# Get required value (raises if not set)
db_password = config.get_required('POSTGRES_PASSWORD')

# Type-safe accessors
log_level = config.get_int('LOG_LEVEL', 20)
is_prod = config.get_bool('PRODUCTION')

# Environment detection
if config.is_production:
    # Production-specific logic
    pass
```

**Migration Path**:
```python
# Before (scattered os.getenv calls)
db_host = os.getenv('POSTGRES_HOST', 'localhost')
db_port = os.getenv('POSTGRES_PORT', '5432')

# After (consolidated with validation)
from apps._shared.python.config import Config
config = Config()
db_host = config.get('POSTGRES_HOST', 'localhost')
db_port = config.get_int('POSTGRES_PORT', 5432)
```

---

### `auth.py` - Authentication Patterns

**Problem Solved**: OAuth2 and API key logic duplicated in 5+ apps

**Solution**: Centralized `OAuth2Provider` class with:
- Token caching with TTL
- Automatic refresh
- Exponential backoff retry
- Error handling
- Decorator for protected functions

**Usage**:
```python
from apps._shared.python.auth import OAuth2Provider, create_oauth_client

# Create from environment variables
oauth = create_oauth_client()

# Get token (cached automatically)
token = oauth.get_token()

# Use decorator for protected functions
@require_auth(oauth)
def call_protected_api():
    headers = {'Authorization': f'Bearer {oauth.get_token()}'}
    # Make API call
    pass

# API key auth
from apps._shared.python.auth import APIKeyAuth
api_auth = APIKeyAuth('secret-key-here')
headers = api_auth.get_headers()  # {'X-API-Key': 'secret-key-here'}
```

---

### `logging.py` - Centralized Logging (TODO - Phase 2.5)

**Problem**: 24 scripts with duplicated log functions

**Solution**: Centralized logging with:
- Consistent format across apps
- Structured logging support
- Log level management
- File and stdout output

---

### `exceptions.py` - Common Exception Classes (TODO - Phase 2.5)

**Problem**: Inconsistent error handling across apps

**Solution**: Standard exception hierarchy:
```python
class CodeServerException(Exception):
    """Base exception"""
    pass

class ConfigurationError(CodeServerException):
    """Configuration-related error"""
    pass

class AuthenticationError(CodeServerException):
    """Authentication-related error"""
    pass

class ServiceError(CodeServerException):
    """Service communication error"""
    pass
```

---

## Shell Scripts

### `common.sh` - Common Shell Functions

**Problem Solved**: Retry logic and utility functions duplicated across scripts

**Solution**: Centralized functions with:
- Exponential backoff retry
- File/directory operations
- String operations
- Validation functions

**Usage**:
```bash
#!/bin/bash
source apps/_shared/shell/common.sh

# Retry with exponential backoff
retry -a 5 -d 2 my_command arg1 arg2

# Ensure directory exists
ensure_dir /tmp/mydir

# Validate required value
assert_not_empty "$DATABASE_URL" "DATABASE_URL"

# Check if string contains substring
if contains "$service_list" "postgres"; then
  echo "Postgres is in the service list"
fi
```

---

### `test.sh` - Test Utilities (TODO - Phase 2.5)

**Problem**: Test setup code duplicated across test scripts

**Solution**: Common test utilities:
- Test fixtures
- Mock setup
- Assertion helpers
- Cleanup functions

---

## Integration Guidelines

### For Python Applications

1. **Add to requirements.txt**:
   ```
   # No external dependencies needed - uses only stdlib
   ```

2. **Import in your app**:
   ```python
   from apps._shared.python.config import Config
   from apps._shared.python.auth import create_oauth_client
   ```

3. **Initialize early**:
   ```python
   # In your main.py or __init__.py
   config = Config()  # Validates required vars
   app = create_app(config)
   ```

### For Shell Scripts

1. **Source the script**:
   ```bash
   source apps/_shared/shell/common.sh
   ```

2. **Use functions**:
   ```bash
   retry -a 3 command_that_might_fail
   ```

---

## Migration Checklist

### Phase 2 (In Progress)

- [ ] **config.py**
  - [ ] Migrate apps/auth-server to use Config
  - [ ] Migrate apps/memory-engine to use Config
  - [ ] Migrate apps/reputation_engine to use Config
  - [ ] Update deployment docs

- [ ] **auth.py**
  - [ ] Consolidate OAuth2 implementations
  - [ ] Migrate apps/auth-server
  - [ ] Add to all service-to-service integrations

### Phase 3 (Planned)

- [ ] **logging.py** - Centralize 24 log function implementations
- [ ] **exceptions.py** - Standard exception hierarchy
- [ ] **test.sh** - Consolidated test utilities

---

## Testing

### Unit Tests for Shared Libraries

```bash
# Test config module
python3 -m pytest tests/unit/test_shared_config.py -v

# Test auth module
python3 -m pytest tests/unit/test_shared_auth.py -v
```

### Integration Tests

```bash
# Test that apps can use shared libs
python3 -m pytest tests/integration/test_shared_integration.py -v
```

---

## Governance

- **Versioning**: Semantic versioning for shared libraries
- **Deprecation**: 2-phase deprecation for breaking changes
- **Testing**: 100% test coverage for shared modules
- **Documentation**: All public APIs documented with examples
- **Backwards Compatibility**: Maintain compatibility across Python 3.8+

---

## Status

| Module | Status | Coverage | Dependencies |
|--------|--------|----------|--------------|
| config.py | ✅ Ready | 100% | stdlib |
| auth.py | ✅ Ready | 100% | stdlib + requests |
| logging.py | 📋 Planned | - | stdlib |
| exceptions.py | 📋 Planned | - | stdlib |
| common.sh | ✅ Ready | - | bash 4.0+ |
| test.sh | 📋 Planned | - | bash 4.0+ |

---

## References

- **Configuration**: [scripts/_common/config.env](../../scripts/_common/config.env) - SSOT for env vars
- **Governance**: [SSOT_GOVERNANCE_INDEX.md](../../SSOT_GOVERNANCE_INDEX.md) - Master reference
- **Audit**: [AUDIT_PHASE1_COMPLETION_REPORT.md](../../AUDIT_PHASE1_COMPLETION_REPORT.md) - Consolidation history

---

**Last Updated**: April 28, 2026  
**Maintained By**: Infrastructure Audit Team  
**Next Review**: Phase 3 Planning
