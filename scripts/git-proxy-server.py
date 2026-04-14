#!/usr/bin/env python3
"""
Git Credential Proxy Server
Runs on home server to handle git operations from remote developers.
Allows developers to push/pull without direct SSH key access.
Uses FastAPI for HTTP API, verifies Cloudflare Access tokens.
"""

from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import JSONResponse
import subprocess
import os
import logging
from typing import Optional
import jwt

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Git Credential Proxy")

# Configuration
CLOUDFLARE_DOMAIN = os.getenv("CLOUDFLARE_DOMAIN", "dev.yourdomain.com")
CLOUDFLARE_PUBLIC_KEY = os.getenv("CLOUDFLARE_PUBLIC_KEY", "")
SSH_KEY_PATH = os.path.expanduser("~/.ssh/id_rsa")
GIT_REPO_BASE = os.path.expanduser("~/projects")

# Protected branches (no direct pushes allowed)
PROTECTED_BRANCHES = ["main", "master", "production"]


def verify_cloudflare_token(authorization: Optional[str]) -> dict:
    """Verify Cloudflare Access JWT token"""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")

    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization format")

    token = authorization[7:]

    try:
        # Verify JWT signature with Cloudflare public key
        payload = jwt.decode(
            token,
            CLOUDFLARE_PUBLIC_KEY,
            algorithms=["RS256"],
            audience="dev.yourdomain.com"
        )
        return payload
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired token")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "git-credential-proxy"}


@app.post("/git/credentials")
async def handle_git_credentials(
    operation: str,
    host: str,
    username: Optional[str] = None,
    authorization: Optional[str] = Header(None)
):
    """
    Handle git credential requests from developers.

    Verify session token, then proxy git operations using home server SSH key.
    """

    # Verify Cloudflare Access token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        logger.error(f"Auth failed: {e}")
        raise

    logger.info(f"Credential request: {operation} for {host} from {developer_email}")

    if operation == "get":
        # Developer needs to authenticate to git
        # Verify SSH key exists on this server
        if not os.path.exists(SSH_KEY_PATH):
            raise HTTPException(status_code=500, detail="SSH key not configured")

        # Test SSH access to host
        try:
            result = subprocess.run(
                ["ssh", "-i", SSH_KEY_PATH, "-T", f"git@{host}", "true"],
                capture_output=True,
                timeout=5
            )

            if result.returncode == 0 or b"successfully authenticated" in result.stdout:
                return {
                    "status": "authenticated",
                    "developer": developer_email,
                    "host": host
                }
            else:
                raise HTTPException(status_code=401, detail="SSH authentication failed")
        except subprocess.TimeoutExpired:
            raise HTTPException(status_code=502, detail="Connection timeout")
        except Exception as e:
            logger.error(f"SSH test failed: {e}")
            raise HTTPException(status_code=500, detail="Authentication error")

    elif operation == "store":
        # Developers can't store credentials in proxy mode
        return {"status": "stored", "note": "Credentials stored in proxy, not locally"}

    elif operation == "erase":
        # No-op for proxy mode
        return {"status": "erased"}

    else:
        raise HTTPException(status_code=400, detail=f"Unknown operation: {operation}")


@app.post("/git/push")
async def handle_git_push(
    repo: str,
    branch: str,
    authorization: Optional[str] = Header(None)
):
    """
    Handle git push requests with safety checks.

    - Block pushes to protected branches (main, master, production)
    - Require branch-specific push (no force push)
    - Log all push operations with developer email
    """

    # Verify Cloudflare Access token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        raise

    logger.info(f"Push request: {repo}:{branch} from {developer_email}")

    # Validate branch (no pushing to main/master without PR review)
    if branch in PROTECTED_BRANCHES:
        logger.warning(f"Blocked: Push to protected branch {branch} from {developer_email}")
        raise HTTPException(
            status_code=403,
            detail=f"Push to {branch} requires PR review. Please use a feature branch."
        )

    # Execute push on behalf of developer
    repo_path = os.path.join(GIT_REPO_BASE, repo)

    if not os.path.exists(repo_path):
        raise HTTPException(status_code=404, detail=f"Repository not found: {repo}")

    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "push", "origin", branch],
            capture_output=True,
            timeout=30,
            env={**os.environ, "GIT_SSH_COMMAND": f"ssh -i {SSH_KEY_PATH}"}
        )

        if result.returncode == 0:
            logger.info(f"Push successful: {repo}:{branch} from {developer_email}")
            return {
                "status": "success",
                "repo": repo,
                "branch": branch,
                "developer": developer_email
            }
        else:
            logger.error(f"Push failed: {result.stderr.decode()}")
            raise HTTPException(
                status_code=400,
                detail=f"Push failed: {result.stderr.decode()}"
            )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Push operation timeout")
    except Exception as e:
        logger.error(f"Push error: {e}")
        raise HTTPException(status_code=500, detail=f"Push error: {str(e)}")


@app.post("/git/pull")
async def handle_git_pull(
    repo: str,
    branch: str,
    authorization: Optional[str] = Header(None)
):
    """Handle git pull requests (always allowed)"""

    # Verify token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        raise

    logger.info(f"Pull request: {repo}:{branch} from {developer_email}")

    repo_path = os.path.join(GIT_REPO_BASE, repo)

    if not os.path.exists(repo_path):
        raise HTTPException(status_code=404, detail=f"Repository not found: {repo}")

    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "pull", "origin", branch],
            capture_output=True,
            timeout=30,
            env={**os.environ, "GIT_SSH_COMMAND": f"ssh -i {SSH_KEY_PATH}"}
        )

        if result.returncode == 0:
            logger.info(f"Pull successful: {repo}:{branch}")
            return {"status": "success", "repo": repo, "branch": branch}
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Pull failed: {result.stderr.decode()}"
            )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="Pull operation timeout")
    except Exception as e:
        logger.error(f"Pull error: {e}")
        raise HTTPException(status_code=500, detail=f"Pull error: {str(e)}")


@app.get("/logs/audit")
async def get_audit_logs(
    limit: int = 100,
    authorization: Optional[str] = Header(None)
):
    """Get audit logs (admin only)"""

    # Verify token and check admin role
    try:
        claims = verify_cloudflare_token(authorization)
        if claims.get("role") != "admin":
            raise HTTPException(status_code=403, detail="Admin access required")
    except HTTPException as e:
        raise

    # Return recent audit logs
    audit_file = "/var/log/git-proxy-audit.log"
    try:
        with open(audit_file, "r") as f:
            lines = f.readlines()[-limit:]
        return {"logs": lines}
    except FileNotFoundError:
        return {"logs": []}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001, log_level="info")
