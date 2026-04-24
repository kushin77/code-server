#!/usr/bin/env python3
# @file        apps/env-provisioner/tests/test_provisioner.py
# @module      devos/tests
# @description Unit tests for environment provisioner
# @owner       devos/provisioning
# @status      production-ready

import pytest
import tempfile
import os
import yaml
from pathlib import Path

from main import EnvProvisioner, EnvironmentSpec


@pytest.fixture
def provisioner():
    """Fixture: EnvProvisioner instance"""
    return EnvProvisioner(schema_path="schemas/env-yaml.v1.json")


@pytest.fixture
def sample_env_yaml():
    """Fixture: Sample env.yaml content"""
    return {
        "version": "1",
        "runtime": {
            "mode": "local",
            "resource_limits": {
                "cpu": 4,
                "memory": "8Gi"
            }
        },
        "services": [
            {
                "name": "postgres",
                "image": "postgres:16",
                "persistent": True,
                "env": {
                    "POSTGRES_DB": "appdb",
                    "POSTGRES_USER": "app"
                }
            },
            {
                "name": "redis",
                "image": "redis:7",
                "persistent": True,
                "ports": ["6379:6379"]
            }
        ],
        "ai": {
            "model": "llama3:8b",
            "provider": "ollama",
            "constraints": ["no_external_unless_explicit", "prompt_pii_scan"]
        },
        "policies": [
            "no_prod_without_human",
            "secrets_never_leave_boundary"
        ]
    }


class TestEnvProvisioner:
    """Test environment provisioner"""
    
    def test_load_env_yaml(self, provisioner, sample_env_yaml):
        """Test loading env.yaml"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            yaml.dump(sample_env_yaml, f)
            temp_path = f.name
        
        try:
            spec = provisioner.load_env_yaml(temp_path)
            assert spec.version == "1"
            assert spec.runtime['mode'] == "local"
            assert len(spec.services) == 2
            assert spec.services[0]['name'] == "postgres"
        finally:
            os.unlink(temp_path)
    
    def test_load_nonexistent_file(self, provisioner):
        """Test error on missing file"""
        with pytest.raises(FileNotFoundError):
            provisioner.load_env_yaml("/nonexistent/path/env.yaml")
    
    def test_validate_valid_spec(self, provisioner, sample_env_yaml):
        """Test validation passes for valid spec"""
        spec = EnvironmentSpec(
            version=sample_env_yaml['version'],
            runtime=sample_env_yaml['runtime'],
            services=sample_env_yaml['services'],
            ai=sample_env_yaml.get('ai'),
            policies=sample_env_yaml.get('policies'),
        )
        
        is_valid, errors = provisioner.validate_spec(spec)
        assert is_valid
        assert len(errors) == 0
    
    def test_validate_missing_version(self, provisioner):
        """Test validation fails for missing version"""
        spec = EnvironmentSpec(
            version="",
            runtime={"mode": "local"},
            services=[],
        )
        
        is_valid, errors = provisioner.validate_spec(spec)
        assert not is_valid
        assert any("version" in error for error in errors)
    
    def test_validate_invalid_runtime_mode(self, provisioner):
        """Test validation fails for invalid runtime mode"""
        spec = EnvironmentSpec(
            version="1",
            runtime={"mode": "invalid"},
            services=[],
        )
        
        is_valid, errors = provisioner.validate_spec(spec)
        assert not is_valid
        assert any("runtime.mode" in error for error in errors)
    
    def test_validate_missing_service_name(self, provisioner):
        """Test validation fails for missing service name"""
        spec = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{"image": "postgres:16"}],
        )
        
        is_valid, errors = provisioner.validate_spec(spec)
        assert not is_valid
        assert any("name" in error for error in errors)
    
    def test_generate_docker_compose(self, provisioner, sample_env_yaml):
        """Test Docker Compose generation"""
        spec = EnvironmentSpec(
            version=sample_env_yaml['version'],
            runtime=sample_env_yaml['runtime'],
            services=sample_env_yaml['services'],
        )
        
        compose = provisioner.generate_docker_compose(spec)
        
        assert compose['version'] == "3.9"
        assert 'services' in compose
        assert 'postgres' in compose['services']
        assert 'redis' in compose['services']
        assert compose['services']['postgres']['image'] == "postgres:16"
    
    def test_docker_compose_persistent_service(self, provisioner):
        """Test Docker Compose restart policy for persistent services"""
        spec = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{
                "name": "postgres",
                "image": "postgres:16",
                "persistent": True,
            }],
        )
        
        compose = provisioner.generate_docker_compose(spec)
        postgres_def = compose['services']['postgres']
        
        assert 'restart_policy' in postgres_def
        assert postgres_def['restart_policy']['condition'] == 'unless-stopped'
    
    def test_docker_compose_environment_vars(self, provisioner, sample_env_yaml):
        """Test environment variables in Docker Compose"""
        compose = EnvironmentSpec(
            version=sample_env_yaml['version'],
            runtime=sample_env_yaml['runtime'],
            services=sample_env_yaml['services'],
        )
        
        generated = provisioner.generate_docker_compose(compose)
        postgres_env = generated['services']['postgres']['environment']
        
        assert postgres_env['POSTGRES_DB'] == "appdb"
        assert postgres_env['POSTGRES_USER'] == "app"
    
    def test_diff_specs(self, provisioner):
        """Test calculating diff between specs"""
        spec1 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[
                {"name": "postgres", "image": "postgres:15"},
                {"name": "redis", "image": "redis:7"},
            ]
        )
        
        spec2 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[
                {"name": "postgres", "image": "postgres:16"},  # Changed
                {"name": "mongo", "image": "mongo:6"},  # Added
            ]
        )
        
        diff = provisioner.diff_specs(spec1, spec2)
        
        assert "redis" in diff['removed_services']
        assert "mongo" in diff['added_services']
        assert any(s['name'] == 'postgres' for s in diff['changed_services'])
    
    def test_spec_hash_deterministic(self, provisioner):
        """Test that spec hashing is deterministic"""
        spec1 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{"name": "postgres", "image": "postgres:16"}],
        )
        
        spec2 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{"name": "postgres", "image": "postgres:16"}],
        )
        
        hash1 = provisioner._hash_spec(spec1)
        hash2 = provisioner._hash_spec(spec2)
        
        assert hash1 == hash2
    
    def test_spec_hash_changes_on_diff(self, provisioner):
        """Test that spec hash changes when spec changes"""
        spec1 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{"name": "postgres", "image": "postgres:16"}],
        )
        
        spec2 = EnvironmentSpec(
            version="1",
            runtime={"mode": "local"},
            services=[{"name": "postgres", "image": "postgres:17"}],
        )
        
        hash1 = provisioner._hash_spec(spec1)
        hash2 = provisioner._hash_spec(spec2)
        
        assert hash1 != hash2
    
    def test_save_docker_compose(self, provisioner, sample_env_yaml):
        """Test saving Docker Compose to file"""
        spec = EnvironmentSpec(
            version=sample_env_yaml['version'],
            runtime=sample_env_yaml['runtime'],
            services=sample_env_yaml['services'],
        )
        
        compose = provisioner.generate_docker_compose(spec)
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            temp_path = f.name
        
        try:
            provisioner.save_docker_compose(compose, temp_path)
            assert os.path.exists(temp_path)
            
            with open(temp_path, 'r') as f:
                loaded = yaml.safe_load(f)
            
            assert loaded['version'] == "3.9"
            assert 'postgres' in loaded['services']
        finally:
            os.unlink(temp_path)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
