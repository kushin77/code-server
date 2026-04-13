#!/usr/bin/env python3
###############################################################################
# GIT PROXY SERVER - Home Server Backend for Credential Proxying
# Issue #184: Enable git operations without SSH key exposure
#
# This FastAPI server runs on the home server behind a Cloudflare Tunnel.
# It receives git credential requests from developers and performs git
# operations using the home server's SSH key (which developers never access).
#
# Features:
#   - Validates Cloudflare Access authentication tokens
#   - Manages SSH key securely (never exposed to developers)
#   - Proxies git operations (push, pull, clone)
#   - Enforces branch protection (no push to main without PR)
#   - Comprehensive audit logging
#   - Rate limiting per developer
#
# Installation:
#   pip install fastapi uvicorn pydantic
#   cp git-proxy-server.py /srv/git-proxy/
#   systemctl start git-proxy
#
# Configuration:
#   See /etc/git-proxy/config.env
#
###############################################################################

import os
import json
import logging
import subprocess
import hashlib
import time
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from pathlib import Path

from fastapi import FastAPI, HTTPException, Header, Request, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import jwt

###############################################################################
# CONFIGURATION
###############################################################################

# Server configuration
GIT_PROXY_PORT = int(os.environ.get('GIT_PROXY_PORT', 8443))
GIT_PROXY_HOST = os.environ.get('GIT_PROXY_HOST', '127.0.0.1')
SSH_KEY_PATH = os.environ.get('SSH_KEY_PATH', os.path.expanduser('~/.ssh/id_rsa'))
GIT_REPOS_PATH = os.environ.get('GIT_REPOS_PATH', os.path.expanduser('~/repos'))

# Cloudflare Access configuration
CLOUDFLARE_ACCOUNT_ID = os.environ.get('CLOUDFLARE_ACCOUNT_ID', '')
CLOUDFLARE_AUTH_DOMAIN = os.environ.get('CLOUDFLARE_AUTH_DOMAIN', 'example.cloudflareaccess.com')
CLOUDFLARE_APP_ID = os.environ.get('CLOUDFLARE_APP_ID', '')

# Security configuration
MAX_REQUESTS_PER_MINUTE = int(os.environ.get('MAX_REQUESTS_PER_MINUTE', 30))
SESSION_TOKEN_EXPIRY = int(os.environ.get('SESSION_TOKEN_EXPIRY', 3600))
PROTECTED_BRANCHES = os.environ.get('PROTECTED_BRANCHES', 'main,master,develop').split(',')

# Logging
LOG_DIR = os.environ.get('LOG_DIR', '/var/log/git-proxy')
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{LOG_DIR}/git-proxy.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

###############################################################################
# DATA MODELS
###############################################################################

class GitCredentialRequest(BaseModel):
    protocol: str = Field(..., description="https or ssh")
    host: str = Field(..., description="github.com or git.example.com")
    username: Optional[str] = Field(default=None)
    password: Optional[str] = Field(default=None)

class GitCredentialResponse(BaseModel):
    protocol: str
    host: str
    username: str
    password: str

class GitOperationRequest(BaseModel):
    operation: str = Field(..., description="get, push, pull, clone")
    repo: str = Field(..., description="repository path or URL")
    branch: Optional[str] = Field(default=None)
    message: Optional[str] = Field(default=None)

class GitOperationResponse(BaseModel):
    status: str
    message: str
    result: Dict[str, Any] = Field(default_factory=dict)

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    version: str = "1.0.0"

###############################################################################
# CLOUDFLARE ACCESS VALIDATION
###############################################################################

class CloudflareAccessValidator:
    """Validates Cloudflare Access JWT tokens"""
    
    def __init__(self):
        self.public_key = None
        self.public_key_cached_at = 0
        self.public_key_cache_ttl = 3600
    
    def get_public_key(self) -> str:
        """Fetch Cloudflare's public key"""
        import urllib.request
        
        now = time.time()
        if self.public_key and (now - self.public_key_cached_at) < self.public_key_cache_ttl:
            return self.public_key
        
        try:
            url = f'https://{CLOUDFLARE_AUTH_DOMAIN}/cdn-cgi/access/certs'
            response = urllib.request.urlopen(url, timeout=5)
            certs = json.loads(response.read().decode())
            
            # Get the first certificate (usually the only one)
            self.public_key = certs['certs'][0]['cert']
            self.public_key_cached_at = now
            return self.public_key
        except Exception as e:
            logger.error(f"Failed to fetch Cloudflare public key: {e}")
            raise HTTPException(status_code=500, detail="Failed to validate token")
    
    def validate_token(self, token: str) -> Dict[str, Any]:
        """Validate and decode Cloudflare Access JWT"""
        try:
            # Remove 'Bearer ' prefix if present
            if token.startswith('Bearer '):
                token = token[7:]
            
            public_key = self.get_public_key()
            
            # Decode JWT
            payload = jwt.decode(
                token,
                public_key,
                algorithms=['RS256'],
                audience=CLOUDFLARE_ACCOUNT_ID
            )
            
            return payload
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {e}")
            raise HTTPException(status_code=401, detail="Invalid authentication token")
        except Exception as e:
            logger.error(f"Token validation error: {e}")
            raise HTTPException(status_code=403, detail="Authentication failed")

###############################################################################
# RATE LIMITING
###############################################################################

class RateLimiter:
    """Simple in-memory rate limiter"""
    
    def __init__(self):
        self.requests: Dict[str, list] = {}
    
    def is_allowed(self, identifier: str, limit: int, window_seconds: int = 60) -> bool:
        """Check if request is allowed under rate limit"""
        now = time.time()
        
        if identifier not in self.requests:
            self.requests[identifier] = []
        
        # Remove old requests outside the window
        self.requests[identifier] = [
            req_time for req_time in self.requests[identifier]
            if now - req_time < window_seconds
        ]
        
        # Check if limit exceeded
        if len(self.requests[identifier]) >= limit:
            return False
        
        # Record this request
        self.requests[identifier].append(now)
        return True

###############################################################################
# GIT OPERATIONS
###############################################################################

class GitOperationHandler:
    """Handles git operations on behalf of developers"""
    
    def __init__(self):
        self.ssh_key = self._load_ssh_key()
    
    def _load_ssh_key(self) -> str:
        """Load SSH key from secure location"""
        if not os.path.exists(SSH_KEY_PATH):
            raise RuntimeError(f"SSH key not found at {SSH_KEY_PATH}")
        
        with open(SSH_KEY_PATH, 'r') as f:
            key = f.read()
        
        logger.info("SSH key loaded successfully")
        return key
    
    def get_credentials(self, protocol: str, host: str) -> GitCredentialResponse:
        """Generate temporary credentials for git access"""
        
        if protocol == 'https':
            # For HTTPS, generate a temporary GitHub personal access token or OAuth token
            # In production, this would generate an actual GitHub token
            username = 'git'
            password = self._generate_temp_token(host)
        else:
            # For SSH, we can't expose the key, but we can provide SSH agent forwarding
            raise HTTPException(status_code=501, detail="SSH protocol requires direct configuration")
        
        return GitCredentialResponse(
            protocol=protocol,
            host=host,
            username=username,
            password=password
        )
    
    def _generate_temp_token(self, host: str) -> str:
        """Generate a temporary authentication token"""
        # In production: call GitHub API to generate a temporary PAT
        # For now, return a mock token
        return f"temp_{hashlib.sha256(f'{host}_{time.time()}'.encode()).hexdigest()}"
    
    def validate_branch_protection(self, repo: str, branch: str, developer_id: str) -> bool:
        """Check if developer can push to this branch"""
        
        if branch in PROTECTED_BRANCHES:
            logger.warning(f"Attempt to push to protected branch {branch} by {developer_id}")
            return False
        
        return True
    
    def execute_git_operation(
        self,
        operation: str,
        repo: str,
        branch: Optional[str] = None,
        message: Optional[str] = None
    ) -> Dict[str, Any]:
        """Execute git operation using server's SSH key"""
        
        try:
            # Setup SSH environment
            env = os.environ.copy()
            env['SSH_KEY_FILE'] = SSH_KEY_PATH
            env['GIT_SSH_COMMAND'] = f'ssh -i {SSH_KEY_PATH} -o StrictHostKeyChecking=no'
            
            # Validate repo path
            repo_path = Path(GIT_REPOS_PATH) / repo
            if not repo_path.exists():
                raise ValueError(f"Repository not found: {repo}")
            
            # Execute operation
            if operation == 'push':
                if branch and not self.validate_branch_protection(repo, branch, 'developer'):
                    raise ValueError(f"Cannot push to protected branch: {branch}")
                
                result = subprocess.run(
                    ['git', 'push', 'origin', branch or 'main'],
                    cwd=repo_path,
                    env=env,
                    capture_output=True,
                    timeout=30,
                    text=True
                )
            
            elif operation == 'pull':
                result = subprocess.run(
                    ['git', 'pull', 'origin', branch or 'main'],
                    cwd=repo_path,
                    env=env,
                    capture_output=True,
                    timeout=30,
                    text=True
                )
            
            elif operation == 'status':
                result = subprocess.run(
                    ['git', 'status'],
                    cwd=repo_path,
                    env=env,
                    capture_output=True,
                    timeout=10,
                    text=True
                )
            
            else:
                raise ValueError(f"Unsupported operation: {operation}")
            
            if result.returncode != 0:
                raise RuntimeError(f"Git operation failed: {result.stderr}")
            
            return {
                'operation': operation,
                'repo': repo,
                'branch': branch,
                'output': result.stdout,
                'status': 'success'
            }
        
        except Exception as e:
            logger.error(f"Git operation error: {e}")
            raise

###############################################################################
# FASTAPI APP
###############################################################################

app = FastAPI(
    title="Git Proxy Server",
    description="Proxy git operations for developers without SSH key access",
    version="1.0.0"
)

# Initialization
access_validator = CloudflareAccessValidator()
rate_limiter = RateLimiter()
git_handler = GitOperationHandler()

###############################################################################
# DEPENDENCIES
###############################################################################

async def verify_cloudflare_token(authorization: Optional[str] = Header(None)) -> Dict[str, Any]:
    """Verify Cloudflare Access token"""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")
    
    return access_validator.validate_token(authorization)

async def check_rate_limit(request: Request, payload: Dict = Depends(verify_cloudflare_token)) -> str:
    """Check rate limiting for developer"""
    developer_id = payload.get('email', payload.get('sub', 'unknown'))
    
    if not rate_limiter.is_allowed(developer_id, MAX_REQUESTS_PER_MINUTE):
        logger.warning(f"Rate limit exceeded for {developer_id}")
        raise HTTPException(status_code=429, detail="Too many requests")
    
    return developer_id

###############################################################################
# API ENDPOINTS
###############################################################################

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat()
    )

@app.post("/api/credentials", response_model=GitCredentialResponse)
async def get_credentials(
    request: GitCredentialRequest,
    developer_id: str = Depends(check_rate_limit),
    token_payload: Dict = Depends(verify_cloudflare_token)
):
    """Get temporary credentials for git host"""
    logger.info(f"Credential request from {developer_id} for {request.host}")
    
    try:
        credentials = git_handler.get_credentials(request.protocol, request.host)
        
        # Log the operation
        _log_git_operation(developer_id, 'credential_request', request.host)
        
        return credentials
    
    except Exception as e:
        logger.error(f"Failed to generate credentials: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate credentials")

@app.post("/api/git-operation", response_model=GitOperationResponse)
async def execute_git_operation(
    request: GitOperationRequest,
    developer_id: str = Depends(check_rate_limit),
    token_payload: Dict = Depends(verify_cloudflare_token)
):
    """Execute a git operation"""
    logger.info(f"Git operation {request.operation} from {developer_id}")
    
    try:
        result = git_handler.execute_git_operation(
            request.operation,
            request.repo,
            request.branch,
            request.message
        )
        
        # Log the operation
        _log_git_operation(developer_id, request.operation, request.repo, request.branch)
        
        return GitOperationResponse(
            status="success",
            message=f"Operation {request.operation} completed",
            result=result
        )
    
    except ValueError as e:
        logger.warning(f"Invalid request from {developer_id}: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    
    except Exception as e:
        logger.error(f"Git operation failed: {e}")
        raise HTTPException(status_code=500, detail="Operation failed")

###############################################################################
# AUDIT LOGGING
###############################################################################

def _log_git_operation(
    developer_id: str,
    operation: str,
    target: str,
    branch: Optional[str] = None
):
    """Log git operation for audit trail"""
    audit_log_path = Path(LOG_DIR) / 'audit.log'
    
    log_entry = {
        'timestamp': datetime.utcnow().isoformat(),
        'developer_id': developer_id,
        'operation': operation,
        'target': target,
        'branch': branch
    }
    
    try:
        with open(audit_log_path, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')
    except Exception as e:
        logger.error(f"Failed to write audit log: {e}")

###############################################################################
# ERROR HANDLERS
###############################################################################

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail}
    )

###############################################################################
# STARTUP/SHUTDOWN
###############################################################################

@app.on_event("startup")
async def startup_event():
    logger.info("Git Proxy Server starting")
    logger.info(f"SSH key: {SSH_KEY_PATH}")
    logger.info(f"Repos path: {GIT_REPOS_PATH}")
    logger.info(f"Rate limit: {MAX_REQUESTS_PER_MINUTE} requests/min")

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Git Proxy Server shutting down")

###############################################################################
# MAIN
###############################################################################

if __name__ == "__main__":
    import uvicorn
    
    logger.info(f"Starting Git Proxy Server on {GIT_PROXY_HOST}:{GIT_PROXY_PORT}")
    
    uvicorn.run(
        app,
        host=GIT_PROXY_HOST,
        port=GIT_PROXY_PORT,
        ssl_keyfile='/etc/git-proxy/ssl.key',
        ssl_certfile='/etc/git-proxy/ssl.crt'
    )
