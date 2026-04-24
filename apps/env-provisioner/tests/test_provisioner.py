import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock
import json

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from provisioner import EnvProvisioner


VALID_IMAGE = "postgres:16@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
REDIS_IMAGE = "redis:7@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
OLLAMA_IMAGE = "ollama/ollama:0.1.27@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"


class EnvProvisionerTests(unittest.TestCase):
    def _sample_env(self, image: str = VALID_IMAGE) -> dict:
        return {
            "version": "1",
            "runtime": {
                "mode": "local",
                "fallback": "none",
                "resource_limits": {
                    "cpu": 4,
                    "memory": "8Gi",
                },
            },
            "services": [
                {
                    "name": "postgres",
                    "image": image,
                    "persistent": True,
                    "env": {
                        "POSTGRES_DB": "appdb",
                        "POSTGRES_USER": "app",
                    },
                },
                {
                    "name": "redis",
                    "image": REDIS_IMAGE,
                    "persistent": False,
                },
                {
                    "name": "ollama",
                    "image": OLLAMA_IMAGE,
                    "persistent": True,
                    "env": {
                        "OLLAMA_BASE_URL": "http://ollama:11434",
                    },
                },
            ],
            "ai": {
                "model": "llama3:8b",
                "provider": "ollama",
                "fallback_chain": ["local"],
                "constraints": [
                    "no_external_unless_explicit",
                    "prompt_pii_scan",
                    "log_all_interactions",
                ],
            },
            "policies": [
                "no_prod_without_human",
                "secrets_never_leave_boundary",
                "full_audit_all_actions",
            ],
            "compliance": {
                "frameworks": ["SOC2", "NIST-800-53"],
                "data_classification": "internal",
            },
        }

    def _write_env(self, directory: Path, filename: str, data: dict) -> Path:
        env_path = directory / filename
        env_path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
        return env_path

    def test_validate_accepts_digest_pinned_images(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env())
            provisioner = EnvProvisioner(str(env_path))

            self.assertTrue(provisioner.validate())

    def test_validate_rejects_non_pinned_images(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env(image="postgres:16"))
            provisioner = EnvProvisioner(str(env_path))

            self.assertFalse(provisioner.validate())

    def test_diff_detects_modified_service(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_a = self._write_env(temp_path, "env-a.yaml", self._sample_env())
            env_b_data = self._sample_env()
            env_b_data["services"][0]["image"] = "postgres:16@sha256:" + "d" * 64
            env_b = self._write_env(temp_path, "env-b.yaml", env_b_data)

            provisioner = EnvProvisioner(str(env_a))
            diff = provisioner.diff(str(env_b))

            self.assertTrue(any(change["name"] == "postgres" and change["action"] == "modified" for change in diff["service_changes"]))

    def test_docker_compose_override_generation(self):
        """Test that docker-compose.override.yml is correctly generated"""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env())
            
            provisioner = EnvProvisioner(str(env_path))
            provisioner.repo_root = temp_path
            
            override_file = provisioner._generate_docker_compose_override()
            
            # Verify file was created
            self.assertTrue(Path(override_file).exists())
            
            # Verify content
            with open(override_file) as f:
                override = yaml.safe_load(f)
            
            # Check structure
            self.assertIn("services", override)
            self.assertIn("postgres", override["services"])
            self.assertIn("redis", override["services"])
            self.assertIn("ollama", override["services"])
            
            # Check postgres has persistent volume
            self.assertIn("volumes", override["services"]["postgres"])
            self.assertEqual(
                override["services"]["postgres"]["volumes"],
                ["./data/postgres:/data"]
            )
            
            # Check environment variables
            self.assertEqual(
                override["services"]["postgres"]["environment"]["POSTGRES_DB"],
                "appdb"
            )

    @patch("provisioner.subprocess.run")
    def test_provision_success_with_valid_config(self, mock_run):
        """Test successful provisioning with valid env.yaml"""
        mock_run.return_value = MagicMock(returncode=0, stderr="")
        
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env())
            
            provisioner = EnvProvisioner(str(env_path))
            provisioner.repo_root = temp_path
            
            result = provisioner.provision()
            
            # Verify provision succeeded
            self.assertTrue(result)
            
            # Verify docker compose was called
            mock_run.assert_called_once()
            call_args = mock_run.call_args
            self.assertIn("docker", call_args[0][0])
            self.assertIn("compose", call_args[0][0])
            self.assertIn("up", call_args[0][0])

    @patch("provisioner.subprocess.run")
    def test_provision_fails_with_docker_error(self, mock_run):
        """Test provisioning fails gracefully when docker compose fails"""
        mock_run.return_value = MagicMock(
            returncode=1,
            stderr="Error: docker daemon not running"
        )
        
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env())
            
            provisioner = EnvProvisioner(str(env_path))
            provisioner.repo_root = temp_path
            
            result = provisioner.provision()
            
            # Verify provision failed gracefully
            self.assertFalse(result)

    def test_provision_fails_with_invalid_config(self):
        """Test that provision() returns False for invalid config"""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(
                temp_path,
                "env.yaml",
                self._sample_env(image="postgres:16")  # Missing digest
            )
            
            provisioner = EnvProvisioner(str(env_path))
            result = provisioner.provision()
            
            # Should fail validation
            self.assertFalse(result)

    def test_log_file_creation(self):
        """Test that provisioner creates log files"""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_path = self._write_env(temp_path, "env.yaml", self._sample_env())
            
            provisioner = EnvProvisioner(str(env_path))
            provisioner.repo_root = temp_path
            
            # Create artifacts directory
            artifacts_dir = temp_path / "artifacts"
            artifacts_dir.mkdir(parents=True, exist_ok=True)
            provisioner.log_file = artifacts_dir / "provisioner.log"
            
            # Validate and write logs
            provisioner.validate()
            
            # Check log file exists and has content
            self.assertTrue(provisioner.log_file.exists())
            log_content = provisioner.log_file.read_text()
            self.assertIn("Validating env.yaml schema", log_content)

    def test_diff_detects_runtime_changes(self):
        """Test that diff detects changes in runtime config"""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_a = self._write_env(temp_path, "env-a.yaml", self._sample_env())
            
            env_b_data = self._sample_env()
            env_b_data["runtime"]["mode"] = "hybrid"  # Change mode
            env_b = self._write_env(temp_path, "env-b.yaml", env_b_data)

            provisioner = EnvProvisioner(str(env_a))
            diff = provisioner.diff(str(env_b))

            self.assertIn("mode", diff["runtime_changes"])
            self.assertEqual(diff["runtime_changes"]["mode"]["from"], "local")
            self.assertEqual(diff["runtime_changes"]["mode"]["to"], "hybrid")

    def test_diff_detects_new_services(self):
        """Test that diff detects newly added services"""
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            env_a = self._write_env(temp_path, "env-a.yaml", self._sample_env())
            
            env_b_data = self._sample_env()
            env_b_data["services"].append({
                "name": "minio",
                "image": "minio/minio:latest@sha256:" + "e" * 64,
                "persistent": True,
            })
            env_b = self._write_env(temp_path, "env-b.yaml", env_b_data)

            provisioner = EnvProvisioner(str(env_a))
            diff = provisioner.diff(str(env_b))

            added = [c for c in diff["service_changes"] if c["action"] == "added"]
            self.assertTrue(any(c["name"] == "minio" for c in added))


if __name__ == "__main__":
    unittest.main()
