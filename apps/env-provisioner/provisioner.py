#!/usr/bin/env python3
# @file apps/env-provisioner/provisioner.py
# @module infrastructure/environment
# @description P0-1553 Phase 2: Parse env.yaml and provision development environment
# @governance GOV-002: All environments version-controlled and deterministic

import json
import yaml
import subprocess
import os
import re
from pathlib import Path
from typing import Dict, Any, List
from dataclasses import dataclass
from datetime import datetime, timezone

from jsonschema import Draft7Validator

from log import get_logger

logger = get_logger(__name__)

@dataclass
class ProvisionerConfig:
    """env.yaml configuration"""
    version: str
    runtime: Dict[str, Any]
    services: List[Dict[str, Any]]
    ai: Dict[str, Any] = None
    policies: List[str] = None
    compliance: Dict[str, Any] = None

class EnvProvisioner:
    def __init__(self, env_file: str = "env.yaml"):
        self.env_path = Path(env_file)
        self.repo_root = Path(__file__).resolve().parents[2]
        self.config = self._load_config()
        self.schema_path = self.repo_root / "schemas" / "env-yaml.v1.json"
        self.log_file = self.repo_root / "artifacts" / "provisioner.log"
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
    
    def _load_config(self) -> ProvisionerConfig:
        """Load and validate env.yaml"""
        if not self.env_path.exists():
            raise FileNotFoundError(f"env.yaml not found: {self.env_path}")
        
        with open(self.env_path) as f:
            data = yaml.safe_load(f)
        
        return ProvisionerConfig(**data)

    def _load_schema(self) -> Dict[str, Any]:
        """Load the canonical env.yaml JSON schema."""
        if not self.schema_path.exists():
            raise FileNotFoundError(f"env schema not found: {self.schema_path}")

        with open(self.schema_path) as f:
            return json.load(f)
    
    def _log(self, msg: str, level: str = "INFO"):
        """Log to file"""
        timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        log_msg = f"[{timestamp}] [{level}] {msg}"
        logger.info(log_msg)
        with open(self.log_file, "a") as f:
            f.write(log_msg + "\n")
    
    def _validate_config(self) -> bool:
        """Validate env.yaml schema"""
        self._log("Validating env.yaml schema...")

        try:
            schema = self._load_schema()
            with open(self.env_path) as f:
                raw_config = yaml.safe_load(f)
        except Exception as exc:
            self._log(f"Failed to load env.yaml or schema: {exc}", "ERROR")
            return False

        errors = sorted(Draft7Validator(schema).iter_errors(raw_config), key=lambda error: error.path)
        if errors:
            first_error = errors[0]
            location = "/".join(str(part) for part in first_error.path) or "root"
            self._log(f"Schema validation failed at {location}: {first_error.message}", "ERROR")
            return False
        
        # Check required fields
        if not self.config.version:
            self._log("Missing 'version' field", "ERROR")
            return False
        
        if not self.config.runtime:
            self._log("Missing 'runtime' section", "ERROR")
            return False
        
        if not self.config.services:
            self._log("Missing 'services' section", "ERROR")
            return False
        
        # Validate image digests and immutable pinning
        for service in self.config.services:
            image = service.get("image", "")
            if not image or not re.match(r"^[a-zA-Z0-9./_-]+:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$", image):
                self._log(
                    f"Service {service['name']} must use a digest-pinned image (got: {image})",
                    "ERROR",
                )
                return False
        
        self._log("Configuration validation passed")
        return True
    
    def _generate_docker_compose_override(self) -> str:
        """Generate docker-compose.override.yml from env.yaml"""
        self._log("Generating docker-compose.override.yml...")
        
        override = {
            "version": "3.8",
            "services": {}
        }
        
        for service in self.config.services:
            override["services"][service["name"]] = {
                "image": service["image"],
                "environment": service.get("env", {}),
                "restart": "unless-stopped"
            }
            
            if service.get("persistent"):
                override["services"][service["name"]]["volumes"] = [
                    f"./data/{service['name']}:/data"
                ]
        
        # Write override file
        override_path = self.repo_root / "docker-compose.override.yml"
        with open(override_path, "w") as f:
            yaml.safe_dump(override, f, sort_keys=False)
        
        self._log(f"Docker Compose override generated: {override_path}")
        return str(override_path)
    
    def provision(self, target_env: str = None) -> bool:
        """Provision environment"""
        self._log(f"Provisioning environment: mode={self.config.runtime['mode']}")
        
        if not self._validate_config():
            return False
        
        # Generate docker-compose override
        override_file = self._generate_docker_compose_override()
        
        # Start services
        self._log("Starting Docker Compose services...")
        result = subprocess.run(
            ["docker", "compose", "up", "-d"],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            self._log(f"Docker Compose startup failed: {result.stderr}", "ERROR")
            return False
        
        self._log("Environment provisioned successfully")
        return True

    def validate(self) -> bool:
        """Validate env.yaml without provisioning services"""
        return self._validate_config()
    
    def diff(self, other_env_file: str) -> Dict[str, Any]:
        """Compare two env.yaml files"""
        self._log(f"Computing diff between {self.env_path} and {other_env_file}...")
        
        with open(other_env_file) as f:
            other_config = ProvisionerConfig(**yaml.safe_load(f))
        
        diff = {
            "runtime_changes": {},
            "service_changes": [],
            "ai_changes": {},
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        }
        
        # Compare runtime
        for key in self.config.runtime:
            if self.config.runtime.get(key) != other_config.runtime.get(key):
                diff["runtime_changes"][key] = {
                    "from": self.config.runtime.get(key),
                    "to": other_config.runtime.get(key)
                }
        
        # Compare services
        my_services = {s["name"]: s for s in self.config.services}
        other_services = {s["name"]: s for s in other_config.services}
        
        for name, service in other_services.items():
            if name not in my_services:
                diff["service_changes"].append({"action": "added", "name": name})
            elif my_services[name] != service:
                diff["service_changes"].append({"action": "modified", "name": name})
        
        for name in my_services:
            if name not in other_services:
                diff["service_changes"].append({"action": "removed", "name": name})
        
        self._log(f"Diff complete: {len(diff['service_changes'])} service changes")
        return diff

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        logger.info("Usage: provisioner.py <validate|provision|diff> [env_file]")
        sys.exit(1)
    
    command = sys.argv[1]
    env_file = sys.argv[2] if len(sys.argv) > 2 else "env.yaml"
    
    provisioner = EnvProvisioner(env_file)
    
    if command == "validate":
        success = provisioner.validate()
        sys.exit(0 if success else 1)
    elif command == "provision":
        success = provisioner.provision()
        sys.exit(0 if success else 1)
    elif command == "diff":
        if len(sys.argv) < 4:
            logger.info("Usage: provisioner.py diff <env1.yaml> <env2.yaml>")
            sys.exit(1)
        
        other_env = sys.argv[3]
        diff_result = provisioner.diff(other_env)
        logger.info(json.dumps(diff_result, indent=2))
        sys.exit(0)
    else:
        logger.info(f"Unknown command: {command}")
        sys.exit(1)
