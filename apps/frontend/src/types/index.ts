/**
 * Type Definitions for RBAC Frontend
 * Single source of truth for all API contracts and component props
 * 
 * NOTE: Many types show as unused by ts-prune but are actually:
 * - Part of public API contracts consumed by backend
 * - Used transitively through union types and interfaces
 * - Used internally within components (ts-prune limitation)
 * 
 * @ts-prune-ignore (issue #1023)
 */

// ============= Domain Models =============

export interface Organization {
  id: string
  slug: string
  name: string
  createdAt: Date
}

export interface User {
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

export interface Role {
  id: string
  name: string
  description: string
  permissions: Permission[]
  createdAt?: Date
}

export interface UserRole {
  id: string
  roleId: string
  userId: string
  granted_at: Date
  expires_at?: Date
  reason?: string
}

// @ts-prune-ignore
/** @ts-prune-ignore - API contract type for repository access */
export interface RepositoryAccess {
  id: string
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string
  grantedAt: Date
  expiresAt?: Date
}

// @ts-prune-ignore
/** @ts-prune-ignore - API contract type for API tokens */
export interface APIToken {
  id: string
  name: string
  scopes: string[]
  createdAt: Date
  expiresAt: Date
  lastUsedAt?: Date
}

// @ts-prune-ignore
/** @ts-prune-ignore - API contract type for session tokens */
export interface Session {
  id: string
  userId: string
  token: string
  ipAddress: string
  userAgent: string
  createdAt: Date
  expiresAt: Date
  lastActivityAt: Date
}

export type SessionLifecycleState = 'requested' | 'queued' | 'provisioning' | 'ready' | 'testing' | 'teardown_pending' | 'destroyed' | 'failed'

export type SessionQueueLane = 'fast' | 'standard'

export type SessionDataProfile = 'synthetic' | 'masked' | 'redacted'

export type SessionProvenanceVerificationResult = 'verified' | 'failed'

export interface SessionProvenanceManifest {
  imageDigest: string
  attestationRef: string
  signerIdentity: string
  verificationTimestamp: Date
  verificationResult: SessionProvenanceVerificationResult
  policyVersion: string
  sessionFingerprint?: string
}

// @ts-prune-ignore
/** @ts-prune-ignore - API contract type for ephemeral sessions */
export interface EphemeralSession {
  sessionId: string
  userId: string
  username: string
  email: string
  dataProfile: SessionDataProfile
  dataProfileValidated: boolean
  provenance?: SessionProvenanceManifest | null
  queueLane?: SessionQueueLane | null
  queuePosition?: number | null
  queueEstimatedWaitSeconds?: number | null
  queueReason?: string | null
  queueEnqueuedAt?: Date | null
  queue?: SessionQueueSummary | null
  containerName: string
  containerPort: number
  url?: string | null
  status: SessionLifecycleState
  createdAt: Date
  expiresAt: Date
  lastActivity: Date
  quotas: {
    cpuLimit: string
    memoryLimit: string
    storageLimit: string
  }
}

/** @ts-prune-ignore - API contract type for session launch requests */
export interface EphemeralSessionLaunchRequest {
  userId: string
  username: string
  email: string
  dataProfile: SessionDataProfile
  provenance?: SessionProvenanceManifest
  priorityLane?: SessionQueueLane
  ttlSeconds?: number
}

export interface SessionQueueSummary {
  lane: SessionQueueLane
  position: number | null
  estimatedWaitSeconds: number | null
  reason: string | null
  enqueuedAt: Date | null
}

/** @ts-prune-ignore - API contract type for session status */
export interface EphemeralSessionStatus {
  sessionId: string
  state: SessionLifecycleState
  active: boolean
  terminal: boolean
  dataProfile: SessionDataProfile
  dataProfileValidated: boolean
  provenance?: SessionProvenanceManifest | null
  queue?: SessionQueueSummary | null
  containerPort: number
  containerName: string
  expiresAt: Date
  lastActivity: Date
  nextActions: Array<'cancel' | 'destroy'>
}

/** @ts-prune-ignore - API contract type for audit logs */
export interface AuditLog {
  id: string
  eventType: string
  userId: string
  targetId: string
  changes: Record<string, any>
  ipAddress: string
  userAgent: string
  timestamp: Date
}

export interface Permission {
  id: string
  action: string
  resource: string
  description?: string
}

// ============= API Request Types =============

/** @ts-prune-ignore - API contract type for login requests */
export interface LoginRequest {
  email: string
  password: string
  org_slug: string
}

/** @ts-prune-ignore - API contract type for login responses */
export interface LoginResponse {
  token: string
  user: User
  org: Organization
  requiresMfa?: boolean
  mfaToken?: string
}

/** @ts-prune-ignore - API contract type for MFA verification */
export interface MFAVerifyRequest {
  mfaToken: string
  totpCode: string
}

/** @ts-prune-ignore - API contract type for MFA verification responses */
export interface MFAVerifyResponse {
  token: string
  user: User
  org: Organization
}

/** @ts-prune-ignore - API contract type for MFA setup */
export interface MFASetupResponse {
  secret: string
  qrCode: string
  backupCodes?: string[]
}

/** @ts-prune-ignore - API contract type for user creation */
export interface CreateUserRequest {
  email: string
  fullName: string
  initialRoles?: string[]
}

/** @ts-prune-ignore - API contract type for user updates */
export interface UpdateUserRequest {
  fullName?: string
  status?: 'active' | 'inactive'
}

/** @ts-prune-ignore - API contract type for role assignment */
export interface AssignRoleRequest {
  roleId: string
  expiresAt?: Date
  reason?: string
}

/** @ts-prune-ignore - API contract type for repository access grants */
export interface GrantRepoAccessRequest {
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string
  expiresAt?: Date
}

/** @ts-prune-ignore - API contract type for token creation */
export interface CreateTokenRequest {
  name: string
  scopes: string[]
  expiresIn?: number
}

/** @ts-prune-ignore - API contract type for token creation responses */
export interface CreateTokenResponse {
  id: string
  name: string
  secret: string
  scopes: string[]
  createdAt: Date
  expiresAt: Date
}

// ============= Store State Types =============

/** @ts-prune-ignore - Store state type for authentication */
export interface AuthState {
  token: string | null
  user: User | null
  org: Organization | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
  setToken: (token: string | null) => void
  setUser: (user: User | null) => void
  setOrg: (org: Organization | null) => void
  setError: (error: string | null) => void
  clearAuth: () => void
}

/** @ts-prune-ignore - Store state type for users */
export interface UserState {
  users: User[]
  selectedUser: User | null
  filters: FilterConfig
  isLoading: boolean
  setUsers: (users: User[]) => void
  addUser: (user: User) => void
  updateUser: (user: User) => void
  removeUser: (userId: string) => void
  setSelectedUser: (user: User | null) => void
  setLoading: (loading: boolean) => void
  fetchUsers: (filters?: FilterConfig) => Promise<void>
}

/** @ts-prune-ignore - Store state type for roles */
export interface RoleState {
  roles: Role[]
  setRoles: (roles: Role[]) => void
  addRole: (role: Role) => void
  removeRole: (roleId: string) => void
}

// ============= UI Component Types =============

/** @ts-prune-ignore - UI component type for table columns */
export interface TableColumn<T> {
  key: string
  label: string
  render?: (value: any, row: T) => React.ReactNode
  sortable?: boolean
  width?: string
}

/** @ts-prune-ignore - UI component type for pagination params */
export interface PaginationParams {
  page: number
  limit: number
}

/** @ts-prune-ignore - API contract type for filter configuration */
export interface FilterConfig {
  page?: number
  limit?: number
  status?: 'active' | 'inactive'
  search?: string
  startDate?: Date
  endDate?: Date
}

// ============= API Health Check =============

/** @ts-prune-ignore - API contract type for health check response */
export interface HealthCheckResponse {
  status: 'ok' | 'error'
  timestamp: string
}

// ============= List Response Types =============

/** @ts-prune-ignore - API contract type for list responses */
export interface ListResponse<T> {
  data: T[]
  total: number
  page: number
  limit: number
}
