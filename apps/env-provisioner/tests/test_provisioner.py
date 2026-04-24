import sys
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
