#!/usr/bin/env python3
"""
Apply read-only filesystem configuration to docker-compose.yml

This script safely adds read_only: true and tmpfs: [...] to services
while preserving YAML structure and formatting.

Usage:
    python3 scripts/apply-readonly-config.py [--dry-run] [--backup]

Prerequisites:
    pip3 install pyyaml
"""

import sys
import json
from pathlib import Path
from datetime import datetime

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Install with: pip3 install pyyaml")
    sys.exit(1)

# Service-specific tmpfs mount requirements
TMPFS_CONFIG = {
    "coredns": ["/run", "/tmp"],
    "postgres": ["/var/run/postgresql", "/var/lib/postgresql/tmp"],
    "redis": ["/var/run", "/tmp"],
    "minio": ["/run", "/tmp"],
    "code-server": ["/run", "/tmp", "/home/coder/.local"],
    "oauth2-proxy": ["/run", "/tmp"],
    "caddy": ["/run", "/var/lib/caddy", "/var/cache/caddy"],
    "prometheus": ["/run", "/tmp"],
    "grafana": ["/run", "/var/lib/grafana/plugins", "/var/lib/grafana/png-cache"],
    "alertmanager": ["/run", "/tmp"],
    "jaeger": ["/run", "/tmp"],
    "pgbouncer": ["/var/run", "/tmp"],
    "vault": ["/tmp"],
    "falco": ["/run", "/tmp"],
    "falcosidekick": ["/run", "/tmp"],
    "loki": ["/run", "/tmp", "/var/log/loki"],
    "ollama": ["/run", "/tmp"],
}

class ReadOnlyConfigurator:
    def __init__(self, compose_file="docker-compose.yml", dry_run=False, backup=True):
        self.compose_file = Path(compose_file)
        self.dry_run = dry_run
        self.backup = backup
        self.changes = []

    def load_compose(self):
        """Load docker-compose.yml"""
        if not self.compose_file.exists():
            raise FileNotFoundError(f"{self.compose_file} not found")
        
        with open(self.compose_file, 'r') as f:
            return yaml.safe_load(f)

    def create_backup(self):
        """Create backup of original file"""
        if not self.backup:
            return
        
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_file = self.compose_file.with_stem(f"{self.compose_file.stem}.bak.{timestamp}")
        
        with open(self.compose_file, 'r') as src:
            with open(backup_file, 'w') as dst:
                dst.write(src.read())
        
        print(f"✓ Backup created: {backup_file}")

    def apply_readonly_config(self, compose_data):
        """Apply read_only: true and tmpfs to services"""
        if 'services' not in compose_data:
            print("WARNING: No 'services' section found in docker-compose.yml")
            return compose_data

        services = compose_data['services']
        
        for service_name, config in services.items():
            if not isinstance(config, dict):
                continue
            
            # Skip if already has read_only: true
            if config.get('read_only') is True:
                print(f"  ⊙ {service_name}: already read_only")
                continue
            
            # Check if service should have tmpfs config
            if service_name not in TMPFS_CONFIG:
                print(f"  - {service_name}: no tmpfs config defined (skipped)")
                continue
            
            # Apply read_only and tmpfs
            tmpfs_mounts = TMPFS_CONFIG[service_name]
            config['read_only'] = True
            config['tmpfs'] = tmpfs_mounts
            
            self.changes.append(f"{service_name}")
            print(f"  ✓ {service_name}: read_only=true, tmpfs={tmpfs_mounts}")

        return compose_data

    def save_compose(self, compose_data):
        """Save modified docker-compose.yml"""
        if self.dry_run:
            print(f"\n[DRY-RUN] Would write {len(self.changes)} services to {self.compose_file}")
            return
        
        with open(self.compose_file, 'w') as f:
            yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)
        
        print(f"\n✓ Saved modifications to {self.compose_file}")

    def validate_yaml(self):
        """Validate YAML syntax after changes"""
        try:
            with open(self.compose_file, 'r') as f:
                yaml.safe_load(f)
            print("✓ YAML validation passed")
            return True
        except yaml.YAMLError as e:
            print(f"✗ YAML validation failed: {e}")
            return False

    def run(self):
        """Execute the configuration process"""
        print("═" * 70)
        print("Docker-compose Read-Only Filesystem Configuration")
        print("═" * 70)
        
        if self.dry_run:
            print("[DRY-RUN MODE] No changes will be written\n")
        
        # Load
        print(f"\n1. Loading {self.compose_file}...")
        try:
            compose_data = self.load_compose()
            print(f"   Loaded {len(compose_data.get('services', {}))} services")
        except Exception as e:
            print(f"✗ Failed to load: {e}")
            return False

        # Backup
        if not self.dry_run and self.backup:
            print(f"\n2. Creating backup...")
            self.create_backup()
        else:
            print(f"\n2. Backup: {'disabled' if not self.backup else 'skipped (dry-run)'}")

        # Apply config
        print(f"\n3. Applying read-only configuration...")
        compose_data = self.apply_readonly_config(compose_data)

        # Save
        print(f"\n4. Saving configuration...")
        self.save_compose(compose_data)

        # Validate
        if not self.dry_run:
            print(f"\n5. Validating YAML...")
            if not self.validate_yaml():
                print("✗ Validation failed - check docker-compose.yml")
                return False

        # Summary
        print(f"\n6. Summary")
        print(f"   Services modified: {len(self.changes)}")
        if self.changes:
            for svc in self.changes:
                print(f"     - {svc}")

        print("\n" + "═" * 70)
        if self.dry_run:
            print("DRY-RUN: Run without --dry-run to apply changes")
        else:
            print("✓ Configuration complete - redeploy with: docker-compose up -d")
        print("═" * 70)

        return True

def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Apply read-only filesystem config to docker-compose.yml"
    )
    parser.add_argument("--compose-file", default="docker-compose.yml",
                       help="Path to docker-compose.yml (default: docker-compose.yml)")
    parser.add_argument("--dry-run", action="store_true",
                       help="Simulate changes without writing")
    parser.add_argument("--no-backup", action="store_true",
                       help="Skip creating backup")
    parser.add_argument("--validate-only", action="store_true",
                       help="Only validate YAML syntax")

    args = parser.parse_args()

    configurator = ReadOnlyConfigurator(
        compose_file=args.compose_file,
        dry_run=args.dry_run,
        backup=not args.no_backup
    )

    if args.validate_only:
        if configurator.validate_yaml():
            print("✓ Validation passed")
            return 0
        else:
            return 1

    success = configurator.run()
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
