// @file        apps/backend/src/services/sentry-client.ts
// @module      services/sentry-client
// @description Sentry error tracking and monitoring client

import axios, { AxiosInstance } from 'axios';

interface SentryError {
  id: string;
  title: string;
  culprit: string;
  level: 'fatal' | 'error' | 'warning' | 'info' | 'debug';
  status: 'unresolved' | 'resolved' | 'ignored';
  count: number;
  userCount: number;
  firstSeen: string;
  lastSeen: string;
  project: { slug: string; name: string };
  environment: string;
  stats: Array<{ timestamp: number; count: number }>;
  tags: Record<string, string>;
  metadata?: {
    filename?: string;
    lineno?: number;
    colno?: number;
    function?: string;
  };
}

interface SentryEvent {
  id: string;
  eventID: string;
  time: string;
  timestamp: number;
  title: string;
  message: string;
  level: string;
  environment: string;
  dist: string;
  platform: string;
  contexts: Record<string, any>;
  release: string;
  user: { id: string; email: string; username: string; ipAddress: string } | null;
  request: { url: string; method: string; headers: Record<string, string> } | null;
  exception: { values: Array<{ type: string; value: string; stacktrace?: any }> } | null;
  breadcrumbs: Array<{ timestamp: number; type: string; category: string; message?: string; data?: any }>;
}

interface SentryRelease {
  version: string;
  shortVersion: string;
  firstEvent: string;
  lastEvent: string;
  dateCreated: string;
  dateReleased: string;
  authors: Array<{ name: string; email: string }>;
  commits: Array<{ id: string; repository: string; message: string; author: string }>;
  issues: { new: number; all: number; resolved: number };
}

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
  private apiClient: AxiosInstance;
  private cacheMap: Map<string, { data: any; timestamp: number }> = new Map();
  private cacheExpiry = 2 * 60 * 1000; // 2 minutes

  constructor(
    private authToken: string,
    private organization: string,
    private project: string,
    private baseUrl: string = 'https://sentry.io/api/0'
  ) {
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
  async getProjects(): Promise<any[]> {
    return this.cachedRequest('projects', async () => {
      const response = await this.apiClient.get(`/organizations/${this.organization}/projects/`);
      return response.data;
    });
  }

  /**
   * List errors in project
   */
  async listErrors(
    environment?: string,
    query?: string,
    limit: number = 25,
    offset: number = 0
  ): Promise<{ errors: SentryError[]; count: number }> {
    try {
      const params: any = { limit, offset };

      if (environment) {
        params.environment = environment;
      }

      if (query) {
        params.query = query;
      }

      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/issues/`,
        { params }
      );

      return {
        errors: response.data,
        count: parseInt(response.headers['x-hits'] || '0'),
      };
    } catch (error) {
      throw new Error(`Failed to list errors: ${error instanceof Error ? error.message : 'Unknown'}`);
    }
  }

  /**
   * Get error details
   */
  async getError(issueId: string): Promise<SentryError> {
    return this.cachedRequest(`error_${issueId}`, async () => {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/issues/${issueId}/`
      );
      return response.data;
    });
  }

  /**
   * Get error events
   */
  async getErrorEvents(issueId: string, limit: number = 10): Promise<SentryEvent[]> {
    try {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/issues/${issueId}/events/`,
        { params: { limit } }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Failed to get events: ${error instanceof Error ? error.message : 'Unknown'}`);
    }
  }

  /**
   * Get specific event
   */
  async getEvent(issueId: string, eventId: string): Promise<SentryEvent> {
    return this.cachedRequest(`event_${issueId}_${eventId}`, async () => {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/issues/${issueId}/events/${eventId}/`
      );
      return response.data;
    });
  }

  /**
   * Resolve issue
   */
  async resolveIssue(issueId: string): Promise<SentryError> {
    const response = await this.apiClient.put(
      `/projects/${this.organization}/${this.project}/issues/${issueId}/`,
      { status: 'resolved' }
    );

    this.invalidateCache(`error_${issueId}`);

    return response.data;
  }

  /**
   * Ignore issue
   */
  async ignoreIssue(issueId: string): Promise<SentryError> {
    const response = await this.apiClient.put(
      `/projects/${this.organization}/${this.project}/issues/${issueId}/`,
      { status: 'ignored' }
    );

    this.invalidateCache(`error_${issueId}`);

    return response.data;
  }

  /**
   * Reopen issue
   */
  async reopenIssue(issueId: string): Promise<SentryError> {
    const response = await this.apiClient.put(
      `/projects/${this.organization}/${this.project}/issues/${issueId}/`,
      { status: 'unresolved' }
    );

    this.invalidateCache(`error_${issueId}`);

    return response.data;
  }

  /**
   * Assign issue to user
   */
  async assignIssue(issueId: string, userId: string): Promise<SentryError> {
    const response = await this.apiClient.put(
      `/projects/${this.organization}/${this.project}/issues/${issueId}/`,
      { assignedTo: userId }
    );

    this.invalidateCache(`error_${issueId}`);

    return response.data;
  }

  /**
   * Add comment to issue
   */
  async addComment(issueId: string, comment: string): Promise<any> {
    const response = await this.apiClient.post(
      `/projects/${this.organization}/${this.project}/issues/${issueId}/comments/`,
      { text: comment }
    );

    return response.data;
  }

  /**
   * Get releases
   */
  async getReleases(limit: number = 10): Promise<SentryRelease[]> {
    return this.cachedRequest('releases', async () => {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/releases/`,
        { params: { limit } }
      );
      return response.data;
    });
  }

  /**
   * Get release details
   */
  async getRelease(version: string): Promise<SentryRelease> {
    return this.cachedRequest(`release_${version}`, async () => {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/releases/${encodeURIComponent(version)}/`
      );
      return response.data;
    });
  }

  /**
   * Get release health
   */
  async getReleaseHealth(version: string): Promise<any> {
    try {
      const response = await this.apiClient.get(
        `/organizations/${this.organization}/releases/${encodeURIComponent(version)}/health/`
      );
      return response.data;
    } catch (error) {
      throw new Error(`Failed to get release health: ${error instanceof Error ? error.message : 'Unknown'}`);
    }
  }

  /**
   * Get error trends
   */
  async getErrorTrends(days: number = 30): Promise<Array<{ date: string; count: number }>> {
    const since = Math.floor((Date.now() - days * 24 * 60 * 60 * 1000) / 1000);

    return this.cachedRequest(`trends_${days}`, async () => {
      const response = await this.apiClient.get(
        `/projects/${this.organization}/${this.project}/stats/`,
        { params: { since, resolution: '1d' } }
      );

      return response.data.map((point: any) => ({
        date: new Date(point[0] * 1000).toISOString(),
        count: point[1],
      }));
    });
  }

  /**
   * Get errors by file
   */
  async getErrorsByFile(): Promise<Map<string, number>> {
    const errors = await this.listErrors(undefined, undefined, 100);
    const fileMap = new Map<string, number>();

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
  async getErrorsByStacktrace(): Promise<Map<string, number>> {
    const errors = await this.listErrors(undefined, undefined, 100);
    const stackMap = new Map<string, number>();

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
  async getErrorDistribution(): Promise<{
    byLevel: Record<string, number>;
    byEnvironment: Record<string, number>;
    byUser: Array<{ email: string; count: number }>;
  }> {
    const errors = await this.listErrors(undefined, undefined, 100);

    const distribution = {
      byLevel: {} as Record<string, number>,
      byEnvironment: {} as Record<string, number>,
      byUser: [] as Array<{ email: string; count: number }>,
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
  private async cachedRequest(cacheKey: string, fetchFn: () => Promise<any>): Promise<any> {
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
  private invalidateCache(cacheKey: string): void {
    this.cacheMap.delete(cacheKey);
  }

  /**
   * Clear all cache
   */
  clearCache(): void {
    this.cacheMap.clear();
  }
}

export default SentryClient;
