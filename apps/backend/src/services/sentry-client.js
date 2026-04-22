// @file        apps/backend/src/services/sentry-client.ts
// @module      services/sentry-client
// @description Sentry error tracking and monitoring client
import axios from 'axios';
/**
 * Sentry Error Tracking Client
 *
 * Provides methods for:
 * - Fetching error issues and events
 * - Tracking errors by environment/release
 * - Managing issue status and resolution
 * - Accessing source maps and stack traces
 * - Release tracking and health
 */
export class SentryClient {
    constructor(authToken, organization, project, baseUrl = 'https://sentry.io/api/0') {
        this.authToken = authToken;
        this.organization = organization;
        this.project = project;
        this.baseUrl = baseUrl;
        this.cacheMap = new Map();
        this.cacheExpiry = 2 * 60 * 1000; // 2 minutes
        this.apiClient = axios.create({
            baseURL: baseUrl,
            headers: {
                'Authorization': `Bearer ${authToken}`,
                'Content-Type': 'application/json',
            },
            timeout: 10000,
        });
    }
    /**
     * Get organization projects
     */
    async getProjects() {
        return this.cachedRequest('projects', async () => {
            const response = await this.apiClient.get(`/organizations/${this.organization}/projects/`);
            return response.data;
        });
    }
    /**
     * List errors in project
     */
    async listErrors(environment, query, limit = 25, offset = 0) {
        try {
            const params = { limit, offset };
            if (environment) {
                params.environment = environment;
            }
            if (query) {
                params.query = query;
            }
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/issues/`, { params });
            return {
                errors: response.data,
                count: parseInt(response.headers['x-hits'] || '0'),
            };
        }
        catch (error) {
            throw new Error(`Failed to list errors: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Get error details
     */
    async getError(issueId) {
        return this.cachedRequest(`error_${issueId}`, async () => {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/issues/${issueId}/`);
            return response.data;
        });
    }
    /**
     * Get error events
     */
    async getErrorEvents(issueId, limit = 10) {
        try {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/issues/${issueId}/events/`, { params: { limit } });
            return response.data;
        }
        catch (error) {
            throw new Error(`Failed to get events: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Get specific event
     */
    async getEvent(issueId, eventId) {
        return this.cachedRequest(`event_${issueId}_${eventId}`, async () => {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/issues/${issueId}/events/${eventId}/`);
            return response.data;
        });
    }
    /**
     * Resolve issue
     */
    async resolveIssue(issueId) {
        const response = await this.apiClient.put(`/projects/${this.organization}/${this.project}/issues/${issueId}/`, { status: 'resolved' });
        this.invalidateCache(`error_${issueId}`);
        return response.data;
    }
    /**
     * Ignore issue
     */
    async ignoreIssue(issueId) {
        const response = await this.apiClient.put(`/projects/${this.organization}/${this.project}/issues/${issueId}/`, { status: 'ignored' });
        this.invalidateCache(`error_${issueId}`);
        return response.data;
    }
    /**
     * Reopen issue
     */
    async reopenIssue(issueId) {
        const response = await this.apiClient.put(`/projects/${this.organization}/${this.project}/issues/${issueId}/`, { status: 'unresolved' });
        this.invalidateCache(`error_${issueId}`);
        return response.data;
    }
    /**
     * Assign issue to user
     */
    async assignIssue(issueId, userId) {
        const response = await this.apiClient.put(`/projects/${this.organization}/${this.project}/issues/${issueId}/`, { assignedTo: userId });
        this.invalidateCache(`error_${issueId}`);
        return response.data;
    }
    /**
     * Add comment to issue
     */
    async addComment(issueId, comment) {
        const response = await this.apiClient.post(`/projects/${this.organization}/${this.project}/issues/${issueId}/comments/`, { text: comment });
        return response.data;
    }
    /**
     * Get releases
     */
    async getReleases(limit = 10) {
        return this.cachedRequest('releases', async () => {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/releases/`, { params: { limit } });
            return response.data;
        });
    }
    /**
     * Get release details
     */
    async getRelease(version) {
        return this.cachedRequest(`release_${version}`, async () => {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/releases/${encodeURIComponent(version)}/`);
            return response.data;
        });
    }
    /**
     * Get release health
     */
    async getReleaseHealth(version) {
        try {
            const response = await this.apiClient.get(`/organizations/${this.organization}/releases/${encodeURIComponent(version)}/health/`);
            return response.data;
        }
        catch (error) {
            throw new Error(`Failed to get release health: ${error instanceof Error ? error.message : 'Unknown'}`);
        }
    }
    /**
     * Get error trends
     */
    async getErrorTrends(days = 30) {
        const since = Math.floor((Date.now() - days * 24 * 60 * 60 * 1000) / 1000);
        return this.cachedRequest(`trends_${days}`, async () => {
            const response = await this.apiClient.get(`/projects/${this.organization}/${this.project}/stats/`, { params: { since, resolution: '1d' } });
            return response.data.map((point) => ({
                date: new Date(point[0] * 1000).toISOString(),
                count: point[1],
            }));
        });
    }
    /**
     * Get errors by file
     */
    async getErrorsByFile() {
        const errors = await this.listErrors(undefined, undefined, 100);
        const fileMap = new Map();
        errors.errors.forEach((error) => {
            if (error.metadata?.filename) {
                const count = fileMap.get(error.metadata.filename) || 0;
                fileMap.set(error.metadata.filename, count + error.count);
            }
        });
        return fileMap;
    }
    /**
     * Get errors by stacktrace
     */
    async getErrorsByStacktrace() {
        const errors = await this.listErrors(undefined, undefined, 100);
        const stackMap = new Map();
        errors.errors.forEach((error) => {
            const stack = `${error.metadata?.filename}:${error.metadata?.lineno}`;
            const count = stackMap.get(stack) || 0;
            stackMap.set(stack, count + error.count);
        });
        return stackMap;
    }
    /**
     * Get error distribution
     */
    async getErrorDistribution() {
        const errors = await this.listErrors(undefined, undefined, 100);
        const distribution = {
            byLevel: {},
            byEnvironment: {},
            byUser: [],
        };
        errors.errors.forEach((error) => {
            // By level
            distribution.byLevel[error.level] = (distribution.byLevel[error.level] || 0) + error.count;
            // By environment
            distribution.byEnvironment[error.environment] =
                (distribution.byEnvironment[error.environment] || 0) + error.count;
        });
        return distribution;
    }
    /**
     * Cached request
     */
    async cachedRequest(cacheKey, fetchFn) {
        const cached = this.cacheMap.get(cacheKey);
        if (cached && Date.now() - cached.timestamp < this.cacheExpiry) {
            return cached.data;
        }
        const data = await fetchFn();
        this.cacheMap.set(cacheKey, { data, timestamp: Date.now() });
        return data;
    }
    /**
     * Invalidate cache
     */
    invalidateCache(cacheKey) {
        this.cacheMap.delete(cacheKey);
    }
    /**
     * Clear all cache
     */
    clearCache() {
        this.cacheMap.clear();
    }
}
export default SentryClient;
//# sourceMappingURL=sentry-client.js.map