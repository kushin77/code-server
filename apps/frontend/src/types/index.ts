/**
 * Type Definitions for RBAC Frontend
 * Single source of truth for all API contracts and component props
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

export interface Team {
  id: string
  name: string
  org_id: string
  created_by: string
  createdAt: Date
}

export interface TeamMember {
  id: string
  team_id: string
  user_id: string
  role: 'owner' | 'admin' | 'developer'
  joined_at: Date
}

export interface Repository {
  id: string
  name: string
  url: string
  isPrivate: boolean
  org_id: string
}

export interface RepositoryAccess {
  id: string
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string
  grantedAt: Date
  expiresAt?: Date
}

export interface APIToken {
  id: string
  name: string
  scopes: string[]
  createdAt: Date
  expiresAt: Date
  lastUsedAt?: Date
}

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

export interface LoginRequest {
  email: string
  password: string
  org_slug: string
}

export interface LoginResponse {
  token: string
  user: User
  org: Organization
  requiresMfa?: boolean
  mfaToken?: string
}

export interface MFAVerifyRequest {
  mfaToken: string
  totpCode: string
}

export interface MFAVerifyResponse {
  token: string
  user: User
  org: Organization
}

export interface MFASetupResponse {
  secret: string
  qrCode: string
  backupCodes?: string[]
}

export interface CreateUserRequest {
  email: string
  fullName: string
  initialRoles?: string[]
}

export interface UpdateUserRequest {
  fullName?: string
  status?: 'active' | 'inactive'
}

export interface AssignRoleRequest {
  roleId: string
  expiresAt?: Date
  reason?: string
}

export interface GrantRepoAccessRequest {
  userId: string
  repositoryId: string
  accessLevel: 'read' | 'write' | 'admin'
  branchPattern?: string
  expiresAt?: Date
}

export interface CreateTokenRequest {
  name: string
  scopes: string[]
  expiresIn?: number
}

export interface CreateTokenResponse {
  id: string
  name: string
  secret: string
  scopes: string[]
  createdAt: Date
  expiresAt: Date
}

// ============= Store State Types =============

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

export interface RoleState {
  roles: Role[]
  setRoles: (roles: Role[]) => void
  addRole: (role: Role) => void
  removeRole: (roleId: string) => void
}

// ============= UI Component Types =============

export interface TableColumn<T> {
  key: string
  label: string
  render?: (value: any, row: T) => React.ReactNode
  sortable?: boolean
  width?: string
}

export interface PaginationParams {
  page: number
  limit: number
}

export interface FilterConfig {
  page?: number
  limit?: number
  status?: 'active' | 'inactive'
  search?: string
  startDate?: Date
  endDate?: Date
}

// ============= API Health Check =============

export interface HealthCheckResponse {
  status: 'ok' | 'error'
  timestamp: string
}

// ============= List Response Types =============

export interface ListResponse<T> {
  data: T[]
  total: number
  page: number
  limit: number
}
