#!/usr/bin/env python3
"""
@file apps/env-provisioner/main.py
@module infrastructure/environment-provisioner
@description P3-1553 Phase 3: FastAPI service for environment provisioning
@governance GOV-002: All API operations logged and version-controlled
"""

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List

from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel

from provisioner import EnvProvisioner
import config as _svc_config

from log import get_logger

logger = get_logger(__name__)

# FastAPI app
app = FastAPI(
    title="Environment Provisioner",
    description="P3-1553 Phase 3: Environment configuration and provisioning service",
    version="1.0.0"
)


class ValidationResult(BaseModel):
    """Validation response"""
    valid: bool
    errors: List[str] = []
    timestamp: str


class DiffResult(BaseModel):
    """Environment diff response"""
    runtime_changes: Dict[str, Any] = {}
    service_changes: List[Dict[str, Any]] = []
    timestamp: str


class ProvisionResult(BaseModel):
    """Provisioning result"""
    success: bool
    message: str
    timestamp: str


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "env-provisioner",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }


@app.post("/validate", response_model=ValidationResult)
async def validate_env(file: UploadFile = File(...)):
    """
    Validate an env.yaml file against the schema.
    Returns validation result with any errors found.
    """
    try:
        # Write uploaded file to temp location
        import tempfile
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
            content = await file.read()
            tmp.write(content.decode("utf-8"))
            tmp_path = tmp.name
        
        # Validate
        provisioner = EnvProvisioner(tmp_path)
        valid = provisioner.validate()
        
        # Clean up
        Path(tmp_path).unlink()
        
        return ValidationResult(
            valid=valid,
            errors=[] if valid else ["Validation failed - see logs for details"],
            timestamp=datetime.utcnow().isoformat() + "Z"
        )
    except Exception as e:
        logger.error(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/diff", response_model=DiffResult)
async def diff_env(file_a: UploadFile = File(...), file_b: UploadFile = File(...)):
    """
    Compare two env.yaml files and return differences.
    """
    try:
        import tempfile
        
        # Write both files
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp_a:
            content = await file_a.read()
            tmp_a.write(content.decode("utf-8"))
            tmp_a_path = tmp_a.name
        
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp_b:
            content = await file_b.read()
            tmp_b.write(content.decode("utf-8"))
            tmp_b_path = tmp_b.name
        
        # Compute diff
        provisioner = EnvProvisioner(tmp_a_path)
        diff = provisioner.diff(tmp_b_path)
        
        # Clean up
        Path(tmp_a_path).unlink()
        Path(tmp_b_path).unlink()
        
        return DiffResult(
            runtime_changes=diff.get("runtime_changes", {}),
            service_changes=diff.get("service_changes", []),
            timestamp=diff.get("timestamp", datetime.utcnow().isoformat() + "Z")
        )
    except Exception as e:
        logger.error(f"Diff error: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/provision", response_model=ProvisionResult)
async def provision_env(file: UploadFile = File(...)):
    """
    Provision environment from env.yaml file.
    Generates docker-compose.override.yml and starts services.
    """
    try:
        import tempfile
        
        # Write uploaded file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as tmp:
            content = await file.read()
            tmp.write(content.decode("utf-8"))
            tmp_path = tmp.name
        
        # Provision
        provisioner = EnvProvisioner(tmp_path)
        success = provisioner.provision()
        
        # Clean up
        Path(tmp_path).unlink()
        
        if success:
            logger.info("Environment provisioned successfully")
            return ProvisionResult(
                success=True,
                message="Environment provisioned and services started",
                timestamp=datetime.utcnow().isoformat() + "Z"
            )
        else:
            return ProvisionResult(
                success=False,
                message="Provisioning failed - see logs for details",
                timestamp=datetime.utcnow().isoformat() + "Z"
            )
    except Exception as e:
        logger.error(f"Provisioning error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=_svc_config.HOST, port=_svc_config.PORT)
