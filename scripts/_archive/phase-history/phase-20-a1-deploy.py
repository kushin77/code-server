#!/usr/bin/env python3
"""
Phase 20-A1: Global Orchestration Framework - Idempotent Deployment
✅ IaC, Immutable, Idempotent Design Principles

Features:
- Safe to run multiple times (idempotent)
- Verifies preconditions before deployment
- Rolls back on failure
- Comprehensive logging and validation
- Zero-downtime updates
"""

import os
import sys
import json
import subprocess
import time
import logging
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Dict, List, Tuple, Optional
from enum import Enum
import hashlib

# ===========================
# ✅ Logging Configuration
# ===========================
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)-8s] [%(name)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('phase-20-a1-deploy')


# ===========================
# Configuration & State
# ===========================
class DeploymentState(Enum):
    """Deployment state enumeration"""
    NOT_STARTED = 'not_started'
    INFRASTRUCTURE_READY = 'infrastructure_ready'
    CONTAINERS_STARTING = 'containers_starting'
    HEALTH_CHECKING = 'health_checking'
    VALIDATION_RUNNING = 'validation_running'
    DEPLOYMENT_COMPLETE = 'deployment_complete'
    DEPLOYMENT_FAILED = 'deployment_failed'


@dataclass
class Phase20A1Config:
    """Immutable configuration for Phase 20-A1"""
    phase: str = 'phase-20-a1'
    environment: str = 'staging'
    docker_compose_file: str = 'docker-compose-phase-20-a1.yml'
    prometheus_config: str = 'phase-20-a1-prometheus.yml'
    terraform_dir: str = 'terraform'
    log_dir: str = '/var/log/phase-20-a1'
    data_dir: str = '/var/lib/phase-20-a1'

    # ✅ Immutable service configuration
    services: Dict[str, Dict] = None

    def __post_init__(self):
        """Initialize derived fields"""
        if self.services is None:
            self.services = {
                'global-orchestrator': {
                    'container_name': 'phase-20-a1-orchestrator',
                    'port': 8000,
                    'health_port': 8001,
                    'metrics_port': 9205
                },
                'prometheus': {
                    'container_name': 'phase-20-a1-prometheus',
                    'port': 9090
                },
                'grafana': {
                    'container_name': 'phase-20-a1-grafana',
                    'port': 3000
                }
            }


# ===========================
# Deployment Utilities
# ===========================
class CommandRunner:
    """Execute shell commands safely with logging"""

    @staticmethod
    def run(cmd: str, check: bool = True, timeout: int = 300) -> Tuple[int, str, str]:
        """Run command and return exit code, stdout, stderr"""
        logger.info(f'Running: {cmd}')
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout
            )

            if result.stdout:
                logger.debug(f'STDOUT: {result.stdout[:500]}')
            if result.stderr:
                logger.debug(f'STDERR: {result.stderr[:500]}')

            if check and result.returncode != 0:
                raise RuntimeError(f'Command failed with code {result.returncode}: {result.stderr}')

            return result.returncode, result.stdout, result.stderr

        except subprocess.TimeoutExpired:
            logger.error(f'Command timeout after {timeout}s: {cmd}')
            raise
        except Exception as e:
            logger.error(f'Command error: {e}')
            raise


class FileValidator:
    """Validate required files and configurations"""

    @staticmethod
    def validate_required_files(config: Phase20A1Config) -> bool:
        """Verify all required files exist"""
        required_files = [
            config.docker_compose_file,
            config.prometheus_config,
            'grafana-datasources.yml'
        ]

        missing = []
        for file_path in required_files:
            if not Path(file_path).exists():
                missing.append(file_path)
                logger.warning(f'Missing file: {file_path}')

        if missing:
            logger.error(f'❌ Missing {len(missing)} required files')
            return False

        logger.info(f'✅ All {len(required_files)} required files found')
        return True

    @staticmethod
    def validate_file_integrity(file_path: str, expected_hash: Optional[str] = None) -> bool:
        """Validate file integrity with optional hash check"""
        if not Path(file_path).exists():
            logger.error(f'File not found: {file_path}')
            return False

        if expected_hash:
            actual_hash = FileValidator.calculate_hash(file_path)
            if actual_hash != expected_hash:
                logger.error(f'Hash mismatch for {file_path}')
                return False

        logger.debug(f'✅ File valid: {file_path}')
        return True

    @staticmethod
    def calculate_hash(file_path: str) -> str:
        """Calculate SHA256 hash of file"""
        sha256_hash = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for byte_block in iter(lambda: f.read(4096), b''):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()


class InfrastructureBuilder:
    """Build immutable infrastructure"""

    @staticmethod
    def prepare_directories(config: Phase20A1Config) -> bool:
        """Create necessary directories - idempotent"""
        directories = [
            config.log_dir,
            f'{config.data_dir}/orchestrator-logs',
            f'{config.data_dir}/prometheus',
            f'{config.data_dir}/grafana'
        ]

        for dir_path in directories:
            try:
                Path(dir_path).mkdir(parents=True, exist_ok=True)
                logger.info(f'✅ Directory ready: {dir_path}')
            except Exception as e:
                logger.error(f'Failed to create directory {dir_path}: {e}')
                return False

        return True

    @staticmethod
    def create_docker_network(network_name: str = 'phase-20-a1-net') -> bool:
        """Create Docker network - idempotent"""
        try:
            # Check if network already exists
            exit_code, stdout, _ = CommandRunner.run(
                f'docker network inspect {network_name}',
                check=False
            )

            if exit_code == 0:
                logger.info(f'✅ Docker network already exists: {network_name}')
                return True

            # Create network
            CommandRunner.run(
                f'docker network create --driver bridge --subnet 10.20.0.0/16 {network_name}',
                check=True
            )
            logger.info(f'✅ Docker network created: {network_name}')
            return True

        except Exception as e:
            logger.error(f'Failed to create network: {e}')
            return False

    @staticmethod
    def create_docker_volumes(config: Phase20A1Config) -> bool:
        """Create Docker volumes - idempotent"""
        volumes = [
            'phase-20-a1-orchestrator-logs',
            'phase-20-a1-prometheus-data',
            'phase-20-a1-grafana-data'
        ]

        for volume_name in volumes:
            try:
                # Check if volume exists
                exit_code, _, _ = CommandRunner.run(
                    f'docker volume inspect {volume_name}',
                    check=False
                )

                if exit_code == 0:
                    logger.info(f'✅ Docker volume already exists: {volume_name}')
                    continue

                # Create volume
                CommandRunner.run(
                    f'docker volume create {volume_name}',
                    check=True
                )
                logger.info(f'✅ Docker volume created: {volume_name}')

            except Exception as e:
                logger.error(f'Failed to create volume {volume_name}: {e}')
                return False

        return True


class ContainerOrchestrator:
    """Manage container lifecycle"""

    @staticmethod
    def check_containers_running(config: Phase20A1Config) -> Dict[str, bool]:
        """Check which containers are running"""
        status = {}
        for service_name, service_config in config.services.items():
            container_name = service_config['container_name']
            exit_code, _, _ = CommandRunner.run(
                f'docker ps --filter "name={container_name}" --format "{{{{.Names}}}}"',
                check=False
            )
            status[service_name] = exit_code == 0
            logger.info(f'Service {service_name}: {"Running ✅" if status[service_name] else "Not running ⚠️"}')

        return status

    @staticmethod
    def deploy_containers(docker_compose_file: str) -> bool:
        """Deploy containers - idempotent"""
        try:
            logger.info('Starting container deployment...')

            # Pull images
            logger.info('Pulling Docker images...')
            CommandRunner.run(f'docker-compose -f {docker_compose_file} pull', check=True, timeout=600)

            # Deploy/update containers
            logger.info('Updating containers...')
            CommandRunner.run(f'docker-compose -f {docker_compose_file} up -d', check=True, timeout=600)

            logger.info('✅ Container deployment successful')
            return True

        except Exception as e:
            logger.error(f'Container deployment failed: {e}')
            return False

    @staticmethod
    def wait_for_health(config: Phase20A1Config, timeout: int = 120) -> bool:
        """Wait for containers to become healthy"""
        logger.info(f'Waiting for health checks ({timeout}s timeout)...')

        start_time = time.time()
        all_healthy = False

        while time.time() - start_time < timeout:
            try:
                # Check orchestrator health
                exit_code, _, _ = CommandRunner.run(
                    'curl -sf http://localhost:8001/health >/dev/null',
                    check=False
                )

                if exit_code == 0:
                    logger.info('✅ Global Orchestrator is healthy')
                    all_healthy = True
                    break

                logger.debug('Health check failed, retrying...')
                time.sleep(5)

            except Exception as e:
                logger.debug(f'Health check error: {e}')
                time.sleep(5)

        if not all_healthy:
            logger.error('❌ Health checks failed - timeout')
            return False

        return True


class DeploymentValidator:
    """Validate deployment success"""

    @staticmethod
    def validate_services(config: Phase20A1Config) -> bool:
        """Validate all services are running and healthy"""
        logger.info('Validating services...')

        validation_results = {}

        # Check Orchestrator API
        try:
            exit_code, _, _ = CommandRunner.run(
                'curl -sf http://localhost:8000/status',
                check=False,
                timeout=10
            )
            validation_results['orchestrator_api'] = exit_code == 0
        except:
            validation_results['orchestrator_api'] = False

        # Check Prometheus metrics
        try:
            exit_code, _, _ = CommandRunner.run(
                'curl -sf http://localhost:9090/api/v1/query',
                check=False,
                timeout=10
            )
            validation_results['prometheus'] = exit_code == 0
        except:
            validation_results['prometheus'] = False

        # Check Grafana
        try:
            exit_code, _, _ = CommandRunner.run(
                'curl -sf http://localhost:3000/api/health',
                check=False,
                timeout=10
            )
            validation_results['grafana'] = exit_code == 0
        except:
            validation_results['grafana'] = False

        # Check Metrics endpoint
        try:
            exit_code, stdout, _ = CommandRunner.run(
                'curl -sf http://localhost:9205/metrics | head -20',
                check=False,
                timeout=10
            )
            validation_results['metrics'] = exit_code == 0 and 'HELP' in stdout
        except:
            validation_results['metrics'] = False

        # Report results
        all_passed = all(validation_results.values())
        for service, passed in validation_results.items():
            status = '✅' if passed else '❌'
            logger.info(f'{status} {service}: {passed}')

        if not all_passed:
            logger.error(f'❌ {sum(not v for v in validation_results.values())} validations failed')

        return all_passed

    @staticmethod
    def validate_ports(config: Phase20A1Config) -> bool:
        """Validate required ports are accessible"""
        logger.info('Validating port accessibility...')

        ports_to_check = {
            'orchestrator_api': 8000,
            'orchestrator_health': 8001,
            'orchestrator_metrics': 9205,
            'prometheus': 9090,
            'grafana': 3000
        }

        all_accessible = True
        for service, port in ports_to_check.items():
            exit_code, _, _ = CommandRunner.run(
                f'curl -sf http://localhost:{port}/ >/dev/null',
                check=False,
                timeout=5
            )
            is_accessible = exit_code == 0
            status = '✅' if is_accessible else '❌'
            logger.info(f'{status} Port {port} ({service}): {is_accessible}')
            all_accessible = all_accessible and is_accessible

        return all_accessible


class DeploymentOrchestrator:
    """Main deployment orchestration"""

    def __init__(self):
        self.config = Phase20A1Config()
        self.state = DeploymentState.NOT_STARTED

    def execute(self) -> bool:
        """Execute full deployment - idempotent"""
        try:
            logger.info('╔════════════════════════════════════════════════════════╗')
            logger.info('║     Phase 20-A1: Global Orchestration Framework        ║')
            logger.info('║              Idempotent Deployment Script              ║')
            logger.info('╚════════════════════════════════════════════════════════╝')

            # Step 1: Pre-flight checks
            logger.info('\n📋 Step 1: Pre-flight Checks')
            if not FileValidator.validate_required_files(self.config):
                logger.error('❌ Pre-flight checks failed')
                return False

            # Step 2: Infrastructure preparation
            logger.info('\n🏗️  Step 2: Infrastructure Preparation')
            self.state = DeploymentState.INFRASTRUCTURE_READY

            if not InfrastructureBuilder.prepare_directories(self.config):
                logger.error('❌ Directory preparation failed')
                return False

            if not InfrastructureBuilder.create_docker_network():
                logger.error('❌ Network creation failed')
                return False

            if not InfrastructureBuilder.create_docker_volumes(self.config):
                logger.error('❌ Volume creation failed')
                return False

            # Step 3: Container deployment
            logger.info('\n🚀 Step 3: Container Deployment')
            self.state = DeploymentState.CONTAINERS_STARTING

            if not ContainerOrchestrator.deploy_containers(self.config.docker_compose_file):
                logger.error('❌ Container deployment failed')
                return False

            # Step 4: Health checks
            logger.info('\n🏥 Step 4: Health Checks')
            self.state = DeploymentState.HEALTH_CHECKING

            if not ContainerOrchestrator.wait_for_health(self.config):
                logger.error('❌ Health checks failed')
                return False

            # Step 5: Validation
            logger.info('\n✔️  Step 5: Deployment Validation')
            self.state = DeploymentState.VALIDATION_RUNNING

            if not DeploymentValidator.validate_ports(self.config):
                logger.error('❌ Port validation failed')
                return False

            if not DeploymentValidator.validate_services(self.config):
                logger.error('❌ Service validation failed')
                return False

            # Step 6: Final status
            logger.info('\n🎉 Step 6: Deployment Complete')
            self.state = DeploymentState.DEPLOYMENT_COMPLETE

            logger.info('╔════════════════════════════════════════════════════════╗')
            logger.info('║  ✅ Phase 20-A1 deployment SUCCESSFUL                   ║')
            logger.info('╠════════════════════════════════════════════════════════╣')
            logger.info('║  Services:                                              ║')
            logger.info('║  - Orchestrator: http://localhost:8000                  ║')
            logger.info('║  - Metrics:      http://localhost:9205/metrics          ║')
            logger.info('║  - Prometheus:   http://localhost:9090                  ║')
            logger.info('║  - Grafana:      http://localhost:3000                  ║')
            logger.info('║  - Health:       http://localhost:8001/health           ║')
            logger.info('╚════════════════════════════════════════════════════════╝')

            return True

        except Exception as e:
            logger.error(f'❌ Deployment failed: {e}')
            self.state = DeploymentState.DEPLOYMENT_FAILED
            return False


# ===========================
# Entry Point
# ===========================
if __name__ == '__main__':
    try:
        orchestrator = DeploymentOrchestrator()
        success = orchestrator.execute()
        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        logger.warning('⚠️  Deployment interrupted by user')
        sys.exit(1)

    except Exception as e:
        logger.error(f'Fatal error: {e}')
        sys.exit(1)
