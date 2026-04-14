# Phase 26: Developer Ecosystem - REST & GraphQL API Specification

**Status**: Production Design - Ready for July 22 Implementation  
**Timeline**: July 22 - August 12, 2026  
**Effort**: 40-50 hours  
**Depends On**: Phase 22-E (Compliance Automation) ✅ Complete  
**Blocks**: Phase 27 (Mobile SDK)  

---

## Executive Summary

Phase 26 is the comprehensive **developer platform unblock** that completes code-server as an enterprise-grade platform. This phase delivers:

1. **REST API** (50+ endpoints across 8 resource categories)
2. **GraphQL API** (complete schema with 15+ types)
3. **Multi-Language SDKs** (Python, TypeScript, Go, Java)
4. **CLI Tools** (50+ commands for on-prem management)
5. **AI Code Generation** (inline autocomplete, refactoring)
6. **Developer Portal** (7-page web UI)

---

## REST API Specification

### API Versioning & Base URL

```
Production: https://api.ide.kushnir.cloud/v1
Staging:    https://staging-api.ide.kushnir.cloud/v1
Local:      http://localhost:8000/v1
```

### Authentication

**OAuth2 / OIDC (Primary)**
```
Authorization: Bearer {access_token}
X-API-Key: {api_key}  # Alternative for machine-to-machine
X-API-Secret: {api_secret}  # Signature for key rotation
```

**Rate Limit Headers**
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 945
X-RateLimit-Reset: 1629849600
```

### Response Format (Standard)

```json
{
  "data": {},
  "meta": {
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total": 245,
      "pages": 13
    },
    "request_id": "req-a1b2c3d4e5f6",
    "timestamp": "2026-07-22T10:30:00Z"
  },
  "errors": null
}
```

### Error Response Format

```json
{
  "errors": [
    {
      "code": "VALIDATION_ERROR",
      "message": "Invalid email format",
      "field": "email",
      "status": 400
    }
  ],
  "meta": {
    "request_id": "req-a1b2c3d4e5f6",
    "timestamp": "2026-07-22T10:30:00Z"
  }
}
```

---

## 1. User Management API

### POST /users
**Create User Account**
```json
Request:
{
  "email": "developer@example.com",
  "name": "John Doe",
  "password": "securePassword123",
  "organization_id": "org-abc123"
}

Response (201):
{
  "data": {
    "id": "user-xyz789",
    "email": "developer@example.com",
    "name": "John Doe",
    "created_at": "2026-07-22T10:30:00Z",
    "verified": false
  }
}
```

### GET /users/{user_id}
**Retrieve User Profile**
```json
Response (200):
{
  "data": {
    "id": "user-xyz789",
    "email": "developer@example.com",
    "name": "John Doe",
    "avatar_url": "https://...",
    "organizations": [
      {
        "id": "org-abc123",
        "name": "Acme Corp",
        "role": "admin"
      }
    ],
    "api_keys_count": 3,
    "created_at": "2026-07-22T10:30:00Z"
  }
}
```

### PATCH /users/{user_id}
**Update User Profile**
```json
Request:
{
  "name": "Jane Doe",
  "avatar_url": "https://..."
}

Response (200): Updated user object
```

### GET /users/me
**Get Current User** (always returns authenticated user)
```json
Response (200): Current user object (same as GET /users/{user_id})
```

### DELETE /users/{user_id}
**Delete User Account**
```
Response (204): No Content
```

---

## 2. Organization Management API

### POST /organizations
**Create Organization**
```json
Request:
{
  "name": "Acme Corp",
  "description": "Enterprise development platform",
  "tier": "enterprise"
}

Response (201):
{
  "data": {
    "id": "org-abc123",
    "name": "Acme Corp",
    "tier": "enterprise",
    "owner_id": "user-xyz789",
    "created_at": "2026-07-22T10:30:00Z",
    "members_count": 1
  }
}
```

### GET /organizations/{org_id}
**Retrieve Organization Details**
```json
Response (200):
{
  "data": {
    "id": "org-abc123",
    "name": "Acme Corp",
    "tier": "enterprise",
    "owner": { "id": "user-xyz789", "email": "owner@acme.com" },
    "members_count": 12,
    "teams_count": 3,
    "api_keys_count": 8,
    "created_at": "2026-07-22T10:30:00Z"
  }
}
```

### PATCH /organizations/{org_id}
**Update Organization**
```json
Request:
{
  "name": "Acme Corp (Updated)",
  "tier": "pro"
}

Response (200): Updated organization
```

### GET /organizations/{org_id}/members
**List Organization Members**
```json
Response (200):
{
  "data": [
    {
      "id": "member-user1",
      "user": { "id": "user-u1", "name": "Alice", "email": "alice@acme.com" },
      "role": "admin",
      "joined_at": "2026-07-22T10:30:00Z"
    }
  ],
  "meta": {
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total": 12
    }
  }
}
```

### POST /organizations/{org_id}/members
**Invite Member to Organization**
```json
Request:
{
  "email": "newmember@acme.com",
  "role": "developer"
}

Response (201):
{
  "data": {
    "id": "member-invite1",
    "email": "newmember@acme.com",
    "role": "developer",
    "status": "pending",
    "invited_at": "2026-07-22T10:30:00Z"
  }
}
```

### DELETE /organizations/{org_id}/members/{member_id}
**Remove Member from Organization**
```
Response (204): No Content
```

---

## 3. API Keys Management

### POST /organizations/{org_id}/api-keys
**Create API Key**
```json
Request:
{
  "name": "CI/CD Pipeline Key",
  "permissions": ["workspaces:read", "workspaces:write"],
  "expires_in_days": 90
}

Response (201):
{
  "data": {
    "id": "key-abc123",
    "name": "CI/CD Pipeline Key",
    "key": "ck_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "secret": "ck_secret_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "permissions": [ "workspaces:read", "workspaces:write" ],
    "created_at": "2026-07-22T10:30:00Z",
    "expires_at": "2026-10-20T10:30:00Z"
  }
}
```

### GET /organizations/{org_id}/api-keys
**List API Keys**
```json
Response (200):
{
  "data": [
    {
      "id": "key-abc123",
      "name": "CI/CD Pipeline Key",
      "key_prefix": "stripe_live_xxxxxxxxxxxxxxxx...",
      "permissions_count": 2,
      "created_at": "2026-07-22T10:30:00Z",
      "last_used_at": "2026-07-24T15:45:00Z"
    }
  ]
}
```

### DELETE /organizations/{org_id}/api-keys/{key_id}
**Revoke API Key**
```
Response (204): No Content
```

---

## 4. Workspaces API

### POST /workspaces
**Create Workspace**
```json
Request:
{
  "name": "Project Alpha",
  "description": "Main development environment",
  "organization_id": "org-abc123",
  "image": "code-server:latest",
  "resources": {
    "cpu": "2000m",
    "memory": "4Gi"
  }
}

Response (201):
{
  "data": {
    "id": "ws-abc123",
    "name": "Project Alpha",
    "url": "https://ws-abc123.ide.kushnir.cloud",
    "status": "provisioning",
    "created_at": "2026-07-22T10:30:00Z"
  }
}
```

### GET /workspaces/{ws_id}
**Retrieve Workspace Details**
```json
Response (200):
{
  "data": {
    "id": "ws-abc123",
    "name": "Project Alpha",
    "url": "https://ws-abc123.ide.kushnir.cloud",
    "status": "running",
    "uptime_hours": 168,
    "last_activity": "2026-07-25T09:15:00Z",
    "resources": {
      "cpu_allocated": "2000m",
      "memory_allocated": "4Gi",
      "cpu_used": "850m",
      "memory_used": "2.1Gi"
    }
  }
}
```

### PATCH /workspaces/{ws_id}
**Update Workspace**
```json
Request:
{
  "resources": {
    "cpu": "4000m",
    "memory": "8Gi"
  }
}

Response (200): Updated workspace
```

### GET /workspaces
**List Workspaces**
```json
Response (200):
{
  "data": [
    { "id": "ws-abc123", "name": "Project Alpha", "status": "running" }
  ],
  "meta": {
    "pagination": {
      "page": 1,
      "per_page": 20,
      "total": 8
    }
  }
}
```

### DELETE /workspaces/{ws_id}
**Delete Workspace**
```
Response (204): No Content
```

### POST /workspaces/{ws_id}/start
**Start Workspace**
```json
Response (200):
{
  "data": {
    "id": "ws-abc123",
    "status": "starting"
  }
}
```

### POST /workspaces/{ws_id}/stop
**Stop Workspace**
```json
Response (200):
{
  "data": {
    "id": "ws-abc123",
    "status": "stopping"
  }
}
```

---

## 5. Files API

### GET /workspaces/{ws_id}/files
**List Files in Workspace**
```json
Query Parameters:
- path: /src (optional, defaults to /)
- recursive: true/false (default: false)

Response (200):
{
  "data": [
    {
      "id": "file-abc123",
      "name": "main.py",
      "path": "/src/main.py",
      "size_bytes": 2048,
      "type": "file",
      "mime_type": "text/x-python",
      "modified_at": "2026-07-25T09:15:00Z"
    }
  ]
}
```

### GET /workspaces/{ws_id}/files/{file_path}
**Read File Content**
```
Query Parameters:
- format: raw | base64 (default: raw)

Response (200):
{
  "data": {
    "path": "/src/main.py",
    "content": "def main():\n    print('Hello')\n",
    "size_bytes": 35,
    "encoding": "utf-8"
  }
}
```

### PUT /workspaces/{ws_id}/files/{file_path}
**Write/Update File**
```json
Request:
{
  "content": "def main():\n    print('Updated')\n",
  "create_if_missing": true
}

Response (200):
{
  "data": {
    "path": "/src/main.py",
    "modified_at": "2026-07-25T09:15:00Z"
  }
}
```

### DELETE /workspaces/{ws_id}/files/{file_path}
**Delete File**
```
Response (204): No Content
```

---

## 6. Usage & Analytics API

### GET /organizations/{org_id}/usage
**Get Organization Usage Statistics**
```json
Query Parameters:
- period: day | month | year (default: month)
- start_date: 2026-07-01 (optional)
- end_date: 2026-07-31 (optional)

Response (200):
{
  "data": {
    "workspace_hours": 1024,
    "cpu_hours": 2048,
    "memory_gb_hours": 4096,
    "network_gb": 512,
    "api_requests": {
      "total": 150000,
      "by_endpoint": {
        "GET /workspaces": 45000,
        "POST /files": 32000
      }
    },
    "cost_estimate": {
      "amount": 456.78,
      "currency": "USD"
    }
  }
}
```

### GET /organizations/{org_id}/analytics
**Get Detailed Analytics**
```json
Query Parameters:
- metric: api_requests | latency | errors | resource_usage (required)
- granularity: hour | day | week | month

Response (200):
{
  "data": [
    {
      "timestamp": "2026-07-25T09:00:00Z",
      "value": 1250,
      "p50": 850,
      "p95": 2100,
      "p99": 2950
    }
  ]
}
```

---

## 7. Webhooks API

### POST /organizations/{org_id}/webhooks
**Register Webhook**
```json
Request:
{
  "url": "https://example.com/webhook",
  "events": [
    "workspace.created",
    "workspace.started",
    "file.modified"
  ],
  "secret": "webhook-secret-key"
}

Response (201):
{
  "data": {
    "id": "webhook-abc123",
    "url": "https://example.com/webhook",
    "events": [ "workspace.created", "workspace.started", "file.modified" ],
    "active": true,
    "created_at": "2026-07-22T10:30:00Z"
  }
}
```

### GET /organizations/{org_id}/webhooks
**List Webhooks**
```json
Response (200):
{
  "data": [
    {
      "id": "webhook-abc123",
      "url": "https://example.com/webhook",
      "events_count": 3,
      "deliveries_total": 450,
      "deliveries_failed": 5,
      "last_delivery_at": "2026-07-25T09:15:00Z"
    }
  ]
}
```

### GET /organizations/{org_id}/webhooks/{webhook_id}/deliveries
**List Webhook Deliveries**
```json
Query Parameters:
- status: success | failed | pending

Response (200):
{
  "data": [
    {
      "id": "delivery-xyz123",
      "event": "workspace.created",
      "status": "success",
      "response_code": 200,
      "delivered_at": "2026-07-25T09:15:00Z",
      "retry_count": 0
    }
  ]
}
```

### DELETE /organizations/{org_id}/webhooks/{webhook_id}
**Delete Webhook**
```
Response (204): No Content
```

---

## 8. Health & Status API

### GET /health
**Service Health Check** (No auth required)
```json
Response (200):
{
  "data": {
    "status": "healthy",
    "uptime_seconds": 3600,
    "version": "1.0.0",
    "services": {
      "auth": "healthy",
      "workspace": "healthy",
      "database": "healthy",
      "cache": "healthy"
    }
  }
}
```

### GET /status
**Detailed System Status**
```json
Response (200):
{
  "data": {
    "api_status": "operational",
    "database_status": "operational",
    "websocket_status": "operational",
    "response_time_ms": 45,
    "timestamp": "2026-07-25T09:15:00Z"
  }
}
```

---

## Error Codes Reference

| Code | HTTP | Description |
|------|------|-------------|
| VALIDATION_ERROR | 400 | Request validation failed |
| AUTHENTICATION_REQUIRED | 401 | Missing or invalid authentication |
| PERMISSION_DENIED | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| CONFLICT | 409 | Resource already exists |
| RATE_LIMITED | 429 | Rate limit exceeded |
| SERVER_ERROR | 500 | Internal server error |
| SERVICE_UNAVAILABLE | 503 | Service temporarily unavailable |

---

## Rate Limiting Policy

| Tier | Requests/Min | Concurrent |
|------|-------------|-----------|
| Free | 100 | 5 |
| Pro | 1,000 | 50 |
| Enterprise | 10,000 | 500 |

---

## Implementation Notes

- ✅ OpenAPI 3.1 specification available at `/api/v1/openapi.json`
- ✅ All endpoints support `application/json` request/response
- ✅ Pagination: max 100 items per page
- ✅ Filtering: `GET /resource?filter[status]=running`
- ✅ Sorting: `GET /resource?sort=-created_at,name`
- ✅ All timestamps in ISO 8601 format with timezone
- ✅ Webhook delivery with HMAC-SHA256 signature in `X-Signature` header

---

**Status**: Specification Complete - Ready for Implementation July 22, 2026  
**Next**: GraphQL Schema Definition  
**Owner**: Infrastructure Team
