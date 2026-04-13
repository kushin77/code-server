import axios, { AxiosInstance, AxiosError } from 'axios'
import * as types from '@/types'
import { useAuthStore } from '@/store'

/**
 * RBAC API Client
 * Singleton Axios instance with interceptors for JWT auth and error handling
 * 20+ methods covering all RBAC operations
 */
class RBACAPIClient {
  private axiosInstance: AxiosInstance

  constructor(baseURL?: string) {
    // MANDATE: Use domain DNS or container networks by default, NEVER localhost
    // Development: VITE_API_URL=http://rbac-api:3001 (Docker container network)
    // Production: VITE_API_URL=https://ide.kushnir.cloud/api OR https://api.kushnir.cloud
    const defaultUrl = baseURL || 
      process.env.VITE_API_URL || 
      (typeof window !== 'undefined' ? `${window.location.origin}/api` : 'http://rbac-api:3001')
    
    this.axiosInstance = axios.create({
      baseURL: defaultUrl,
      headers: {
        'Content-Type': 'application/json',
      },
    })

    // Setup interceptors
    this.setupInterceptors()
  }

  /**
   * Setup request/response interceptors
   */
  private setupInterceptors() {
    // Request interceptor: Add JWT token
    this.axiosInstance.interceptors.request.use(
      (config) => {
        const token = useAuthStore.getState().token
        if (token) {
          config.headers.Authorization = `Bearer ${token}`
        }
        return config
      },
      (error) => Promise.reject(error)
    )

    // Response interceptor: Handle errors and 401
    this.axiosInstance.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        // Handle 401 Unauthorized
        if (error.response?.status === 401) {
          useAuthStore.getState().clearAuth()
          window.location.href = '/login'
        }
        return Promise.reject(error)
      }
    )
  }

  // ============= Helper Methods =============

  private async get<T>(endpoint: string, config?: any): Promise<T> {
    const response = await this.axiosInstance.get<T>(endpoint, config)
    return response.data
  }

  private async post<T>(endpoint: string, data?: any, config?: any): Promise<T> {
    const response = await this.axiosInstance.post<T>(endpoint, data, config)
    return response.data
  }

  private async patch<T>(endpoint: string, data?: any, config?: any): Promise<T> {
    const response = await this.axiosInstance.patch<T>(endpoint, data, config)
    return response.data
  }

  private async delete<T>(endpoint: string, config?: any): Promise<T> {
    const response = await this.axiosInstance.delete<T>(endpoint, config)
    return response.data
  }

  // ============= Authentication Methods =============

  /**
   * Login with email/password
   */
  async login(request: types.LoginRequest): Promise<types.LoginResponse> {
    return this.post<types.LoginResponse>('/auth/login', request)
  }

  /**
   * Verify TOTP code
   */
  async verifyMFA(mfaToken: string, totpCode: string): Promise<types.MFAVerifyResponse> {
    return this.post<types.MFAVerifyResponse>('/auth/mfa-verify', {
      mfaToken,
      totpCode,
    })
  }

  /**
   * Setup TOTP MFA
   */
  async setupMFA(): Promise<types.MFASetupResponse> {
    return this.post<types.MFASetupResponse>('/auth/mfa-setup', {})
  }

  /**
   * Confirm MFA setup
   */
  async confirmMFA(secret: string, totpCode: string): Promise<{ success: boolean }> {
    return this.post<{ success: boolean }>('/auth/mfa-confirm', {
      secret,
      totpCode,
    })
  }

  /**
   * Logout (invalidate session)
   */
  async logout(): Promise<{ success: boolean }> {
    return this.post<{ success: boolean }>('/auth/logout', {})
  }

  // ============= User Management Methods =============

  /**
   * Get all users
   */
  async getUsers(filters?: types.FilterConfig): Promise<{ users: types.User[]; total: number }> {
    return this.get<{ users: types.User[]; total: number }>('/admin/users', {
      params: filters,
    })
  }

  /**
   * Create new user
   */
  async createUser(request: types.CreateUserRequest): Promise<types.User> {
    return this.post<types.User>('/admin/users', request)
  }

  /**
   * Update user
   */
  async updateUser(id: string, request: types.UpdateUserRequest): Promise<types.User> {
    return this.patch<types.User>(`/admin/users/${id}`, request)
  }

  /**
   * Delete user
   */
  async deleteUser(id: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/admin/users/${id}`)
  }

  /**
   * Assign role to user
   */
  async assignRole(userId: string, request: types.AssignRoleRequest): Promise<types.UserRole> {
    return this.post<types.UserRole>(`/admin/users/${userId}/roles`, request)
  }

  /**
   * Remove role from user
   */
  async removeRole(userId: string, roleId: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/admin/users/${userId}/roles/${roleId}`)
  }

  // ============= Repository Access Methods =============

  /**
   * Grant repository access
   */
  async grantRepositoryAccess(request: types.GrantRepoAccessRequest): Promise<types.RepositoryAccess> {
    return this.post<types.RepositoryAccess>('/admin/repos/access', request)
  }

  /**
   * Revoke repository access
   */
  async revokeRepositoryAccess(userId: string, repositoryId: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/admin/repos/${repositoryId}/access/${userId}`)
  }

  // ============= API Token Methods =============

  /**
   * Create API token
   */
  async createToken(request: types.CreateTokenRequest): Promise<types.CreateTokenResponse> {
    return this.post<types.CreateTokenResponse>('/tokens', request)
  }

  /**
   * Revoke API token
   */
  async revokeToken(tokenId: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/tokens/${tokenId}`)
  }

  // ============= Session Methods =============

  /**
   * Get active sessions
   */
  async getSessions(): Promise<types.Session[]> {
    return this.get<types.Session[]>('/sessions')
  }

  /**
   * Revoke own session
   */
  async revokeSession(sessionId: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/sessions/${sessionId}`)
  }

  /**
   * Admin revoke user session
   */
  async adminRevokeSession(userId: string, sessionId: string): Promise<{ success: boolean }> {
    return this.delete<{ success: boolean }>(`/admin/sessions/${userId}/${sessionId}`)
  }

  // ============= Audit Log Methods =============

  /**
   * Get audit logs
   */
  async getAuditLogs(
    filters?: types.FilterConfig
  ): Promise<{ logs: types.AuditLog[]; total: number }> {
    return this.get<{ logs: types.AuditLog[]; total: number }>('/audit-logs', {
      params: filters,
    })
  }

  // ============= GitHub Sync Methods =============

  /**
   * Sync repositories from GitHub
   */
  async syncRepositories(): Promise<{ synced: number }> {
    return this.post<{ synced: number }>('/admin/sync-repos', {})
  }

  // ============= Health Check =============

  /**
   * Health check endpoint
   */
  async healthCheck(): Promise<types.HealthCheckResponse> {
    return this.get<types.HealthCheckResponse>('/health')
  }
}

// Export singleton instance
export const rbacAPI = new RBACAPIClient()
