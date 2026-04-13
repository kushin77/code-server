# API Integration Guide - RBAC Frontend

**Version**: 1.0.0  
**Status**: Phase 3A  
**Date**: 2026-04-12

---

## Quick Reference

### API Client Usage

```typescript
// Import the singleton API client
import { rbacAPI } from '@/api/rbac-client'

// Use in hooks
const users = await rbacAPI.getUsers()
const user = await rbacAPI.createUser({ email, fullName })
```

### Authentication Flow

```typescript
import { useLogin } from '@/hooks'

const { login, verifyMFA, isLoading, error } = useLogin()

// Step 1: Login
await login({ email, password, org_slug })

// Step 2: If MFA required
await verifyMFA(mfaToken, totpCode)

// Result: Token stored in localStorage + useAuthStore
```

---

## 1. RBACAPIClient Class

### Overview

Singleton Axios instance with:
- Auto JWT token injection
- Error handling
- Response transformation
- 20+ typed methods

### Location

```
frontend/src/api/rbac-client.ts
```

### Constructor

```typescript
class RBACAPIClient {
  private axiosInstance: AxiosInstance
  
  constructor(baseURL: string = 'http://localhost:3001') {
    this.axiosInstance = axios.create({
      baseURL,
      headers: {
        'Content-Type': 'application/json',
      },
    })
    
    // Add interceptors
    this.setupInterceptors()
  }
  
  private setupInterceptors() {
    // Request: Add JWT token
    // Response: Handle errors
  }
}

// Export singleton
export const rbacAPI = new RBACAPIClient()
```

---

## 2. API Methods

### Authentication

#### `login(request: LoginRequest): Promise<LoginResponse>`

Authenticate user with email/password.

**Request**:
```typescript
interface LoginRequest {
  email: string
  password: string
  org_slug: string
}
```

**Response**:
```typescript
interface LoginResponse {
  token: string
  user: User
  org: Organization
  requiresMfa?: boolean
  mfaToken?: string
}
```

**Example**:
```typescript
const response = await rbacAPI.login({
  email: 'admin@example.com',
  password: 'secure-password',
  org_slug: 'acme-corp',
})

if (response.requiresMfa) {
  // Show TOTP input
  const mfaResponse = await rbacAPI.verifyMFA(response.mfaToken, '123456')
  // Store mfaResponse.token
} else {
  // Store response.token
}
```

#### `verifyMFA(mfaToken: string, totpCode: string): Promise<MFAVerifyResponse>`

Verify TOTP code from authenticator app.

**Request**:
```typescript
interface MFAVerifyRequest {
  mfaToken: string  // From login response
  totpCode: string  // 6-digit code
}
```

**Response**:
```typescript
interface MFAVerifyResponse {
  token: string
  user: User
  org: Organization
}
```

**Example**:
```typescript
const response = await rbacAPI.verifyMFA(mfaToken, '123456')
localStorage.setItem('auth_token', response.token)
useAuthStore.setState({ token: response.token, user: response.user })
```

#### `setupMFA(): Promise<MFASetupResponse>`

Generate QR code and secret for TOTP setup.

**Response**:
```typescript
interface MFASetupResponse {
  secret: string
  qrCode: string  // Data URL
  backupCodes: string[]
}
```

**Example**:
```typescript
const { qrCode, secret, backupCodes } = await rbacAPI.setupMFA()
// Display QR code in UI
// Store secret locally for verification
```

#### `confirmMFA(secret: string, totpCode: string): Promise<{ success: boolean }>`

Confirm MFA setup with TOTP verification.

**Request**:
```typescript
interface MFAConfirmRequest {
  secret: string      // From setupMFA
  totpCode: string    // 6-digit code
}
```

**Response**:
```typescript
{ success: boolean }
```

**Example**:
```typescript
const { success } = await rbacAPI.confirmMFA(secret, '123456')
if (success) {
  toast.success('MFA enabled')
  setMFAEnabled(true)
}
```

#### `logout(): Promise<{ success: boolean }>`

Invalidate current session.

**Example**:
```typescript
await rbacAPI.logout()
localStorage.removeItem('auth_token')
useAuthStore.setState({ token: null, user: null })
navigate('/login')
```

---

### User Management

#### `getUsers(filters?: FilterConfig): Promise<{ users: User[]; total: number }>`

List all users with optional pagination/filters.

**Request**:
```typescript
interface FilterConfig {
  page?: number
  limit?: number
  status?: 'active' | 'inactive'
  search?: string
}
```

**Response**:
```typescript
interface UserListResponse {
  users: User[]
  total: number
  page: number
  limit: number
}
```

**Example**:
```typescript
const { users, total } = await rbacAPI.getUsers({
  page: 1,
  limit: 10,
  search: 'john',
})
```

#### `createUser(request: CreateUserRequest): Promise<User>`

Create new user account.

**Request**:
```typescript
interface CreateUserRequest {
  email: string
  fullName: string
  initialRoles?: string[]  // ['admin', 'developer']
}
```

**Response**:
```typescript
interface User {
  id: string
  email: string
  fullName: string
  status: 'active' | 'inactive'
  mfaEnabled: boolean
  roles: UserRole[]
  createdAt: Date
  updatedAt: Date
}
```

**Example**:
```typescript
const user = await rbacAPI.createUser({
  email: 'newuser@example.com',
  fullName: 'John Doe',
  initialRoles: ['developer'],
})
useUserStore.getState().addUser(user)
```

#### `updateUser(id: string, request: UpdateUserRequest): Promise<User>`

Update user details.

**Request**:
```typescript
interface UpdateUserRequest {
  fullName?: string
  status?: 'active' | 'inactive'
}
```

**Example**:
```typescript
const updated = await rbacAPI.updateUser(userId, {
  fullName: 'Jane Doe',
  status: 'active',
})
```

#### `deleteUser(id: string): Promise<{ success: boolean }>`

Delete user account.

**Example**:
```typescript
const { success } = await rbacAPI.deleteUser(userId)
if (success) {
  useUserStore.getState().removeUser(userId)
}
```

#### `assignRole(userId: string, request: AssignRoleRequest): Promise<UserRole>`

Assign role to user with optional expiry.

**Request**:
```typescript
interface AssignRoleRequest {
  roleId: string
  expiresAt?: Date  // JIT provisioning
  reason?: string   // Audit trail
}
```

**Response**:
```typescript
interface UserRole {
  id: string
  roleId: string
  userId: string
  granted_at: Date
  expires_at?: Date
  reason?: string
}
```

**Example**:
```typescript
const userRole = await rbacAPI.assignRole(userId, {
  roleId: 'admin',
  expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
  reason: 'Incident response - temporary access',
})
```

#### `removeRole(userId: string, roleId: string): Promise<{ success: boolean }>`

Remove role from user.

**Example**:
```typescript
const { success } = await rbacAPI.removeRole(userId, roleId)
if (success) {
  toast.success('Role removed')
}
```

---

### Repository Access

#### `grantRepositoryAccess(request: GrantRepoAccessRequest): Promise<RepositoryAccess>`

Grant user access to repository.

**Request**:
```typescript
interface GrantRepoAccessRequest {
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string  // e.g., "main", "release/*"
  expiresAt?: Date
}
```

**Response**:
```typescript
interface RepositoryAccess {
  id: string
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string
  grantedAt: Date
  expiresAt?: Date
}
```

**Example**:
```typescript
const access = await rbacAPI.grantRepositoryAccess({
  userId,
  repositoryId,
  accessLevel: 'write',
  branchPattern: 'feature/*',
  expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
})
```

#### `revokeRepositoryAccess(userId: string, repositoryId: string): Promise<{ success: boolean }>`

Revoke user access from repository.

**Example**:
```typescript
const { success } = await rbacAPI.revokeRepositoryAccess(userId, repositoryId)
```

#### `syncRepositories(): Promise<{ synced: number }>`

Sync repositories from GitHub.

**Example**:
```typescript
const { synced } = await rbacAPI.syncRepositories()
toast.success(`Synced ${synced} repositories`)
```

---

### API Tokens

#### `createToken(request: CreateTokenRequest): Promise<CreateTokenResponse>`

Create new API token.

**Request**:
```typescript
interface CreateTokenRequest {
  name: string
  scopes: string[]  // ['read:users', 'write:repos']
  expiresIn?: number  // Days, default 90
}
```

**Response**:
```typescript
interface CreateTokenResponse {
  id: string
  name: string
  secret: string  // Only returned once
  scopes: string[]
  createdAt: Date
  expiresAt: Date
}
```

**Example**:
```typescript
const { secret } = await rbacAPI.createToken({
  name: 'CI/CD Pipeline',
  scopes: ['read:repos', 'write:deployments'],
  expiresIn: 90,
})

// Copy secret to clipboard
navigator.clipboard.writeText(secret)
```

#### `revokeToken(tokenId: string): Promise<{ success: boolean }>`

Revoke API token.

**Example**:
```typescript
const { success } = await rbacAPI.revokeToken(tokenId)
if (success) {
  toast.success('Token revoked')
}
```

---

### Sessions

#### `getSessions(): Promise<Session[]>`

Get all active sessions for current user.

**Response**:
```typescript
interface Session {
  id: string
  userId: string
  token: string
  ipAddress: string
  userAgent: string
  createdAt: Date
  expiresAt: Date
  lastActivityAt: Date
}
```

**Example**:
```typescript
const sessions = await rbacAPI.getSessions()
setActiveSessions(sessions)
```

#### `revokeSession(sessionId: string): Promise<{ success: boolean }>`

Revoke specific session (user action).

**Example**:
```typescript
const { success } = await rbacAPI.revokeSession(sessionId)
if (success) {
  toast.success('Session ended')
  // Refresh sessions list
  const updated = await rbacAPI.getSessions()
  setActiveSessions(updated)
}
```

#### `adminRevokeSession(userId: string, sessionId: string): Promise<{ success: boolean }>`

Revoke user's session (admin action).

**Example**:
```typescript
// Admin forcibly ends user's session
const { success } = await rbacAPI.adminRevokeSession(userId, sessionId)
```

---

### Audit Logs

#### `getAuditLogs(filters?: AuditFilterConfig): Promise<{ logs: AuditLog[]; total: number }>`

Retrieve audit trail.

**Request**:
```typescript
interface AuditFilterConfig {
  startDate?: Date
  endDate?: Date
  eventType?: string  // 'user_created', 'role_assigned', etc
  userId?: string
  page?: number
  limit?: number
}
```

**Response**:
```typescript
interface AuditLog {
  id: string
  eventType: string
  userId: string
  targetId: string  // User/role/repo ID
  changes: Record<string, any>
  ipAddress: string
  userAgent: string
  timestamp: Date
}
```

**Example**:
```typescript
const { logs, total } = await rbacAPI.getAuditLogs({
  eventType: 'role_assigned',
  startDate: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000), // 30 days
  limit: 50,
})
```

---

### Health Check

#### `healthCheck(): Promise<{ status: 'ok' }>`

Check API connectivity.

**Example**:
```typescript
try {
  const { status } = await rbacAPI.healthCheck()
  console.log('API healthy:', status === 'ok')
} catch (error) {
  console.error('API unreachable')
}
```

---

## 3. Error Handling

### Common Errors

```typescript
try {
  await rbacAPI.createUser({ email: 'invalid', fullName: '' })
} catch (error: AxiosError) {
  // Validation error (422)
  if (error.response?.status === 422) {
    const { message, fields } = error.response.data
    console.error('Validation error:', fields)
  }
  
  // Duplicate email (409)
  if (error.response?.status === 409) {
    console.error('Email already exists')
  }
  
  // Unauthorized (401)
  if (error.response?.status === 401) {
    // Token expired - logout user
    useAuthStore.getState().clearAuth()
    window.location.href = '/login'
  }
  
  // Network error
  if (!error.response) {
    console.error('Network error:', error.message)
  }
}
```

### Error Response Format

```typescript
interface ErrorResponse {
  error: string
  message: string
  statusCode: number
  timestamp: string
  path: string
  details?: Record<string, string>  // Validation errors
}
```

---

## 4. Request/Response Examples

### Complete User Creation Flow

```typescript
// 1. User fills form
const formData: CreateUserRequest = {
  email: 'john.doe@example.com',
  fullName: 'John Doe',
  initialRoles: ['developer'],
}

// 2. Hook validates and sends
try {
  const newUser = await rbacAPI.createUser(formData)
  
  // 3. Update local state
  useUserStore.getState().addUser(newUser)
  
  // 4. UI feedback
  toast.success(`Created user: ${newUser.email}`)
  
  // 5. Reset form
  setFormData({ email: '', fullName: '', initialRoles: [] })
  setIsModalOpen(false)
  
} catch (error) {
  // Error handling
  if (error.response?.status === 409) {
    setError('Email already exists')
  } else {
    setError('Failed to create user')
  }
}
```

### Complete Repository Access Flow

```typescript
// 1. User selects repo + access level
const { users, selectedRepositories, accessLevel } = state

// 2. Grant access for each user
const promises = selectedRepositories.map(repoId =>
  rbacAPI.grantRepositoryAccess({
    userId: state.selectedUserId,
    repositoryId: repoId,
    accessLevel,
    expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000),
  })
)

// 3. Wait for all to complete
const results = await Promise.all(promises)

// 4. Show results
toast.success(`Granted access to ${results.length} repositories`)

// 5. Refresh access matrix
const matrix = await fetchAccessMatrix()
```

---

## 5. Type Definitions

Located in: `frontend/src/types/index.ts`

### Domain Models

```typescript
interface User {
  id: string
  email: string
  fullName: string
  status: 'active' | 'inactive'
  mfaEnabled: boolean
  roles: UserRole[]
  createdAt: Date
  updatedAt: Date
  lastLogin?: Date
}

interface Role {
  id: string
  name: string
  description: string
  permissions: Permission[]
  createdAt?: Date
}

interface Permission {
  id: string
  action: string      // 'read', 'write', 'delete'
  resource: string    // 'users', 'repos', 'roles'
  description?: string
}

interface Organization {
  id: string
  slug: string
  name: string
  createdAt: Date
}

interface Repository {
  id: string
  name: string
  url: string
  isPrivate: boolean
  org_id: string
}
```

---

## 6. Custom Hooks

### `useLogin()`

```typescript
const { login, verifyMFA, isLoading, error, mfaRequired, mfaToken } = useLogin()

// Login
await login({ email, password, org_slug })

// Verify TOTP
await verifyMFA(mfaToken, totpCode)
```

### `useUserManagement()`

```typescript
const {
  users,
  selectedUser,
  isLoading,
  error,
  fetchUsers,
  createUser,
  updateUser,
  deleteUser,
  assignRole,
} = useUserManagement()

// Fetch all users
await fetchUsers()

// Create user
await createUser({ email, fullName })

// Assign role with expiry
await assignRole(userId, { roleId, expiresAt, reason })
```

### `useRepositoryAccess()`

```typescript
const { grantAccess, revokeAccess, isLoading } = useRepositoryAccess()

// Grant access
await grantAccess({
  userId,
  repositoryId,
  accessLevel: 'write',
  expiresAt,
})

// Revoke access
await revokeAccess(userId, repositoryId)
```

### `useAPITokens()`

```typescript
const {
  tokens,
  isLoading,
  createToken,
  revokeToken,
  fetchTokens,
} = useAPITokens()

// Create with scopes
const { secret } = await createToken({
  name: 'CI/CD',
  scopes: ['read:repos'],
  expiresIn: 90,
})

// Revoke
await revokeToken(tokenId)
```

### `useSessions()`

```typescript
const { sessions, isLoading, fetchSessions, revokeSession } = useSessions()

// Get active sessions
await fetchSessions()

// End session
await revokeSession(sessionId)
```

---

## 7. Integration Testing

### Mock API for Development

```typescript
// tests/mocks/rbacAPI.ts
export const mockRBACAPI = {
  login: jest.fn().mockResolvedValue({
    token: 'mock-jwt-token',
    user: { id: '1', email: 'test@example.com' },
    org: { id: '1', slug: 'test' },
  }),
  
  getUsers: jest.fn().mockResolvedValue({
    users: [
      { id: '1', email: 'user1@example.com', fullName: 'User 1' },
      { id: '2', email: 'user2@example.com', fullName: 'User 2' },
    ],
    total: 2,
  }),
  
  createUser: jest.fn().mockResolvedValue({
    id: '3',
    email: 'newuser@example.com',
    fullName: 'New User',
    status: 'active',
  }),
}

// Use in tests
jest.mock('@/api/rbac-client', () => ({
  rbacAPI: mockRBACAPI,
}))
```

### Test Example

```typescript
describe('useUserManagement', () => {
  test('should create user', async () => {
    const { result } = renderHook(() => useUserManagement())
    
    await act(async () => {
      await result.current.createUser({
        email: 'test@example.com',
        fullName: 'Test User',
      })
    })
    
    expect(mockRBACAPI.createUser).toHaveBeenCalledWith({
      email: 'test@example.com',
      fullName: 'Test User',
    })
    
    expect(result.current.users).toHaveLength(1)
  })
})
```

---

**API Documentation**: Complete reference for all 20+ RBAC API endpoints.

**Last Updated**: 2026-04-12  
**Next**: [Frontend Architecture](./ARCHITECTURE.md) | [Deployment Guide](./DEPLOYMENT.md)
