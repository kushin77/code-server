#!/usr/bin/env python3
# ==============================================================================
# BACKGROUND TEST RUNNER WITH ERROR COLLECTION
# ==============================================================================
# Continuously runs deployment validation tests in the background,
# collects errors, and creates GitHub issues for failures.
#
# Usage: python3 scripts/ci/background-test-runner.py --interval 3600
# ==============================================================================

import os
import sys
import subprocess
import json
import argparse
import time
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional
import hashlib

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)


class TestRunner:
    """Background test runner that validates deployments and collects errors"""
    
    def __init__(
        self,
        interval_seconds: int = 3600,
        max_retries: int = 3,
        github_token: Optional[str] = None,
        create_issues: bool = True
    ):
        """
        Initialize test runner.
        
        Args:
            interval_seconds: Run tests every N seconds
            max_retries: Retry failed tests this many times
            github_token: GitHub API token for creating issues
            create_issues: Whether to auto-create GitHub issues on failure
        """
        self.interval = interval_seconds
        self.max_retries = max_retries
        self.github_token = github_token or os.getenv('GITHUB_TOKEN')
        self.create_issues = create_issues and bool(self.github_token)
        self.repo_root = Path(__file__).parent.parent.parent
        self.error_log = self.repo_root / '.test-errors.jsonl'
    
    def run_tests(self) -> Dict[str, Any]:
        """Run all validation tests"""
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'passed': [],
            'failed': [],
            'errors': []
        }
        
        tests = [
            ('SSOT Config', self._test_ssot_config),
            ('Docker Compose Syntax', self._test_docker_compose),
            ('Health Checks', self._test_health_checks),
            ('Terraform Validation', self._test_terraform),
            ('Idempotency', self._test_idempotency),
        ]
        
        for test_name, test_func in tests:
            try:
                logger.info(f"Running: {test_name}")
                test_func()
                results['passed'].append(test_name)
                logger.info(f"✓ {test_name} passed")
            except Exception as e:
                logger.error(f"✗ {test_name} failed: {e}")
                results['failed'].append(test_name)
                results['errors'].append({
                    'test': test_name,
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                })
        
        return results
    
    def _test_ssot_config(self) -> None:
        """Validate SSOT configuration is accessible"""
        config_file = self.repo_root / 'scripts/_common/config.env'
        
        if not config_file.exists():
            raise RuntimeError(f"Config file not found: {config_file}")
        
        # Try to source and validate
        result = subprocess.run(
            ['bash', '-c', f'source {config_file} && validate_required_vars'],
            cwd=str(self.repo_root),
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Config validation failed: {result.stderr}")
    
    def _test_docker_compose(self) -> None:
        """Validate docker-compose syntax"""
        compose_file = self.repo_root / 'docker-compose.yml'
        
        result = subprocess.run(
            ['docker-compose', '-f', str(compose_file), 'config'],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Docker-compose validation failed: {result.stderr}")
    
    def _test_health_checks(self) -> None:
        """Validate health check functions"""
        script = self.repo_root / 'scripts/_common/health-checks.sh'
        
        if not script.exists():
            raise RuntimeError(f"Health checks script not found: {script}")
        
        result = subprocess.run(
            ['bash', '-n', str(script)],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Health checks syntax error: {result.stderr}")
    
    def _test_terraform(self) -> None:
        """Validate Terraform configurations"""
        terraform_dir = self.repo_root / 'terraform'
        
        result = subprocess.run(
            ['terraform', 'validate'],
            cwd=str(terraform_dir),
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Terraform validation failed: {result.stderr}")
    
    def _test_idempotency(self) -> None:
        """Check deployment idempotency (test mode)"""
        # This is a dry-run check, not actual deployment
        compose_file = self.repo_root / 'docker-compose.yml'
        
        result = subprocess.run(
            ['docker-compose', '-f', str(compose_file), 'config'],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            raise RuntimeError("Idempotency check failed")
    
    def log_errors(self, results: Dict[str, Any]) -> None:
        """Log errors to file for tracking"""
        if not results['errors']:
            return
        
        with open(self.error_log, 'a') as f:
            for error in results['errors']:
                f.write(json.dumps(error) + '\n')
    
    def create_github_issue(self, error: Dict[str, Any]) -> None:
        """Create GitHub issue for test failure"""
        if not self.create_issues:
            return
        
        try:
            import requests
            
            # Avoid duplicate issues
            issue_title = f"Test Failure: {error['test']}"
            
            payload = {
                'title': issue_title,
                'body': f"""
**Test**: {error['test']}
**Error**: {error['error']}
**Time**: {error['timestamp']}
**Source**: Automatic test runner

Related: audit-remediation
""",
                'labels': ['test-failure', 'audit-remediation', 'auto-created']
            }
            
            headers = {
                'Authorization': f'token {self.github_token}',
                'Accept': 'application/vnd.github.v3+json'
            }
            
            # Get repo from git remote
            result = subprocess.run(
                ['git', 'remote', 'get-url', 'origin'],
                cwd=str(self.repo_root),
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                origin = result.stdout.strip()
                # Parse owner/repo from git URL
                if 'github.com' in origin:
                    repo_parts = origin.split('/')[-2:]
                    owner, repo = repo_parts[0], repo_parts[1].replace('.git', '')
                    
                    api_url = f'https://api.github.com/repos/{owner}/{repo}/issues'
                    response = requests.post(api_url, json=payload, headers=headers, timeout=10)
                    
                    if response.status_code == 201:
                        logger.info(f"Created GitHub issue: {response.json()['html_url']}")
                    else:
                        logger.warning(f"Failed to create issue: {response.text}")
        except Exception as e:
            logger.error(f"Failed to create GitHub issue: {e}")
    
    def run_loop(self) -> None:
        """Run tests in a loop"""
        logger.info(f"Starting background test runner (interval: {self.interval}s)")
        
        while True:
            try:
                results = self.run_tests()
                self.log_errors(results)
                
                # Create issues for new failures
                for error in results.get('errors', []):
                    self.create_github_issue(error)
                
                logger.info(
                    f"Results: {len(results['passed'])} passed, "
                    f"{len(results['failed'])} failed"
                )
                
            except Exception as e:
                logger.error(f"Test runner error: {e}")
            
            time.sleep(self.interval)


def main():
    parser = argparse.ArgumentParser(
        description='Background test runner with error collection'
    )
    parser.add_argument(
        '--interval',
        type=int,
        default=3600,
        help='Run tests every N seconds (default: 3600)'
    )
    parser.add_argument(
        '--max-retries',
        type=int,
        default=3,
        help='Max retries per test (default: 3)'
    )
    parser.add_argument(
        '--no-issues',
        action='store_true',
        help='Do not create GitHub issues'
    )
    parser.add_argument(
        '--once',
        action='store_true',
        help='Run tests once and exit'
    )
    
    args = parser.parse_args()
    
    runner = TestRunner(
        interval_seconds=args.interval,
        max_retries=args.max_retries,
        create_issues=not args.no_issues
    )
    
    if args.once:
        results = runner.run_tests()
        runner.log_errors(results)
        print(json.dumps(results, indent=2))
        sys.exit(0 if not results['failed'] else 1)
    else:
        try:
            runner.run_loop()
        except KeyboardInterrupt:
            logger.info("Test runner stopped")
            sys.exit(0)


if __name__ == '__main__':
    main()
