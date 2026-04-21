# Phase 3 - Role-Based Access Control (RBAC) Enforcement
## Implementation Plan — April 21, 2026

## Objective
Implement role-based access control (RBAC) in JWT tokens and enforce authorization checks across services.

## Phase 3 Components

### Phase 3A - JWT Claims Extension (4-6 hours)
**Goal**: Add 'roles' array to JWT token payload with support for group inheritance

**Tasks**:
1. Extend OIDC issuer to include 'roles' claim in token response
2. Map Google OAuth groups to application roles
3. Support custom role assignments per service account
4. Implement role cache in Redis with TTL

**Files to Create**:
- `backend/src/services/auth/role-manager.ts` - Role assignment and lookup
- `backend/src/services/auth/role-mapper.ts` - Google groups → app roles mapping
- `backend/src/services/auth/tests/role-manager.test.ts` - Unit tests
- `.env.phase-3-template` - Role configuration template

### Phase 3B - Authorization Middleware (6-8 hours)
**Goal**: Implement JWT token validation with role enforcement

**Tasks**:
1. Create `@requireRole()` decorator for Express endpoints
2. Add role validation to JWT middleware
3. Implement role inheritance (admin inherits all)
4. Support role groups (e.g., 'admin:code-server')

**Files to Create**:
- `backend/src/middleware/jwt-rbac.ts` - Role-based access control middleware
- `backend/src/decorators/require-role.ts` - @requireRole() decorator
- `backend/src/services/auth/role-validator.ts` - Role validation logic
- `backend/src/middleware/tests/jwt-rbac.test.ts` - Middleware tests

### Phase 3C - Role Assignment Management (4-6 hours)
**Goal**: Create APIs and database schema for role assignment

**Tasks**:
1. Create `role_assignments` table in PostgreSQL
2. Implement role CRUD operations (list, create, delete)
3. Create management REST API endpoints
4. Add permission checks to management endpoints

**Files to Create**:
- `backend/src/models/role-assignment.ts` - Role assignment model
- `backend/src/services/role-assignment-service.ts` - Business logic
- `backend/src/routes/role-assignments.ts` - REST API endpoints
- `backend/schema/migrations/phase-3-role-assignments-table.sql` - Migration

### Phase 3D - Testing & Verification (4-6 hours)
**Goal**: Comprehensive testing of RBAC implementation

**Tasks**:
1. Write unit tests for role validation
2. Write integration tests for authorization flows
3. Test role inheritance scenarios
4. Test service-to-service JWT authorization
5. E2E tests for admin/user role separation

**Files to Create**:
- `backend/src/services/auth/tests/role-validator.test.ts`
- `backend/src/routes/tests/role-assignments.test.ts`
- `scripts/ci/run-phase-3-rbac-tests.sh`

## Definition of Done

- [ ] JWT token payload includes 'roles' claim
- [ ] Authorization middleware validates roles on protected endpoints
- [ ] @requireRole() decorator working in Express routes
- [ ] Role assignment CRUD API operational
- [ ] PostgreSQL role_assignments table created
- [ ] All unit tests passing (>90% coverage)
- [ ] All integration tests passing
- [ ] E2E tests for authorization flows passing
- [ ] Role inheritance tested and verified
- [ ] Service-to-service JWT with roles tested
- [ ] Production deployment verified

## Effort Estimate

- Phase 3A (JWT Claims): 4-6 hours
- Phase 3B (Authorization): 6-8 hours
- Phase 3C (Role Management): 4-6 hours
- Phase 3D (Testing): 4-6 hours
- **Total: 18-26 hours**

## Rollback Strategy

If any phase fails:
1. All changes remain on feature branch `feat/1030-phase-3-rbac-enforcement`
2. Main branch unaffected (JWT Phase 2 still operational)
3. Revert branch and try again: `git reset --hard origin/main`

## Success Criteria

1. User with 'admin' role can access all endpoints
2. User with 'user' role can only access public endpoints
3. Service account with 'service-admin' role can call admin APIs
4. Role inheritance: admin role includes 'user' permissions
5. All 14 production services remain healthy
6. HTTPS/OAuth still working after deployment

## Next Steps After Phase 3

- Phase 4: Audit Logging (track all role-based access decisions)
- Phase 5: Fine-grained permissions (per-resource access control)
- Phase 6: SAML/OpenID Connect federation for external IdPs
