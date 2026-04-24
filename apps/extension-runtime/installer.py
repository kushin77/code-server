#!/usr/bin/env python3
# @file        apps/extension-runtime/installer.py
# @module      extension-runtime/installer
# @description Extension installation and verification

import logging
import yaml
import hashlib
import json
from pathlib import Path
from typing import Dict, Optional
import subprocess

logger = logging.getLogger(__name__)


class ExtensionInstaller:
    """Handles extension installation and verification."""

    def __init__(self, registry_path: str = "config/extensions.yaml"):
        self.registry_path = Path(registry_path)
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)

    async def install_extension(
        self,
        extension_id: str,
        source_url: str,
        verify_signature: bool = True,
    ) -> bool:
        """
        Install extension from marketplace or URL.
        
        Returns: True if successful
        """
        try:
            logger.info(f"Installing extension: {extension_id} from {source_url}")

            # Download extension package
            package_path = await self._download_extension(extension_id, source_url)
            if not package_path:
                return False

            # Verify signature
            if verify_signature:
                if not await self._verify_signature(package_path, extension_id):
                    logger.error(f"Signature verification failed for {extension_id}")
                    return False

            # Extract and validate manifest
            manifest = await self._extract_manifest(package_path)
            if not manifest:
                return False

            # Verify OPA policies
            if not await self._verify_opa_policy(manifest):
                logger.error(f"OPA policy check failed for {extension_id}")
                return False

            # Register extension
            await self._register_extension(extension_id, manifest, package_path)

            logger.info(f"✅ Extension installed: {extension_id}")
            return True

        except Exception as e:
            logger.error(f"Installation failed: {e}")
            return False

    async def uninstall_extension(self, extension_id: str) -> bool:
        """Uninstall an extension."""
        try:
            logger.info(f"Uninstalling extension: {extension_id}")

            # Load registry
            registry = self._load_registry()
            if extension_id not in registry.get("extensions", {}):
                logger.warning(f"Extension not found: {extension_id}")
                return False

            # Remove from registry
            del registry["extensions"][extension_id]
            self._save_registry(registry)

            logger.info(f"✅ Extension uninstalled: {extension_id}")
            return True

        except Exception as e:
            logger.error(f"Uninstallation failed: {e}")
            return False

    async def list_installed_extensions(self) -> Dict:
        """List all installed extensions."""
        registry = self._load_registry()
        return registry.get("extensions", {})

    async def upgrade_extension(self, extension_id: str) -> bool:
        """Upgrade an extension to latest version."""
        # Placeholder: would fetch from marketplace and upgrade
        logger.info(f"Upgrading extension: {extension_id}")
        return True

    async def _download_extension(self, ext_id: str, url: str) -> Optional[Path]:
        """Download extension package."""
        # Placeholder: real impl would download and extract tarball
        logger.debug(f"Downloading {ext_id} from {url}")
        return Path(f"/tmp/{ext_id}.tar.gz")

    async def _verify_signature(self, package_path: Path, ext_id: str) -> bool:
        """Verify extension package signature."""
        # Placeholder: real impl would verify HMAC/RSA signature
        logger.debug(f"Verifying signature for {package_path}")
        return True

    async def _extract_manifest(self, package_path: Path) -> Optional[Dict]:
        """Extract and parse extension manifest."""
        # Placeholder: real impl would extract from tarball
        manifest = {
            "name": "extension",
            "version": "0.1.0",
            "capabilities": {},
            "permissions": {},
        }
        logger.debug(f"Manifest extracted: {manifest}")
        return manifest

    async def _verify_opa_policy(self, manifest: Dict) -> bool:
        """Verify manifest against OPA extension policy."""
        # Placeholder: real impl would call OPA
        logger.debug(f"OPA verification for: {manifest.get('name')}")
        return True

    async def _register_extension(
        self,
        ext_id: str,
        manifest: Dict,
        package_path: Path,
    ):
        """Register extension in config."""
        registry = self._load_registry()

        if "extensions" not in registry:
            registry["extensions"] = {}

        registry["extensions"][ext_id] = {
            "manifest": manifest,
            "package_path": str(package_path),
            "installed_at": __import__("datetime").datetime.utcnow().isoformat(),
        }

        self._save_registry(registry)

    def _load_registry(self) -> Dict:
        """Load extensions registry."""
        if not self.registry_path.exists():
            return {"extensions": {}}

        try:
            with open(self.registry_path) as f:
                return yaml.safe_load(f) or {"extensions": {}}
        except Exception as e:
            logger.error(f"Failed to load registry: {e}")
            return {"extensions": {}}

    def _save_registry(self, registry: Dict):
        """Save extensions registry."""
        try:
            with open(self.registry_path, "w") as f:
                yaml.dump(registry, f)
        except Exception as e:
            logger.error(f"Failed to save registry: {e}")
