# Test Utilities Module - Usage Guide

**Location:** `apps/_shared/python/test_utilities.py`  
**Version:** 1.0.0  
**Status:** ✅ Production Ready

---

## Overview

Centralized test utilities module providing reusable fixtures and helpers to eliminate code duplication across the CodeServer CI/CD pipeline. Supports Docker, Docker Compose, YAML, shell scripts, JSON, and comprehensive test reporting.

## Quick Start

### Import the Module

```python
from apps._shared.python.test_utilities import (
    TestEnvironment,
    DockerTestHelper,
    ComposeTestHelper,
    YAMLTestHelper,
    ShellScriptTestHelper,
    TestReporter,
)
```

### Create an Isolated Test Environment

```python
from pathlib import Path

# Create managed test environment with automatic cleanup
env = TestEnvironment(cleanup_on_exit=True)

# Use temporary directory
with env.temp_directory(prefix="my_test_") as temp_dir:
    test_file = temp_dir / "test.txt"
    test_file.write_text("test data")
    # Directory automatically cleaned up when exiting context

# Use temporary file with content
with env.temp_file("file content", suffix=".json") as temp_file:
    # Use temp_file for testing
    pass
```

---

## Classes and Methods

### TestResult

Standardized result format for all tests.

```python
from apps._shared.python.test_utilities import TestResult

result = TestResult(
    name="test_deployment_validation",
    passed=True,
    duration_ms=1234.5,
    error_message=None,
    output="Test output captured here"
)

# Convert to JSON
result_dict = result.to_dict()
```

### TestEnvironment

Manage isolated test environments with automatic cleanup.

```python
env = TestEnvironment(cleanup_on_exit=True)

# Create temporary directory
with env.temp_directory(prefix="test_") as temp_dir:
    # Run tests
    pass

# Create temporary file
with env.temp_file("content", suffix=".yaml") as temp_file:
    # Use file for testing
    pass

# Manual cleanup when needed
env.cleanup()
```

### DockerTestHelper

Utilities for Docker container operations.

```python
from apps._shared.python.test_utilities import DockerTestHelper

# Check if image exists
if DockerTestHelper.image_exists("python:3.11"):
    print("Image found locally")

# Start a test container
container_id = DockerTestHelper.start_container(
    image="python:3.11",
    name="test-python",
    env=["PYTHONUNBUFFERED=1"],
    ports=["8000:8000"]
)

# Get container logs
logs = DockerTestHelper.get_container_logs(container_id)
print(logs)

# Stop container
DockerTestHelper.stop_container(container_id)
```

### ComposeTestHelper

Utilities for Docker Compose file validation and testing.

```python
from pathlib import Path
from apps._shared.python.test_utilities import ComposeTestHelper

compose_file = Path("docker-compose.yml")

# Validate compose file
is_valid, error = ComposeTestHelper.validate_compose_file(compose_file)
if not is_valid:
    print(f"Validation error: {error}")

# Get list of services
services = ComposeTestHelper.get_services(compose_file)
print(f"Services: {services}")

# Start services with specific profile
success = ComposeTestHelper.up_services(compose_file, profile="observability")

# Stop services
ComposeTestHelper.down_services(compose_file)
```

### YAMLTestHelper

Utilities for YAML file operations.

```python
from pathlib import Path
from apps._shared.python.test_utilities import YAMLTestHelper

yaml_file = Path("config.yaml")

# Validate YAML syntax
is_valid, error = YAMLTestHelper.validate_yaml(yaml_file)

# Load YAML file
config = YAMLTestHelper.load_yaml(yaml_file)

# Find all values for a specific key
api_keys = YAMLTestHelper.find_values_by_key(config, "api_key")
```

### ShellScriptTestHelper

Utilities for shell script validation and execution.

```python
from pathlib import Path
from apps._shared.python.test_utilities import ShellScriptTestHelper

script = Path("scripts/deploy.sh")

# Validate script syntax
is_valid, error = ShellScriptTestHelper.validate_script(script)
if not is_valid:
    print(f"Syntax error: {error}")

# Check script requirements
requirements = ShellScriptTestHelper.check_script_requirements(script)
print(f"Has shebang: {requirements['has_shebang']}")
print(f"Has error handling: {requirements['has_error_trap']}")

# Execute script
exit_code, stdout, stderr = ShellScriptTestHelper.execute_script(
    script,
    args=["--dry-run", "--verbose"]
)
print(f"Exit code: {exit_code}")
```

### JsonSchemaTestHelper

Utilities for JSON file operations.

```python
from pathlib import Path
from apps._shared.python.test_utilities import JsonSchemaTestHelper

json_file = Path("data.json")

# Validate JSON syntax
is_valid, error = JsonSchemaTestHelper.validate_json(json_file)

# Load JSON file
data = JsonSchemaTestHelper.load_json(json_file)
```

### TestReporter

Generate test reports in multiple formats.

```python
from pathlib import Path
from apps._shared.python.test_utilities import TestReporter, TestResult

reporter = TestReporter(output_dir=Path("./test-reports"))

# Add test results
reporter.add_result(TestResult(
    name="test_api_endpoint",
    passed=True,
    duration_ms=250.5
))

reporter.add_result(TestResult(
    name="test_database_connection",
    passed=False,
    duration_ms=1500.0,
    error_message="Connection timeout"
))

# Generate reports
json_report = reporter.generate_json_report("results.json")
text_report = reporter.generate_text_report("results.txt")
```

---

## Complete Example: CI/CD Pipeline Test

```python
"""
Example: Comprehensive Docker Compose validation test
"""
from pathlib import Path
from apps._shared.python.test_utilities import (
    TestEnvironment,
    ComposeTestHelper,
    ShellScriptTestHelper,
    TestReporter,
    TestResult,
)
import time

def test_deployment_pipeline():
    """Test complete deployment pipeline"""
    env = TestEnvironment()
    reporter = TestReporter()
    
    try:
        # Test 1: Validate compose file syntax
        start = time.time()
        compose_file = Path("docker-compose.yml")
        is_valid, error = ComposeTestHelper.validate_compose_file(compose_file)
        duration = (time.time() - start) * 1000
        
        reporter.add_result(TestResult(
            name="validate_compose_syntax",
            passed=is_valid,
            duration_ms=duration,
            error_message=error
        ))
        
        if not is_valid:
            raise RuntimeError("Compose file validation failed")
        
        # Test 2: Extract and validate services
        start = time.time()
        services = ComposeTestHelper.get_services(compose_file)
        duration = (time.time() - start) * 1000
        
        reporter.add_result(TestResult(
            name="extract_services",
            passed=len(services) > 0,
            duration_ms=duration,
            output=f"Found {len(services)} services"
        ))
        
        # Test 3: Validate deployment scripts
        start = time.time()
        deploy_script = Path("scripts/ops/deploy.sh")
        is_valid, error = ShellScriptTestHelper.validate_script(deploy_script)
        duration = (time.time() - start) * 1000
        
        requirements = ShellScriptTestHelper.check_script_requirements(deploy_script)
        
        reporter.add_result(TestResult(
            name="validate_deploy_script",
            passed=is_valid and requirements.get('has_error_trap', False),
            duration_ms=duration,
            error_message=error,
            output=f"Requirements met: {requirements}"
        ))
        
    finally:
        # Generate reports
        reporter.generate_json_report()
        reporter.generate_text_report()
        env.cleanup()
    
    return reporter

# Run test
if __name__ == "__main__":
    reporter = test_deployment_pipeline()
    print("✓ Tests completed - see test-reports/ for details")
```

---

## Best Practices

### Use Context Managers

Always use context managers for automatic resource cleanup:

```python
# ✅ GOOD: Automatic cleanup
env = TestEnvironment()
with env.temp_directory() as temp_dir:
    # Use temp_dir
    pass

# ❌ AVOID: Manual cleanup required
temp_dir = tempfile.mkdtemp()
# Remember to cleanup!
```

### Catch Exceptions Properly

```python
# ✅ GOOD: Comprehensive error handling
try:
    compose_file = Path("docker-compose.yml")
    is_valid, error = ComposeTestHelper.validate_compose_file(compose_file)
    if not is_valid:
        log.error(f"Validation failed: {error}")
except Exception as e:
    log.error(f"Unexpected error: {e}")

# ❌ AVOID: Silent failures
is_valid, error = ComposeTestHelper.validate_compose_file(compose_file)
# Error ignored silently
```

### Generate Reports for CI/CD

Always generate reports for CI/CD pipeline integration:

```python
reporter = TestReporter(output_dir=Path("./test-reports"))

# ... run tests ...

# Generate both JSON and text reports
reporter.generate_json_report("results.json")
reporter.generate_text_report("results.txt")

# Use JSON report in CI pipelines for parsing
# Use text report for human-readable output
```

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Run test suite
  run: |
    python3 scripts/ci/run_tests.py
    
- name: Upload test reports
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: test-reports
    path: test-reports/
```

---

## Troubleshooting

### Docker Commands Fail

Ensure Docker daemon is running:

```bash
docker ps  # Should list containers
```

### YAML Validation Errors

Validate YAML manually:

```bash
python3 -c "import yaml; yaml.safe_load(open('file.yaml'))"
```

### Permission Errors in Tests

Use `TestEnvironment` to create writable directories:

```python
env = TestEnvironment()
with env.temp_directory() as temp_dir:
    # Directory is writable and will be cleaned up
    (temp_dir / "test.txt").write_text("content")
```

---

## Contributing

To extend the test utilities module:

1. Add new helper methods to existing classes
2. Maintain consistent error handling patterns
3. Update this documentation with examples
4. Run syntax validation: `python3 -m py_compile apps/_shared/python/test_utilities.py`

---

## Version History

- **1.0.0** (2026-04-28): Initial release with 8 core classes
