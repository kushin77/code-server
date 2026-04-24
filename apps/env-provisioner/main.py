#!/usr/bin/env python3
# @file        apps/env-provisioner/main.py
# @module      infrastructure/parity
# @description Parser and provisioner for env.yaml environment specifications

import os
import sys
import yaml
import json
import argparse
from typing import Dict, Any

class EnvProvisioner:
    def __init__(self, schema_path: str):
        self.schema_path = schema_path
        self.config = {}

    def load_env_yaml(self, file_path: str):
        """Load and parse env.yaml file"""
        if not os.path.exists(file_path):
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
