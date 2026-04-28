"""
@module apps/_shared/python/test_utilities.py
@description Centralized test utilities for CodeServer CI/CD pipeline
@governance GOV-002: Reusable test fixtures and helpers to eliminate code duplication
"""

import os
import sys
import json
import tempfile
import subprocess
import shutil
from typing import Dict, List, Optional, Tuple, Any
from pathlib import Path
from contextlib import contextmanager
from dataclasses import dataclass


@dataclass
class TestResult:
    """Standardized test result format"""
    name: str
    passed: bool
    duration_ms: float
    error_message: Optional[str] = None
    output: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            'name': self.name,
            'passed': self.passed,
            'duration_ms': self.duration_ms,
            'error_message': self.error_message,
            'output': self.output,
        }


class TestEnvironment:
    """Manage isolated test environments"""
    
    def __init__(self, cleanup_on_exit: bool = True):
        self.cleanup_on_exit = cleanup_on_exit
        self.temp_dirs: List[Path] = []
        self.docker_containers: List[str] = []
    
    @contextmanager
    def temp_directory(self, prefix: str = "test_") -> Path:
        """Create a temporary directory that's cleaned up after use"""
        temp_dir = Path(tempfile.mkdtemp(prefix=prefix))
        self.temp_dirs.append(temp_dir)
        try:
            yield temp_dir
        finally:
            if self.cleanup_on_exit:
                shutil.rmtree(temp_dir, ignore_errors=True)
    
    @contextmanager
    def temp_file(self, content: str, suffix: str = ".txt") -> Path:
        """Create a temporary file with content"""
        with tempfile.NamedTemporaryFile(mode='w', suffix=suffix, delete=False) as f:
            f.write(content)
            temp_file = Path(f.name)
        
        try:
            yield temp_file
        finally:
            if self.cleanup_on_exit:
                temp_file.unlink(missing_ok=True)
    
    def cleanup(self):
        """Clean up all resources"""
        for temp_dir in self.temp_dirs:
            shutil.rmtree(temp_dir, ignore_errors=True)
        
        for container_id in self.docker_containers:
            subprocess.run(
                ['docker', 'rm', '-f', container_id],
                capture_output=True
            )


class DockerTestHelper:
    """Utilities for Docker-based testing"""
    
    @staticmethod
    def image_exists(image: str) -> bool:
        """Check if a Docker image exists locally"""
        result = subprocess.run(
            ['docker', 'image', 'inspect', image],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    
    @staticmethod
    def start_container(image: str, name: str, **kwargs) -> str:
        """Start a Docker container for testing"""
        cmd = ['docker', 'run', '-d', '--name', name]
        
        # Add optional parameters
        for env_var in kwargs.get('env', []):
            cmd.extend(['-e', env_var])
        
        for port in kwargs.get('ports', []):
            cmd.extend(['-p', port])
        
        for volume in kwargs.get('volumes', []):
            cmd.extend(['-v', volume])
        
        cmd.append(image)
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to start container: {result.stderr}")
        
        return result.stdout.strip()
    
    @staticmethod
    def stop_container(container_id: str) -> bool:
        """Stop and remove a Docker container"""
        result = subprocess.run(
            ['docker', 'rm', '-f', container_id],
            capture_output=True
        )
        return result.returncode == 0
    
    @staticmethod
    def get_container_logs(container_id: str) -> str:
        """Retrieve logs from a container"""
        result = subprocess.run(
            ['docker', 'logs', container_id],
            capture_output=True,
            text=True
        )
        return result.stdout


class ComposeTestHelper:
    """Utilities for Docker Compose testing"""
    
    @staticmethod
    def validate_compose_file(file_path: Path) -> Tuple[bool, Optional[str]]:
        """Validate a docker-compose.yml file"""
        try:
            import yaml
            with open(file_path) as f:
                yaml.safe_load(f)
            return True, None
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def get_services(file_path: Path) -> List[str]:
        """Extract list of services from docker-compose file"""
        import yaml
        with open(file_path) as f:
            config = yaml.safe_load(f)
        
        return list(config.get('services', {}).keys())
    
    @staticmethod
    def up_services(file_path: Path, profile: Optional[str] = None) -> bool:
        """Start services defined in docker-compose file"""
        cmd = ['docker-compose', '-f', str(file_path), 'up', '-d']
        
        if profile:
            cmd.extend(['--profile', profile])
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode == 0
    
    @staticmethod
    def down_services(file_path: Path) -> bool:
        """Stop and remove services"""
        result = subprocess.run(
            ['docker-compose', '-f', str(file_path), 'down'],
            capture_output=True
        )
        return result.returncode == 0


class YAMLTestHelper:
    """Utilities for YAML validation and testing"""
    
    @staticmethod
    def validate_yaml(file_path: Path) -> Tuple[bool, Optional[str]]:
        """Validate YAML file syntax"""
        try:
            import yaml
            with open(file_path) as f:
                yaml.safe_load(f)
            return True, None
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def load_yaml(file_path: Path) -> Optional[Dict]:
        """Load and parse YAML file"""
        try:
            import yaml
            with open(file_path) as f:
                return yaml.safe_load(f)
        except Exception:
            return None
    
    @staticmethod
    def find_values_by_key(data: Dict, key: str) -> List[Any]:
        """Find all values for a given key in nested structure"""
        values = []
        
        if isinstance(data, dict):
            for k, v in data.items():
                if k == key:
                    values.append(v)
                values.extend(YAMLTestHelper.find_values_by_key(v, key))
        elif isinstance(data, list):
            for item in data:
                values.extend(YAMLTestHelper.find_values_by_key(item, key))
        
        return values


class ShellScriptTestHelper:
    """Utilities for shell script testing"""
    
    @staticmethod
    def validate_script(script_path: Path) -> Tuple[bool, Optional[str]]:
        """Validate shell script syntax"""
        result = subprocess.run(
            ['bash', '-n', str(script_path)],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            return False, result.stderr
        return True, None
    
    @staticmethod
    def execute_script(script_path: Path, args: Optional[List[str]] = None) -> Tuple[int, str, str]:
        """Execute a shell script and return exit code, stdout, stderr"""
        cmd = ['bash', str(script_path)]
        if args:
            cmd.extend(args)
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    
    @staticmethod
    def check_script_requirements(script_path: Path) -> Dict[str, bool]:
        """Check for common script requirements"""
        with open(script_path) as f:
            content = f.read()
        
        return {
            'has_shebang': content.startswith('#!/'),
            'has_set_euo': 'set -euo pipefail' in content or 'set -e' in content,
            'has_error_trap': 'trap' in content and 'ERR' in content,
            'has_cleanup_trap': 'trap' in content and 'EXIT' in content,
            'sources_init': 'source' in content and 'init.sh' in content,
        }


class JsonSchemaTestHelper:
    """Utilities for JSON schema validation"""
    
    @staticmethod
    def validate_json(file_path: Path) -> Tuple[bool, Optional[str]]:
        """Validate JSON file syntax"""
        try:
            with open(file_path) as f:
                json.load(f)
            return True, None
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def load_json(file_path: Path) -> Optional[Dict]:
        """Load and parse JSON file"""
        try:
            with open(file_path) as f:
                return json.load(f)
        except Exception:
            return None


class TestReporter:
    """Generate test reports in multiple formats"""
    
    def __init__(self, output_dir: Path = Path(".")):
        self.output_dir = output_dir
        self.results: List[TestResult] = []
    
    def add_result(self, result: TestResult):
        """Add a test result"""
        self.results.append(result)
    
    def generate_json_report(self, filename: str = "test-results.json"):
        """Generate JSON report of test results"""
        report = {
            'total': len(self.results),
            'passed': sum(1 for r in self.results if r.passed),
            'failed': sum(1 for r in self.results if not r.passed),
            'results': [r.to_dict() for r in self.results],
        }
        
        output_file = self.output_dir / filename
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        return output_file
    
    def generate_text_report(self, filename: str = "test-results.txt"):
        """Generate human-readable text report"""
        output_file = self.output_dir / filename
        
        with open(output_file, 'w') as f:
            f.write("=" * 60 + "\n")
            f.write("TEST RESULTS REPORT\n")
            f.write("=" * 60 + "\n\n")
            
            for result in self.results:
                status = "PASS" if result.passed else "FAIL"
                f.write(f"[{status}] {result.name} ({result.duration_ms}ms)\n")
                
                if result.error_message:
                    f.write(f"  Error: {result.error_message}\n")
            
            f.write("\n" + "=" * 60 + "\n")
            passed = sum(1 for r in self.results if r.passed)
            f.write(f"Total: {len(self.results)} | Passed: {passed} | Failed: {len(self.results) - passed}\n")
            f.write("=" * 60 + "\n")
        
        return output_file


# Export public API
__all__ = [
    'TestResult',
    'TestEnvironment',
    'DockerTestHelper',
    'ComposeTestHelper',
    'YAMLTestHelper',
    'ShellScriptTestHelper',
    'JsonSchemaTestHelper',
    'TestReporter',
]
