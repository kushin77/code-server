import axios from 'axios';
import { useAuthStore } from '@/store';
/**
 * RBAC API Client
 * Singleton Axios instance with interceptors for JWT auth and error handling
 * 20+ methods covering all RBAC operations
 */
class RBACAPIClient {
    constructor(baseURL = 'http://localhost:3001') {
        this.axiosInstance = axios.create({
            baseURL,
            headers: {
                'Content-Type': 'application/json',
            },
        });
        // Setup interceptors
        this.setupInterceptors();
    }
    /**
     * Setup request/response interceptors
     */
    setupInterceptors() {
        // Request interceptor: Add JWT token
        this.axiosInstance.interceptors.request.use((config) => {
            const token = useAuthStore.getState().token;
            if (token) {
                config.headers.Authorization = `Bearer ${token}`;
            }
            return config;
        }, (error) => Promise.reject(error));
        // Response interceptor: Handle errors and 401
        this.axiosInstance.interceptors.response.use((response) => response, (error) => {
            // Handle 401 Unauthorized
            if (error.response?.status === 401) {
                useAuthStore.getState().clearAuth();
                window.location.href = '/login';
            }
            return Promise.reject(error);
        });
    }
    // ============= Helper Methods =============
    async get(endpoint, config) {
        const response = await this.axiosInstance.get(endpoint, config);
        return response.data;
    }
    async post(endpoint, data, config) {
        const response = await this.axiosInstance.post(endpoint, data, config);
        return response.data;
    }
    async patch(endpoint, data, config) {
        const response = await this.axiosInstance.patch(endpoint, data, config);
        return response.data;
    }
    async delete(endpoint, config) {
        const response = await this.axiosInstance.delete(endpoint, config);
        return response.data;
    }
    // ============= Authentication Methods =============
    /**
     * Login with email/password
     */
    async login(request) {
        return this.post('/auth/login', request);
    }
    /**
     * Verify TOTP code
     */
    async verifyMFA(mfaToken, totpCode) {
        return this.post('/auth/mfa-verify', {
            mfaToken,
            totpCode,
        });
    }
    /**
     * Setup TOTP MFA
     */
    async setupMFA() {
        return this.post('/auth/mfa-setup', {});
    }
    /**
     * Confirm MFA setup
     */
    async confirmMFA(secret, totpCode) {
        return this.post('/auth/mfa-confirm', {
            secret,
            totpCode,
        });
    }
    /**
     * Logout (invalidate session)
     */
    async logout() {
        return this.post('/auth/logout', {});
    }
    // ============= User Management Methods =============
    /**
     * Get all users
     */
    async getUsers(filters) {
        return this.get('/admin/users', {
            params: filters,
        });
    }
    /**
     * Create new user
     */
    async createUser(request) {
        return this.post('/admin/users', request);
    }
    /**
     * Update user
     */
    async updateUser(id, request) {
        return this.patch(`/admin/users/${id}`, request);
    }
    /**
     * Delete user
     */
    async deleteUser(id) {
        return this.delete(`/admin/users/${id}`);
    }
    /**
     * Assign role to user
     */
    async assignRole(userId, request) {
        return this.post(`/admin/users/${userId}/roles`, request);
    }
    /**
     * Remove role from user
     */
    async removeRole(userId, roleId) {
        return this.delete(`/admin/users/${userId}/roles/${roleId}`);
    }
    // ============= Repository Access Methods =============
    /**
     * Grant repository access
     */
    async grantRepositoryAccess(request) {
        return this.post('/admin/repos/access', request);
    }
    /**
     * Revoke repository access
     */
    async revokeRepositoryAccess(userId, repositoryId) {
        return this.delete(`/admin/repos/${repositoryId}/access/${userId}`);
    }
    // ============= API Token Methods =============
    /**
     * Create API token
     */
    async createToken(request) {
        return this.post('/tokens', request);
    }
    /**
     * Revoke API token
     */
    async revokeToken(tokenId) {
        return this.delete(`/tokens/${tokenId}`);
    }
    // ============= Session Methods =============
    /**
     * Launch an ephemeral session
     */
    async launchSession(request) {
        return this.post('/sessions', request);
    }
    /**
     * Inspect an ephemeral session lifecycle state
     */
    async getSessionStatus(sessionId) {
        return this.get(`/sessions/${sessionId}/status`);
    }
    /**
     * Cancel an ephemeral session before teardown completes
     */
    async cancelSession(sessionId) {
        return this.post(`/sessions/${sessionId}/cancel`, {});
    }
    /**
     * Destroy an ephemeral session immediately
     */
    async destroySession(sessionId) {
        return this.post(`/sessions/${sessionId}/destroy`, {});
    }
    /**
     * Get active sessions
     */
    async getSessions() {
        return this.get('/sessions');
    }
    /**
     * Revoke own session
     */
    async revokeSession(sessionId) {
        return this.delete(`/sessions/${sessionId}`);
    }
    /**
     * Admin revoke user session
     */
    async adminRevokeSession(userId, sessionId) {
        return this.delete(`/admin/sessions/${userId}/${sessionId}`);
    }
    // ============= Audit Log Methods =============
    /**
     * Get audit logs
     */
    async getAuditLogs(filters) {
        return this.get('/audit-logs', {
            params: filters,
        });
    }
    // ============= GitHub Sync Methods =============
    /**
     * Sync repositories from GitHub
     */
    async syncRepositories() {
        return this.post('/admin/sync-repos', {});
    }
    // ============= Health Check =============
    /**
     * Health check endpoint
     */
    async healthCheck() {
        return this.get('/health');
    }
}
// Export singleton instance
export const rbacAPI = new RBACAPIClient();
//# sourceMappingURL=rbac-client.js.map