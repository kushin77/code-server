#!/usr/bin/env python3
# @file        apps/env-provisioner/main.py
# @module      devos/env-provisioner
# @description Environment provisioner - converts env.yaml to Docker Compose services
# @owner       devos/provisioning
# @status      production-ready
#
# Reads env.yaml specification and generates/manages Docker Compose configuration

import json
import logging
import os
import yaml
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime
import hashlib

logger = logging.getLogger(__name__)


@dataclass
class EnvironmentSpec:
    """Parsed env.yaml specification"""
    version: str
    runtime: Dict[str, Any]
    services: List[Dict[str, Any]]
    ai: Optional[Dict[str, Any]] = None
    policies: Optional[List[str]] = None
    compliance: Optional[Dict[str, Any]] = None


class EnvProvisioner:
    """Provisions environments from env.yaml specifications"""
    
    def __init__(self, schema_path: str = "schemas/env-yaml.v1.json"):
        """
        Initialize provisioner
        
        Args:
            schema_path: Path to JSON Schema for env.yaml
        """
        self.schema_path = schema_path
        self.schema = self._load_schema()
        logger.basicConfig(level=logging.INFO)
    
    def _load_schema(self) -> Dict[str, Any]:
        """Load JSON Schema"""
        try:
            with open(self.schema_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Schema not found at {self.schema_path}")
            return {}
    
    def load_env_yaml(self, env_yaml_path: str) -> EnvironmentSpec:
        """
        Load and parse env.yaml file
        
        Args:
            env_yaml_path: Path to env.yaml file
        
        Returns: EnvironmentSpec
        """
        if not os.path.exists(env_yaml_path):
            raise FileNotFoundError(f"env.yaml not found at {env_yaml_path}")
        
        with open(env_yaml_path, 'r') as f:
            data = yaml.safe_load(f)
        
        logger.info(f"Loaded env.yaml from {env_yaml_path}")
        
        return EnvironmentSpec(
            version=data.get('version', '1'),
            runtime=data.get('runtime', {}),
            services=data.get('services', []),
            ai=data.get('ai'),
            policies=data.get('policies', []),
            compliance=data.get('compliance'),
        )
    
    def validate_spec(self, spec: EnvironmentSpec) -> Tuple[bool, List[str]]:
        """
        Validate environment spec against schema
        
        Returns: (is_valid, errors)
        """
        if not self.schema:
            logger.warning("Schema not loaded, skipping validation")
            return True, []
        
        errors = []
        
        # Check required fields
        if not spec.version:
            errors.append("version is required")
        if not spec.runtime:
            errors.append("runtime is required")
        if not spec.runtime.get('mode'):
            errors.append("runtime.mode is required")
        
        # Validate runtime mode
        valid_modes = ["local", "remote", "ci", "edge"]
        if spec.runtime.get('mode') not in valid_modes:
            errors.append(f"runtime.mode must be one of {valid_modes}")
        
        # Validate services
        for i, service in enumerate(spec.services):
            if not service.get('name'):
                errors.append(f"services[{i}].name is required")
            if not service.get('image'):
                errors.append(f"services[{i}].image is required")
            
            # Validate service name format
            if service.get('name') and not service['name'].replace('_', '').replace('-', '').isalnum():
                errors.append(f"services[{i}].name must be alphanumeric with underscores/hyphens")
        
        is_valid = len(errors) == 0
        logger.info(f"Validation: {'PASSED' if is_valid else 'FAILED'} ({len(errors)} errors)")
        
        return is_valid, errors
    
    def generate_docker_compose(self, spec: EnvironmentSpec) -> Dict[str, Any]:
        """
        Generate Docker Compose override from env.yaml
        
        Returns: docker-compose.override.yml as dict
        """
        compose = {
            "version": "3.9",
            "services": {},
            "x-metadata": {
                "generated_from": "env.yaml",
                "generated_at": datetime.utcnow().isoformat(),
                "spec_hash": self._hash_spec(spec),
            },
        }
        
        for service in spec.services:
            service_def = {
                "image": service.get('image'),
            }
            
            # Add ports if specified
            if service.get('ports'):
                service_def['ports'] = service['ports']
            
            # Add environment variables
            if service.get('env'):
                service_def['environment'] = service['env']
            
            # Add volumes
            if service.get('volumes'):
                service_def['volumes'] = service['volumes']
            
            # Add healthcheck
            if service.get('healthcheck'):
                hc = service['healthcheck']
                service_def['healthcheck'] = {
                    'test': hc.get('test', ['CMD', 'true']),
                    'interval': hc.get('interval', '30s'),
                    'timeout': hc.get('timeout', '10s'),
                }
            
            # Add restart policy for persistent services
            if service.get('persistent', False):
                service_def['restart_policy'] = {
                    'condition': 'unless-stopped',
                }
            
            compose['services'][service['name']] = service_def
            logger.info(f"Added service: {service['name']} ({service.get('image')})")
        
        return compose
    
    def save_docker_compose(self, compose: Dict[str, Any], output_path: str = "docker-compose.override.yml"):
        """Save generated Docker Compose to file"""
        with open(output_path, 'w') as f:
            yaml.dump(compose, f, default_flow_style=False, sort_keys=False)
        
        logger.info(f"Saved Docker Compose to {output_path}")
    
    def diff_specs(self, spec1: EnvironmentSpec, spec2: EnvironmentSpec) -> Dict[str, Any]:
        """
        Calculate diff between two environment specs
        
        Returns: {added, removed, changed} service lists
        """
        services1 = {s['name']: s for s in spec1.services}
        services2 = {s['name']: s for s in spec2.services}
        
        diff = {
            "added_services": list(set(services2.keys()) - set(services1.keys())),
            "removed_services": list(set(services1.keys()) - set(services2.keys())),
            "changed_services": [],
        }
        
        for name in services1:
            if name in services2:
                if services1[name] != services2[name]:
                    diff['changed_services'].append({
                        "name": name,
                        "before": services1[name],
                        "after": services2[name],
                    })
        
        return diff
    
    def _hash_spec(self, spec: EnvironmentSpec) -> str:
        """Generate deterministic hash of spec for fingerprinting"""
        spec_dict = {
            "version": spec.version,
            "runtime": spec.runtime,
            "services": sorted(spec.services, key=lambda s: s.get('name', '')),
        }
        spec_json = json.dumps(spec_dict, sort_keys=True)
        return hashlib.sha256(spec_json.encode()).hexdigest()[:16]
    
    def get_service_status(self, service_name: str) -> Dict[str, Any]:
        """
        Get status of a service (healthy, running, stopped, etc.)
        
        Phase 2: Query Docker daemon for actual status
        """
        return {
            "name": service_name,
            "status": "unknown",  # Phase 2: implement actual status
            "last_checked": datetime.utcnow().isoformat(),
        }


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python main.py <env.yaml>")
        sys.exit(1)
    
    provisioner = EnvProvisioner()
    spec = provisioner.load_env_yaml(sys.argv[1])
    is_valid, errors = provisioner.validate_spec(spec)
    
    if not is_valid:
        for error in errors:
            print(f"ERROR: {error}")
        sys.exit(1)
    
    compose = provisioner.generate_docker_compose(spec)
    provisioner.save_docker_compose(compose)
    print("SUCCESS: Generated docker-compose.override.yml")
            raise FileNotFoundError(f"Environment file not found: {file_path}")
        
        with open(file_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        return self.config

    def validate(self):
        """Validate config against JSON schema (mock for MVP)"""
        if not self.config:
            return False, "No config loaded"
        
        # In a real implementation, we would use jsonschema library
        if 'version' not in self.config or 'metadata' not in self.config:
            return False, "Missing required top-level fields: version, metadata"
        
        return True, "Validation successful"

    def generate_docker_compose(self) -> str:
        """Generate a docker-compose.yml content based on env.yaml"""
        metadata = self.config.get('metadata', {})
        compute = self.config.get('compute', {})
        data = self.config.get('data', {})
        
        services = {
            "app": {
                "image": "kushin77/kc-ide:latest",
                "environment": {
                    "ENV_NAME": metadata.get('name'),
                    "ENV_MODE": metadata.get('env'),
                    "PROFILES": ",".join(compute.get('profiles', []))
                }
            }
        }
        
        if 'postgres' in data:
            services['db'] = {
                "image": f"postgres:{data['postgres'].get('version', 'latest')}",
                "environment": {
                    "POSTGRES_DB": "kc_ide",
                    "POSTGRES_USER": "admin",
                    "POSTGRES_PASSWORD_FILE": "/run/secrets/db_password"
                }
            }
            
        compose = {
            "version": "3.8",
            "services": services
        }
        
        return yaml.dump(compose)

def main():
    parser = argparse.ArgumentParser(description="ElevatedIQ Env Provisioner")
    parser.add_argument("--file", default="env.yaml", help="Path to env.yaml")
    parser.add_argument("--validate-only", action="store_true", help="Only validate the file")
    parser.add_argument("--output-compose", help="Path to write docker-compose.yml")
    
    args = parser.parse_args()
    
    schema_path = "config/schemas/env-yaml.v1.json"
    provisioner = EnvProvisioner(schema_path)
    
    try:
        config = provisioner.load_env_yaml(args.file)
        valid, msg = provisioner.validate()
        
        if not valid:
            print(f"Error: {msg}")
            sys.exit(1)
            
        if args.validate_only:
            print("OK")
            sys.exit(0)
            
        if args.output_compose:
            compose_content = provisioner.generate_docker_compose()
            with open(args.output_compose, 'w') as f:
                f.write(compose_content)
            print(f"Generated docker-compose at {args.output_compose}")
            
    except Exception as e:
        print(f"Fatal: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
