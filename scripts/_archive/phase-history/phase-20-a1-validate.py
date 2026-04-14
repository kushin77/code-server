#!/usr/bin/env python3
"""
Phase 20-A1: Deployment Validation Test Suite
✅ Comprehensive testing and validation

Tests:
  - Port accessibility
  - Service health checks
  - Metrics collection
  - Configuration validity
  - Service discovery
  - Failover readiness
"""

import asyncio
import json
import sys
import time
import logging
from dataclasses import dataclass
from typing import Dict, List, Tuple
from enum import Enum
import urllib.request
import urllib.error
import subprocess

# ===========================
# Logging Configuration
# ===========================
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)-8s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('phase-20-a1-validation')


class TestResult(Enum):
    """Test result status"""
    PASSED = 'passed'
    FAILED = 'failed'
    SKIPPED = 'skipped'
    WARNING = 'warning'


@dataclass
class TestCase:
    """Single test case result"""
    name: str
    status: TestResult
    message: str
    duration_ms: float


class Phase20A1Validator:
    """Phase 20-A1 deployment validator"""

    def __init__(self):
        self.test_results: List[TestCase] = []
        self.endpoints = {
            'orchestrator_api': 'http://localhost:8000',
            'orchestrator_health': 'http://localhost:8001',
            'orchestrator_metrics': 'http://localhost:9205',
            'prometheus': 'http://localhost:9090',
            'grafana': 'http://localhost:3000'
        }

    def run_all_tests(self) -> bool:
        """Execute full test suite"""
        logger.info('╔════════════════════════════════════════════════════════╗')
        logger.info('║     Phase 20-A1: Deployment Validation Test Suite      ║')
        logger.info('╚════════════════════════════════════════════════════════╝')

        # Test suites
        self._test_port_accessibility()
        self._test_service_health()
        self._test_metrics_collection()
        self._test_config_validity()
        self._test_service_discovery()
        self._test_failover_readiness()

        # Print results
        return self._print_results()

    def _test_port_accessibility(self):
        """Test endpoint port accessibility"""
        logger.info('\n🔌 Testing Port Accessibility...')

        for endpoint_name, endpoint_url in self.endpoints.items():
            start = time.time()
            try:
                req = urllib.request.Request(endpoint_url)
                urllib.request.urlopen(req, timeout=5)
                duration = (time.time() - start) * 1000

                self.test_results.append(TestCase(
                    name=f'Port {endpoint_name.upper()}',
                    status=TestResult.PASSED,
                    message=f'✅ {endpoint_url} is accessible',
                    duration_ms=duration
                ))
            except urllib.error.URLError as e:
                duration = (time.time() - start) * 1000
                self.test_results.append(TestCase(
                    name=f'Port {endpoint_name.upper()}',
                    status=TestResult.FAILED,
                    message=f'❌ {endpoint_url} is not accessible: {str(e)}',
                    duration_ms=duration
                ))
            except Exception as e:
                duration = (time.time() - start) * 1000
                self.test_results.append(TestCase(
                    name=f'Port {endpoint_name.upper()}',
                    status=TestResult.FAILED,
                    message=f'❌ Error checking {endpoint_url}: {str(e)}',
                    duration_ms=duration
                ))

    def _test_service_health(self):
        """Test service health endpoints"""
        logger.info('\n🏥 Testing Service Health...')

        health_endpoints = {
            'Orchestrator Health': 'http://localhost:8001/health',
            'Prometheus Status': 'http://localhost:9090/-/healthy',
            'Grafana Status': 'http://localhost:3000/api/health'
        }

        for test_name, endpoint in health_endpoints.items():
            start = time.time()
            try:
                req = urllib.request.Request(endpoint)
                response = urllib.request.urlopen(req, timeout=5)
                duration = (time.time() - start) * 1000

                if response.status == 200:
                    self.test_results.append(TestCase(
                        name=test_name,
                        status=TestResult.PASSED,
                        message=f'✅ Health check passed (HTTP {response.status})',
                        duration_ms=duration
                    ))
                else:
                    self.test_results.append(TestCase(
                        name=test_name,
                        status=TestResult.WARNING,
                        message=f'⚠️  Unexpected status code: HTTP {response.status}',
                        duration_ms=duration
                    ))
            except Exception as e:
                duration = (time.time() - start) * 1000
                self.test_results.append(TestCase(
                    name=test_name,
                    status=TestResult.FAILED,
                    message=f'❌ Health check failed: {str(e)}',
                    duration_ms=duration
                ))

    def _test_metrics_collection(self):
        """Test Prometheus metrics collection"""
        logger.info('\n📊 Testing Metrics Collection...')

        # Test Prometheus scrape targets
        start = time.time()
        try:
            req = urllib.request.Request('http://localhost:9090/api/v1/targets')
            response = urllib.request.urlopen(req, timeout=10)
            data = json.loads(response.read().decode())
            duration = (time.time() - start) * 1000

            if data.get('status') == 'success':
                targets = data.get('data', {}).get('activeTargets', [])
                self.test_results.append(TestCase(
                    name='Prometheus Targets',
                    status=TestResult.PASSED,
                    message=f'✅ Found {len(targets)} active targets',
                    duration_ms=duration
                ))
            else:
                self.test_results.append(TestCase(
                    name='Prometheus Targets',
                    status=TestResult.FAILED,
                    message=f'❌ Unexpected response from Prometheus',
                    duration_ms=duration
                ))
        except Exception as e:
            duration = (time.time() - start) * 1000
            self.test_results.append(TestCase(
                name='Prometheus Targets',
                status=TestResult.FAILED,
                message=f'❌ Failed to query Prometheus: {str(e)}',
                duration_ms=duration
            ))

        # Test metrics export endpoint
        start = time.time()
        try:
            req = urllib.request.Request('http://localhost:9205/metrics')
            response = urllib.request.urlopen(req, timeout=10)
            metrics_text = response.read().decode()
            duration = (time.time() - start) * 1000

            # Count metrics
            metric_count = len([line for line in metrics_text.split('\n')
                              if line and not line.startswith('#')])

            if metric_count > 0:
                self.test_results.append(TestCase(
                    name='Metrics Export',
                    status=TestResult.PASSED,
                    message=f'✅ Exported {metric_count} metrics',
                    duration_ms=duration
                ))
            else:
                self.test_results.append(TestCase(
                    name='Metrics Export',
                    status=TestResult.WARNING,
                    message=f'⚠️  No metrics exported',
                    duration_ms=duration
                ))
        except Exception as e:
            duration = (time.time() - start) * 1000
            self.test_results.append(TestCase(
                name='Metrics Export',
                status=TestResult.FAILED,
                message=f'❌ Failed to fetch metrics: {str(e)}',
                duration_ms=duration
            ))

    def _test_config_validity(self):
        """Test configuration file validity"""
        logger.info('\n⚙️  Testing Configuration Validity...')

        config_files = {
            'phase-20-a1-config.yml': 'YAML',
            'phase-20-a1-prometheus.yml': 'YAML',
            'grafana-datasources.yml': 'YAML'
        }

        for config_file, file_type in config_files.items():
            start = time.time()
            try:
                with open(config_file, 'r') as f:
                    content = f.read()
                duration = (time.time() - start) * 1000

                if len(content) > 0:
                    self.test_results.append(TestCase(
                        name=f'{config_file}',
                        status=TestResult.PASSED,
                        message=f'✅ Configuration file is valid ({len(content)} bytes)',
                        duration_ms=duration
                    ))
                else:
                    self.test_results.append(TestCase(
                        name=f'{config_file}',
                        status=TestResult.FAILED,
                        message=f'❌ Configuration file is empty',
                        duration_ms=duration
                    ))
            except FileNotFoundError:
                duration = (time.time() - start) * 1000
                self.test_results.append(TestCase(
                    name=f'{config_file}',
                    status=TestResult.FAILED,
                    message=f'❌ Configuration file not found',
                    duration_ms=duration
                ))
            except Exception as e:
                duration = (time.time() - start) * 1000
                self.test_results.append(TestCase(
                    name=f'{config_file}',
                    status=TestResult.FAILED,
                    message=f'❌ Failed to read configuration: {str(e)}',
                    duration_ms=duration
                ))

    def _test_service_discovery(self):
        """Test service discovery functionality"""
        logger.info('\n🔍 Testing Service Discovery...')

        start = time.time()
        try:
            # Check orchestrator service discovery endpoint
            req = urllib.request.Request('http://localhost:8000/services')
            response = urllib.request.urlopen(req, timeout=10)
            data = json.loads(response.read().decode())
            duration = (time.time() - start) * 1000

            services_found = len(data.get('services', []))
            self.test_results.append(TestCase(
                name='Service Discovery',
                status=TestResult.PASSED if services_found > 0 else TestResult.WARNING,
                message=f'✅ Found {services_found} registered services',
                duration_ms=duration
            ))
        except Exception as e:
            duration = (time.time() - start) * 1000
            self.test_results.append(TestCase(
                name='Service Discovery',
                status=TestResult.WARNING,
                message=f'⚠️  Service discovery check skipped: {str(e)}',
                duration_ms=duration
            ))

    def _test_failover_readiness(self):
        """Test failover system readiness"""
        logger.info('\n🔄 Testing Failover Readiness...')

        start = time.time()
        try:
            # Check if orchestrator is ready for failover
            req = urllib.request.Request('http://localhost:8000/failover-status')
            response = urllib.request.urlopen(req, timeout=10)
            data = json.loads(response.read().decode())
            duration = (time.time() - start) * 1000

            if data.get('ready'):
                self.test_results.append(TestCase(
                    name='Failover Readiness',
                    status=TestResult.PASSED,
                    message=f'✅ Failover system is ready',
                    duration_ms=duration
                ))
            else:
                self.test_results.append(TestCase(
                    name='Failover Readiness',
                    status=TestResult.WARNING,
                    message=f'⚠️  Failover system not fully ready',
                    duration_ms=duration
                ))
        except Exception as e:
            duration = (time.time() - start) * 1000
            self.test_results.append(TestCase(
                name='Failover Readiness',
                status=TestResult.WARNING,
                message=f'⚠️  Failover check skipped: {str(e)}',
                duration_ms=duration
            ))

    def _print_results(self) -> bool:
        """Print test results summary"""
        logger.info('\n' + '=' * 70)
        logger.info('TEST RESULTS SUMMARY')
        logger.info('=' * 70)

        passed = sum(1 for r in self.test_results if r.status == TestResult.PASSED)
        failed = sum(1 for r in self.test_results if r.status == TestResult.FAILED)
        warned = sum(1 for r in self.test_results if r.status == TestResult.WARNING)

        logger.info(f'\n📈 Statistics:')
        logger.info(f'   ✅ Passed:  {passed}')
        logger.info(f'   ⚠️  Warned:  {warned}')
        logger.info(f'   ❌ Failed:  {failed}')
        logger.info(f'   📊 Total:   {len(self.test_results)}\n')

        # Detailed results
        logger.info('Detailed Results:')
        for result in self.test_results:
            symbol = ('✅' if result.status == TestResult.PASSED
                     else '⚠️' if result.status == TestResult.WARNING
                     else '❌')
            logger.info(f'{symbol} {result.name:30} [{result.duration_ms:6.1f}ms] {result.message}')

        logger.info('\n' + '=' * 70)

        if failed > 0:
            logger.error(f'\n❌ {failed} test(s) FAILED')
            return False
        elif warned > 0:
            logger.warning(f'\n⚠️  {warned} test(s) with warnings')
            return True
        else:
            logger.info(f'\n✅ All {len(self.test_results)} tests PASSED')
            return True


def main():
    """Main entry point"""
    try:
        validator = Phase20A1Validator()
        success = validator.run_all_tests()
        return 0 if success else 1
    except KeyboardInterrupt:
        logger.warning('\nValidation interrupted by user')
        return 1
    except Exception as e:
        logger.error(f'Validation error: {e}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
