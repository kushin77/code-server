# API Reference

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Audience**: Developers, Integrators, SREs

## Overview

This document describes the primary HTTP API surface for the code-server-enterprise platform. The API follows REST conventions, uses JSON request and response bodies, and enforces authentication on all non-health endpoints.

## Base URL

- Local development: `http://localhost:3100`
- Production: `https://<deployment-host>`
- Reverse proxy path: `/api`

Example:

```bash
curl -s http://localhost:3100/api/health
```

## Authentication

### Required Headers

Most endpoints require one of the following:

- `Authorization: Bearer <token>`
- Session cookie established via OAuth2 Proxy

### Identity Context

Authenticated requests include user context resolved from OAuth2 Proxy and policy enforcement via OPA.

## Response Conventions

### Success

```json
{
  "status": "ok",
  "data": {}
}
```

### Error

```json
{
  "status": "error",
  "error": {
    "code": "validation_error",
    "message": "Invalid request",
    "details": []
  }
}
```

## Core Endpoints

### Health

`GET /api/health`

Returns overall service health.

#### Response

```json
{
  "status": "ok",
  "service": "api",
  "uptime_seconds": 12345,
  "checks": {
    "database": "ok",
    "cache": "ok",
    "policy": "ok"
  }
}
```

### Readiness

`GET /api/ready`

Returns readiness status for deployment validation.

### Activities

`GET /api/activities`

Returns a paginated activity stream.

#### Query Parameters

- `limit` - Number of items to return
- `cursor` - Pagination cursor
- `actor_id` - Filter by actor
- `type` - Filter by activity type

#### Example

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3100/api/activities?limit=25"
```

### Create Activity

`POST /api/activities`

Creates a new activity record.

#### Request Body

```json
{
  "actor_id": "user-123",
  "action": "file.created",
  "resource": "workspace/file.ts",
  "metadata": {
    "branch": "main"
  }
}
```

### Search

`GET /api/search`

Performs full-text search across indexed content.

#### Query Parameters

- `q` - Search query
- `scope` - Optional scope: `docs`, `code`, `issues`
- `limit` - Result count

### Users

`GET /api/users/me`

Returns the current authenticated user profile.

`GET /api/users/:id`

Returns a user by ID if authorized.

### Deployments

`GET /api/deployments`

Lists deployment events and status records.

`POST /api/deployments/validate`

Runs deployment validation and readiness checks.

## Error Codes

| Code | Meaning | Typical Status |
|------|---------|----------------|
| `unauthorized` | Missing or invalid auth | 401 |
| `forbidden` | Authenticated but blocked by policy | 403 |
| `not_found` | Resource does not exist | 404 |
| `validation_error` | Invalid request payload | 400 |
| `conflict` | Resource already exists | 409 |
| `rate_limited` | Request limit exceeded | 429 |
| `internal_error` | Unexpected server failure | 500 |

## Rate Limiting

- Default limit: 100 requests per minute per user
- Burst allowance: 20 requests
- Exceeded requests return HTTP 429
- Retry headers may include `Retry-After`

## Pagination

List endpoints use cursor-based pagination.

### Response Shape

```json
{
  "data": [],
  "page": {
    "next_cursor": null,
    "has_more": false
  }
}
```

## Webhooks

The platform can emit event notifications for:

- Activity creation
- Deployment status changes
- Policy violations
- SLA breaches

Webhook payloads are JSON and signed with a shared secret.

## OpenAPI Notes

An OpenAPI specification should describe the same surface as this reference document. Keep the schema aligned with:

- request validation rules
- response shapes
- error codes
- pagination metadata
- authentication requirements

## Examples

### Health Check

```bash
curl -s http://localhost:3100/api/health | jq .
```

### List Activities

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3100/api/activities?limit=10&actor_id=user-123"
```

### Validate Deployment

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:3100/api/deployments/validate
```

## Operational Notes

- Health and readiness endpoints are safe for automation.
- All mutating endpoints require authorization.
- Policy decisions should be logged for auditability.
- Any new endpoint must include an entry in this reference and the matching OpenAPI schema.
# API Reference

**Version**: 2.0  
**Last Updated**: April 24, 2026  
**Audience**: Developers, Integrators, Platform Engineers  

## Overview

This reference documents the primary HTTP API exposed by the Paperclip platform. The API follows REST conventions, uses JSON request/response payloads, and requires authenticated access for all non-public endpoints.

## Base URL

- **Production**: `https://kushnir.cloud/api`
- **Staging**: `https://staging.kushnir.cloud/api`
- **Local Development**: `http://localhost:3100/api`

## Authentication

All authenticated endpoints require one of the following:
- OAuth2 session cookie issued by OAuth2-Proxy
- Bearer token for service-to-service requests
- Fine-grained GitHub token for GitHub integration endpoints

### Standard Headers

```http
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json
X-Request-Id: <uuid>
```

## Common Response Format

### Success

```json
{
  "success": true,
  "data": {},
  "meta": {
    "requestId": "uuid",
    "timestamp": "2026-04-24T20:00:00Z"
  }
}
```

### Error

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request payload",
    "details": []
  },
  "meta": {
    "requestId": "uuid",
    "timestamp": "2026-04-24T20:00:00Z"
  }
}
```

## Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET/PUT/PATCH |
| 201 | Created | Resource created successfully |
| 204 | No Content | Successful delete or idempotent update |
| 400 | Bad Request | Invalid input or malformed JSON |
| 401 | Unauthorized | Missing or invalid credentials |
| 403 | Forbidden | Authenticated but not allowed |
| 404 | Not Found | Resource does not exist |
| 409 | Conflict | Duplicate resource or version conflict |
| 422 | Unprocessable Entity | Validation failed |
| 429 | Too Many Requests | Rate limiting exceeded |
| 500 | Internal Server Error | Unexpected server failure |

## Core Endpoints

### Health

#### `GET /health`
Returns the service health status.

**Response**
```json
{
  "status": "ok",
  "uptime": 123456,
  "version": "2.0.0",
  "services": {
    "database": "ok",
    "cache": "ok",
    "queue": "ok"
  }
}
```

**Notes**
- Public endpoint
- Used by load balancers and deployment checks

#### `GET /ready`
Returns readiness status for Kubernetes or external probes.

**Response**
```json
{
  "status": "ready",
  "checks": {
    "db": true,
    "cache": true,
    "migrations": true
  }
}
```

### Activity Feed

#### `GET /api/activities`
Lists recent activity events.

**Query Parameters**
- `limit` - maximum number of items, default 20, max 100
- `cursor` - pagination cursor
- `userId` - filter by user
- `type` - filter by activity type

**Example**
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://kushnir.cloud/api/activities?limit=10"
```

**Response**
```json
{
  "success": true,
  "data": [
    {
      "id": "act_123",
      "userId": "usr_456",
      "type": "file.created",
      "resource": "file_789",
      "timestamp": "2026-04-24T19:00:00Z"
    }
  ],
  "meta": {
    "nextCursor": "eyJpZCI6IjEyMyJ9"
  }
}
```

#### `POST /api/activities`
Creates a new activity record.

**Request Body**
```json
{
  "userId": "usr_456",
  "type": "file.created",
  "resource": "file_789",
  "details": {
    "path": "src/index.ts"
  }
}
```

**Validation Rules**
- `userId` is required
- `type` must match a known event type
- `resource` must reference an existing entity

### Sessions

#### `GET /api/sessions`
Lists active sessions for the authenticated user.

**Response**
```json
{
  "success": true,
  "data": [
    {
      "id": "sess_123",
      "userId": "usr_456",
      "state": "active",
      "startedAt": "2026-04-24T18:45:00Z"
    }
  ]
}
```

#### `POST /api/sessions`
Creates a new session.

**Request Body**
```json
{
  "projectId": "proj_123",
  "browser": true,
  "workspace": "main"
}
```

#### `DELETE /api/sessions/{sessionId}`
Terminates a session.

**Path Parameters**
- `sessionId` - session identifier

**Response**
- `204 No Content` on success

### Users

#### `GET /api/users/me`
Returns the current authenticated user profile.

**Response**
```json
{
  "success": true,
  "data": {
    "id": "usr_456",
    "email": "user@example.com",
    "name": "Test User",
    "roles": ["collaborator"]
  }
}
```

#### `PATCH /api/users/me`
Updates the current user profile.

**Request Body**
```json
{
  "name": "Updated Name",
  "timezone": "UTC"
}
```

### Projects

#### `GET /api/projects`
Lists projects visible to the current user.

**Query Parameters**
- `q` - search term
- `limit` - pagination limit
- `cursor` - pagination cursor

#### `POST /api/projects`
Creates a new project.

**Request Body**
```json
{
  "name": "New Project",
  "description": "Internal automation workspace",
  "visibility": "private"
}
```

### GitHub Integration

#### `GET /api/integrations/github/status`
Checks the GitHub integration health.

**Response**
```json
{
  "success": true,
  "data": {
    "connected": true,
    "rateLimitRemaining": 4321,
    "tokenType": "fine-grained"
  }
}
```

#### `POST /api/integrations/github/issues`
Creates or links a GitHub issue.

**Request Body**
```json
{
  "title": "Documentation gap: API reference",
  "body": "Missing API reference documentation",
  "labels": ["P2", "docs"]
}
```

### GitLab Integration

#### `GET /api/integrations/gitlab/status`
Checks GitLab mirror status.

#### `POST /api/integrations/gitlab/sync`
Triggers a mirror sync to the GitLab source-control repository.

## Rate Limiting

### Limits
- Authenticated users: 500 requests per 5 minutes
- Anonymous users: 50 requests per 5 minutes
- GitHub webhook endpoints: 1000 requests per 5 minutes

### Headers
```http
X-RateLimit-Limit: 500
X-RateLimit-Remaining: 422
X-RateLimit-Reset: 1713993600
```

## Webhooks

### Supported Events
- `activity.created`
- `session.started`
- `session.ended`
- `issue.created`
- `issue.closed`
- `deployment.completed`

### Webhook Payload
```json
{
  "event": "activity.created",
  "id": "evt_123",
  "timestamp": "2026-04-24T20:00:00Z",
  "data": {}
}
```

## Error Codes

| Code | Description |
|------|-------------|
| AUTH_REQUIRED | Authentication required |
| ACCESS_DENIED | User does not have permission |
| VALIDATION_ERROR | Request failed validation |
| NOT_FOUND | Resource not found |
| CONFLICT | Resource already exists |
| RATE_LIMITED | Request rate limit exceeded |
| SERVICE_UNAVAILABLE | Dependent service unavailable |

## SDK Usage

### JavaScript Example
```javascript
const response = await fetch('https://kushnir.cloud/api/activities', {
  headers: {
    Authorization: `Bearer ${token}`,
    Accept: 'application/json'
  }
});

const payload = await response.json();
```

### cURL Example
```bash
curl -X POST https://kushnir.cloud/api/projects \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo Project","visibility":"private"}'
```

## Versioning

The API is versioned by path and supports backward-compatible evolution.
- Current stable: `/api`
- Deprecated fields are announced one release ahead
- Breaking changes require a major version bump and migration guide

## Related Documentation

- [Architecture Overview](../architecture/OVERVIEW.md)
- [Deployment Runbook](../operations/DEPLOYMENT-RUNBOOK.md)
- [Test Plan](../testing/TEST-PLAN.md)
- [Security Guide](../security/SECURITY-GUIDE.md)
