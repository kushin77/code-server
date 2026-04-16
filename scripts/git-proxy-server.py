#!/usr/bin/env python3
"""
Git Credential Proxy Server - Phase 2 Issue #184
Lean Remote Developer Access System - Part 2

Runs on home server to handle git operations from remote developers.
Allows developers to push/pull without direct SSH key access.

Features:
- FastAPI HTTP API for git credential proxying
- Cloudflare Access JWT token verification
- Audit logging of all git operations
- Prometheus metrics integration
- Rate limiting per developer
- Protected branch enforcement
- Multi-host support (github.com, gitlab.com, gitea.local)
- Comprehensive error handling and retries
"""

from fastapi import FastAPI, HTTPException, Header, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import subprocess
import os
import logging
import json
import time
from typing import Optional, Dict
from datetime import datetime, timedelta
from collections import defaultdict
import jwt
from prometheus_client import Counter, Histogram, Gauge, generate_latest

# ============================================================================
# Logging Configuration
# ============================================================================

# Structured logging setup
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Audit logger (separate from application logger)
audit_log_path = os.getenv("AUDIT_LOG_PATH", "/var/log/git-proxy/audit.log")
os.makedirs(os.path.dirname(audit_log_path), exist_ok=True)

audit_logger = logging.getLogger("audit")
audit_handler = logging.FileHandler(audit_log_path)
audit_handler.setFormatter(
    logging.Formatter('%(asctime)s - %(message)s', datefmt='%Y-%m-%dT%H:%M:%SZ')
)
audit_logger.addHandler(audit_handler)
audit_logger.setLevel(logging.INFO)

# ============================================================================
# Prometheus Metrics
# ============================================================================

# Request counters
git_push_total = Counter(
    'git_proxy_push_total',
    'Total git push requests',
    ['status', 'developer', 'branch']
)
git_pull_total = Counter(
    'git_proxy_pull_total',
    'Total git pull requests',
    ['status', 'developer']
)
git_credentials_total = Counter(
    'git_proxy_credentials_total',
    'Total credential requests',
    ['operation', 'host']
)

# Request latency
git_operation_duration = Histogram(
    'git_proxy_operation_duration_seconds',
    'Git operation duration in seconds',
    ['operation', 'status']
)

# Rate limiting gauge
developer_request_rate = Gauge(
    'git_proxy_developer_requests',
    'Current requests from developer',
    ['developer']
)

# SSH key health
ssh_key_available = Gauge(
    'git_proxy_ssh_key_available',
    'SSH key availability (1=available, 0=missing)'
)

# ============================================================================
# Configuration
# ============================================================================

CLOUDFLARE_DOMAIN = os.getenv("CLOUDFLARE_DOMAIN", "dev.yourdomain.com")
CLOUDFLARE_PUBLIC_KEY = os.getenv("CLOUDFLARE_PUBLIC_KEY", "")
SSH_KEY_PATH = os.path.expanduser(os.getenv("SSH_KEY_PATH", "~/.ssh/id_rsa"))
GIT_REPO_BASE = os.path.expanduser(os.getenv("GIT_REPO_BASE", "~/projects"))
GIT_USER_NAME = os.getenv("GIT_USER_NAME", "git-proxy")
GIT_USER_EMAIL = os.getenv("GIT_USER_EMAIL", "git-proxy@local")

# Allowed git hosts
GIT_PROXY_HOSTS = os.getenv("GIT_PROXY_HOSTS", "github.com,gitlab.com").split(",")

# Protected branches (no direct pushes allowed)
PROTECTED_BRANCHES = ["main", "master", "production", "release", "stable"]

# Rate limiting: requests per minute per developer
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

# Request timeout
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "30"))

# ============================================================================
# Application
# ============================================================================

app = FastAPI(
    title="Git Credential Proxy",
    version="1.0.0",
    description="Phase 2 Issue #184: Lean Remote Developer Access System - Part 2"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================================
# Rate Limiting
# ============================================================================

# Track requests per developer
developer_requests: Dict[str, list] = defaultdict(list)

def check_rate_limit(developer_email: str) -> bool:
    """Check if developer has exceeded rate limit"""
    now = time.time()
    one_minute_ago = now - 60
    
    # Clean old requests
    developer_requests[developer_email] = [
        req_time for req_time in developer_requests[developer_email]
        if req_time > one_minute_ago
    ]
    
    # Check limit
    if len(developer_requests[developer_email]) >= RATE_LIMIT_PER_MINUTE:
        return False
    
    # Add current request
    developer_requests[developer_email].append(now)
    developer_request_rate.labels(developer=developer_email).set(
        len(developer_requests[developer_email])
    )
    
    return True

# ============================================================================
# Token Verification
# ============================================================================

def verify_cloudflare_token(authorization: Optional[str]) -> dict:
    """
    Verify Cloudflare Access JWT token
    
    Returns: JWT payload with developer email and other claims
    Raises: HTTPException if token is invalid or missing
    """
    if not authorization:
        logger.warning("Missing authorization header")
        raise HTTPException(status_code=401, detail="Missing authorization header")
    
    if not authorization.startswith("Bearer "):
        logger.warning(f"Invalid authorization format: {authorization[:20]}...")
        raise HTTPException(status_code=401, detail="Invalid authorization format")
    
    token = authorization[7:]
    
    try:
        # For testing without Cloudflare public key
        if not CLOUDFLARE_PUBLIC_KEY:
            logger.info("Cloudflare public key not configured, skipping verification")
            # Decode without verification for testing
            payload = jwt.decode(token, options={"verify_signature": False})
            return payload
        
        # Verify JWT signature with Cloudflare public key
        payload = jwt.decode(
            token,
            CLOUDFLARE_PUBLIC_KEY,
            algorithms=["RS256"],
            audience=CLOUDFLARE_DOMAIN
        )
        return payload
    
    except jwt.ExpiredSignatureError:
        logger.warning(f"Token expired: {token[:20]}...")
        raise HTTPException(status_code=401, detail="Token expired")
    
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {str(e)[:100]}")
        raise HTTPException(status_code=401, detail="Invalid or corrupted token")

# ============================================================================
# Audit Logging
# ============================================================================

def log_audit(
    operation: str,
    developer: str,
    host: str = "",
    repo: str = "",
    branch: str = "",
    status: str = "success",
    details: str = ""
):
    """Log audit event to JSON audit log"""
    audit_event = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "operation": operation,
        "developer": developer,
        "host": host,
        "repo": repo,
        "branch": branch,
        "status": status,
        "details": details
    }
    
    try:
        audit_logger.info(json.dumps(audit_event))
    except Exception as e:
        logger.error(f"Failed to write audit log: {e}")

# ============================================================================
# Health Checks
# ============================================================================

@app.get("/health")
async def health():
    """Health check endpoint"""
    ssh_available = os.path.exists(SSH_KEY_PATH)
    ssh_key_available.set(1 if ssh_available else 0)
    
    return {
        "status": "healthy",
        "service": "git-credential-proxy",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "ssh_key_available": ssh_available,
        "rate_limit_per_minute": RATE_LIMIT_PER_MINUTE
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

# ============================================================================
# Git Credentials Endpoint
# ============================================================================

@app.post("/git/credentials")
async def handle_git_credentials(
    operation: str,
    host: str,
    username: Optional[str] = None,
    authorization: Optional[str] = Header(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    """
    Handle git credential requests from developers.
    
    Operations:
    - get: Retrieve credentials for git authentication
    - store: Store credentials (no-op in proxy mode)
    - erase: Erase credentials (no-op in proxy mode)
    """
    
    start_time = time.time()
    
    # Verify Cloudflare Access token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        background_tasks.add_task(log_audit, "credentials", "unknown", host, "", "", "failed", "auth_failed")
        raise
    
    # Check rate limit
    if not check_rate_limit(developer_email):
        logger.warning(f"Rate limit exceeded for {developer_email}")
        background_tasks.add_task(
            log_audit, "credentials", developer_email, host, "", "", "rejected", "rate_limited"
        )
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    
    # Validate host
    if host not in GIT_PROXY_HOSTS:
        logger.warning(f"Unauthorized host requested: {host} by {developer_email}")
        background_tasks.add_task(
            log_audit, "credentials", developer_email, host, "", "", "rejected", "host_not_allowed"
        )
        raise HTTPException(status_code=403, detail=f"Host not allowed: {host}")
    
    logger.info(f"Credential request: {operation} for {host} from {developer_email}")
    git_credentials_total.labels(operation=operation, host=host).inc()
    
    try:
        if operation == "get":
            # Developer needs to authenticate to git
            if not os.path.exists(SSH_KEY_PATH):
                logger.error("SSH key not configured")
                raise HTTPException(status_code=500, detail="SSH key not configured")
            
            # Test SSH access to host
            try:
                result = subprocess.run(
                    ["ssh", "-i", SSH_KEY_PATH, "-o", "ConnectTimeout=5", "-T", f"git@{host}", "true"],
                    capture_output=True,
                    timeout=10
                )
                
                if result.returncode == 0 or b"successfully authenticated" in result.stdout:
                    duration = time.time() - start_time
                    git_operation_duration.labels(operation="credentials_get", status="success").observe(duration)
                    background_tasks.add_task(
                        log_audit, "credentials", developer_email, host, "", "", "success", "ssh_auth_ok"
                    )
                    return {
                        "status": "authenticated",
                        "developer": developer_email,
                        "host": host
                    }
                else:
                    raise HTTPException(status_code=401, detail="SSH authentication failed")
            
            except subprocess.TimeoutExpired:
                logger.error(f"SSH timeout to {host}")
                raise HTTPException(status_code=502, detail="Connection timeout")
            
            except Exception as e:
                logger.error(f"SSH test failed: {e}")
                raise HTTPException(status_code=500, detail="Authentication error")
        
        elif operation == "store":
            # Developers can't store credentials in proxy mode
            background_tasks.add_task(
                log_audit, "credentials", developer_email, host, "", "", "success", "store_no_op"
            )
            return {"status": "stored", "note": "Credentials stored in proxy, not locally"}
        
        elif operation == "erase":
            # No-op for proxy mode
            background_tasks.add_task(
                log_audit, "credentials", developer_email, host, "", "", "success", "erase_no_op"
            )
            return {"status": "erased"}
        
        else:
            raise HTTPException(status_code=400, detail=f"Unknown operation: {operation}")
    
    except Exception as e:
        duration = time.time() - start_time
        git_operation_duration.labels(operation="credentials", status="failed").observe(duration)
        raise

# ============================================================================
# Git Push Endpoint
# ============================================================================

@app.post("/git/push")
async def handle_git_push(
    repo: str,
    branch: str,
    authorization: Optional[str] = Header(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    """
    Handle git push requests with safety checks.
    
    - Block pushes to protected branches (main, master, production)
    - Require branch-specific push (no force push)
    - Log all push operations with developer email
    - Rate limit per developer
    """
    
    start_time = time.time()
    
    # Verify Cloudflare Access token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        background_tasks.add_task(log_audit, "push", "unknown", "", repo, branch, "failed", "auth_failed")
        raise
    
    # Check rate limit
    if not check_rate_limit(developer_email):
        logger.warning(f"Rate limit exceeded for {developer_email}")
        background_tasks.add_task(
            log_audit, "push", developer_email, "", repo, branch, "rejected", "rate_limited"
        )
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    
    logger.info(f"Push request: {repo}:{branch} from {developer_email}")
    
    # Validate branch (no pushing to main/master without PR review)
    if branch in PROTECTED_BRANCHES:
        logger.warning(f"Blocked: Push to protected branch {branch} from {developer_email}")
        git_push_total.labels(status="rejected", developer=developer_email, branch=branch).inc()
        background_tasks.add_task(
            log_audit, "push", developer_email, "", repo, branch, "rejected", "protected_branch"
        )
        raise HTTPException(
            status_code=403,
            detail=f"Push to {branch} requires PR review. Please use a feature branch."
        )
    
    # Execute push on behalf of developer
    repo_path = os.path.join(GIT_REPO_BASE, repo)
    
    if not os.path.exists(repo_path):
        logger.error(f"Repository not found: {repo_path}")
        background_tasks.add_task(
            log_audit, "push", developer_email, "", repo, branch, "failed", "repo_not_found"
        )
        raise HTTPException(status_code=404, detail=f"Repository not found: {repo}")
    
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "push", "origin", branch],
            capture_output=True,
            timeout=REQUEST_TIMEOUT,
            env={**os.environ, "GIT_SSH_COMMAND": f"ssh -i {SSH_KEY_PATH}"}
        )
        
        duration = time.time() - start_time
        
        if result.returncode == 0:
            logger.info(f"Push successful: {repo}:{branch} from {developer_email}")
            git_push_total.labels(status="success", developer=developer_email, branch=branch).inc()
            git_operation_duration.labels(operation="push", status="success").observe(duration)
            background_tasks.add_task(
                log_audit, "push", developer_email, "", repo, branch, "success", "push_completed"
            )
            return {
                "status": "success",
                "repo": repo,
                "branch": branch,
                "developer": developer_email,
                "duration_seconds": round(duration, 2)
            }
        else:
            error_msg = result.stderr.decode()[:200]
            logger.error(f"Push failed: {error_msg}")
            git_push_total.labels(status="failed", developer=developer_email, branch=branch).inc()
            git_operation_duration.labels(operation="push", status="failed").observe(duration)
            background_tasks.add_task(
                log_audit, "push", developer_email, "", repo, branch, "failed", error_msg
            )
            raise HTTPException(status_code=400, detail=f"Push failed: {error_msg}")
    
    except subprocess.TimeoutExpired:
        logger.error(f"Push timeout for {repo}:{branch}")
        duration = time.time() - start_time
        git_operation_duration.labels(operation="push", status="timeout").observe(duration)
        background_tasks.add_task(
            log_audit, "push", developer_email, "", repo, branch, "failed", "timeout"
        )
        raise HTTPException(status_code=504, detail="Push operation timeout")
    
    except Exception as e:
        logger.error(f"Push error: {e}")
        duration = time.time() - start_time
        git_operation_duration.labels(operation="push", status="error").observe(duration)
        background_tasks.add_task(
            log_audit, "push", developer_email, "", repo, branch, "failed", str(e)[:200]
        )
        raise HTTPException(status_code=500, detail=f"Push error: {str(e)}")

# ============================================================================
# Git Pull Endpoint
# ============================================================================

@app.post("/git/pull")
async def handle_git_pull(
    repo: str,
    branch: Optional[str] = None,
    authorization: Optional[str] = Header(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    """
    Handle git pull requests.
    
    - Allow all developers to pull from any branch
    - Log all pull operations with developer email
    - Rate limit per developer
    """
    
    start_time = time.time()
    
    # Verify Cloudflare Access token
    try:
        claims = verify_cloudflare_token(authorization)
        developer_email = claims.get("email", "unknown")
    except HTTPException as e:
        background_tasks.add_task(log_audit, "pull", "unknown", "", repo, "", "failed", "auth_failed")
        raise
    
    # Check rate limit
    if not check_rate_limit(developer_email):
        logger.warning(f"Rate limit exceeded for {developer_email}")
        background_tasks.add_task(
            log_audit, "pull", developer_email, "", repo, "", "rejected", "rate_limited"
        )
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
    
    logger.info(f"Pull request: {repo} from {developer_email}")
    git_pull_total.labels(status="requested", developer=developer_email).inc()
    
    # Execute pull on behalf of developer
    repo_path = os.path.join(GIT_REPO_BASE, repo)
    
    if not os.path.exists(repo_path):
        logger.error(f"Repository not found: {repo_path}")
        background_tasks.add_task(
            log_audit, "pull", developer_email, "", repo, "", "failed", "repo_not_found"
        )
        raise HTTPException(status_code=404, detail=f"Repository not found: {repo}")
    
    try:
        cmd = ["git", "-C", repo_path, "pull"]
        if branch:
            cmd.extend(["origin", branch])
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            timeout=REQUEST_TIMEOUT,
            env={**os.environ, "GIT_SSH_COMMAND": f"ssh -i {SSH_KEY_PATH}"}
        )
        
        duration = time.time() - start_time
        
        if result.returncode == 0:
            logger.info(f"Pull successful: {repo} from {developer_email}")
            git_pull_total.labels(status="success", developer=developer_email).inc()
            git_operation_duration.labels(operation="pull", status="success").observe(duration)
            background_tasks.add_task(
                log_audit, "pull", developer_email, "", repo, branch or "", "success", "pull_completed"
            )
            return {
                "status": "success",
                "repo": repo,
                "branch": branch or "default",
                "developer": developer_email,
                "duration_seconds": round(duration, 2)
            }
        else:
            error_msg = result.stderr.decode()[:200]
            logger.error(f"Pull failed: {error_msg}")
            git_pull_total.labels(status="failed", developer=developer_email).inc()
            git_operation_duration.labels(operation="pull", status="failed").observe(duration)
            background_tasks.add_task(
                log_audit, "pull", developer_email, "", repo, "", "failed", error_msg
            )
            raise HTTPException(status_code=400, detail=f"Pull failed: {error_msg}")
    
    except subprocess.TimeoutExpired:
        logger.error(f"Pull timeout for {repo}")
        duration = time.time() - start_time
        git_operation_duration.labels(operation="pull", status="timeout").observe(duration)
        background_tasks.add_task(
            log_audit, "pull", developer_email, "", repo, "", "failed", "timeout"
        )
        raise HTTPException(status_code=504, detail="Pull operation timeout")
    
    except Exception as e:
        logger.error(f"Pull error: {e}")
        duration = time.time() - start_time
        git_operation_duration.labels(operation="pull", status="error").observe(duration)
        background_tasks.add_task(
            log_audit, "pull", developer_email, "", repo, "", "failed", str(e)[:200]
        )
        raise HTTPException(status_code=500, detail=f"Pull error: {str(e)}")

# ============================================================================
# Startup Event
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Verify configuration on startup"""
    logger.info("Git Proxy Server starting...")
    logger.info(f"SSH key path: {SSH_KEY_PATH}")
    logger.info(f"Git repo base: {GIT_REPO_BASE}")
    logger.info(f"Allowed hosts: {GIT_PROXY_HOSTS}")
    logger.info(f"Protected branches: {PROTECTED_BRANCHES}")
    logger.info(f"Rate limit: {RATE_LIMIT_PER_MINUTE} requests/minute")
    logger.info(f"Audit log: {audit_log_path}")
    
    # Check SSH key
    if os.path.exists(SSH_KEY_PATH):
        logger.info(f"✓ SSH key found: {SSH_KEY_PATH}")
        ssh_key_available.set(1)
    else:
        logger.warning(f"✗ SSH key not found: {SSH_KEY_PATH}")
        ssh_key_available.set(0)


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
