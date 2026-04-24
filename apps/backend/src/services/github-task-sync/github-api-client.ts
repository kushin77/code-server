#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/github-api-client.ts
// @module      services/github-task-sync
// @description GitHub REST API client for issue management
// @owner       collab-9
// @status      active

import axios, { AxiosInstance } from 'axios';
import { EventEmitter } from 'events';

export interface GitHubIssue {
  id: number;
  number: number;
  title: string;
  body: string;
  state: 'open' | 'closed';
  assignee?: { login: string; avatar_url: string } | null;
  labels: Array<{ name: string; color: string }>;
  created_at: string;
  updated_at: string;
  closed_at?: string | null;
  user: { login: string; avatar_url: string };
  url: string;
  html_url: string;
  comments: number;
}

export interface CreateIssueInput {
  title: string;
  body?: string;
  labels?: string[];
  assignees?: string[];
}

export interface UpdateIssueInput {
  title?: string;
  body?: string;
  state?: 'open' | 'closed';
  labels?: string[];
  assignees?: string[];
}

export interface IssueComment {
  id: number;
  body: string;
  user: { login: string; avatar_url: string };
  created_at: string;
  updated_at: string;
}

export class GitHubAPIClient extends EventEmitter {
  private client: AxiosInstance;
  private owner: string;
  private repo: string;
  private baseUrl = 'https://api.github.com';
  private cache = new Map<string, { data: any; ttl: number }>();
  private cacheTTL = 60000; // 1 minute default cache

  constructor(token: string, owner: string, repo: string) {
    super();
    this.owner = owner;
    this.repo = repo;

    this.client = axios.create({
      baseURL: this.baseUrl,
      headers: {
        'Authorization': `token ${token}`,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'code-server-ide-task-sync',
      },
      timeout: 10000,
    });

    // Add response interceptor for rate limiting
    this.client.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 403) {
          this.emit('rate-limited', {
            resetTime: error.response.headers['x-ratelimit-reset'],
            remaining: error.response.headers['x-ratelimit-remaining'],
          });
        }
        throw error;
      }
    );
  }

  /**
   * Get a single issue by number
   */
  async getIssue(issueNumber: number): Promise<GitHubIssue> {
    const cacheKey = `issue-${issueNumber}`;
    
    const cached = this.cache.get(cacheKey);
    if (cached && cached.ttl > Date.now()) {
      return cached.data;
    }

    const response = await this.client.get<GitHubIssue>(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}`
    );

    this.cache.set(cacheKey, {
      data: response.data,
      ttl: Date.now() + this.cacheTTL,
    });

    return response.data;
  }

  /**
   * List issues with filters
   */
  async listIssues(filters?: {
    state?: 'open' | 'closed' | 'all';
    labels?: string[];
    assignee?: string;
    sort?: 'created' | 'updated' | 'comments';
    direction?: 'asc' | 'desc';
    per_page?: number;
  }): Promise<GitHubIssue[]> {
    const params = new URLSearchParams();
    
    if (filters?.state) params.append('state', filters.state);
    if (filters?.labels?.length) params.append('labels', filters.labels.join(','));
    if (filters?.assignee) params.append('assignee', filters.assignee);
    if (filters?.sort) params.append('sort', filters.sort);
    if (filters?.direction) params.append('direction', filters.direction);
    params.append('per_page', String(filters?.per_page || 30));

    const cacheKey = `issues-${params.toString()}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.ttl > Date.now()) {
      return cached.data;
    }

    const response = await this.client.get<GitHubIssue[]>(
      `/repos/${this.owner}/${this.repo}/issues?${params.toString()}`
    );

    this.cache.set(cacheKey, {
      data: response.data,
      ttl: Date.now() + this.cacheTTL,
    });

    return response.data;
  }

  /**
   * Create a new issue
   */
  async createIssue(input: CreateIssueInput): Promise<GitHubIssue> {
    const response = await this.client.post<GitHubIssue>(
      `/repos/${this.owner}/${this.repo}/issues`,
      {
        title: input.title,
        body: input.body || '',
        labels: input.labels || [],
        assignees: input.assignees || [],
      }
    );

    // Invalidate cache
    this.cache.delete(`issues-`);
    
    this.emit('issue-created', {
      issueNumber: response.data.number,
      title: response.data.title,
    });

    return response.data;
  }

  /**
   * Update an existing issue
   */
  async updateIssue(issueNumber: number, input: UpdateIssueInput): Promise<GitHubIssue> {
    const response = await this.client.patch<GitHubIssue>(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}`,
      {
        title: input.title,
        body: input.body,
        state: input.state,
        labels: input.labels,
        assignees: input.assignees,
      }
    );

    // Invalidate cache
    this.cache.delete(`issue-${issueNumber}`);
    this.cache.delete(`issues-`);

    const stateChange = input.state ? ` (${input.state})` : '';
    this.emit('issue-updated', {
      issueNumber,
      title: response.data.title,
      stateChange,
    });

    return response.data;
  }

  /**
   * Close an issue
   */
  async closeIssue(issueNumber: number, reason?: string): Promise<GitHubIssue> {
    return this.updateIssue(issueNumber, {
      state: 'closed',
      body: reason ? `Closed from IDE\n\n${reason}` : undefined,
    });
  }

  /**
   * Reopen a closed issue
   */
  async reopenIssue(issueNumber: number): Promise<GitHubIssue> {
    return this.updateIssue(issueNumber, { state: 'open' });
  }

  /**
   * Get issue comments
   */
  async getIssueComments(issueNumber: number): Promise<IssueComment[]> {
    const cacheKey = `comments-${issueNumber}`;
    
    const cached = this.cache.get(cacheKey);
    if (cached && cached.ttl > Date.now()) {
      return cached.data;
    }

    const response = await this.client.get<IssueComment[]>(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}/comments`
    );

    this.cache.set(cacheKey, {
      data: response.data,
      ttl: Date.now() + this.cacheTTL,
    });

    return response.data;
  }

  /**
   * Add a comment to an issue
   */
  async addComment(issueNumber: number, body: string): Promise<IssueComment> {
    const response = await this.client.post<IssueComment>(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}/comments`,
      { body }
    );

    // Invalidate comments cache
    this.cache.delete(`comments-${issueNumber}`);

    this.emit('comment-added', {
      issueNumber,
      author: response.data.user.login,
    });

    return response.data;
  }

  /**
   * Add labels to an issue
   */
  async addLabels(issueNumber: number, labels: string[]): Promise<void> {
    await this.client.post(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}/labels`,
      { labels }
    );

    // Invalidate cache
    this.cache.delete(`issue-${issueNumber}`);
    this.cache.delete(`issues-`);
  }

  /**
   * Remove a label from an issue
   */
  async removeLabel(issueNumber: number, labelName: string): Promise<void> {
    await this.client.delete(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}/labels/${labelName}`
    );

    // Invalidate cache
    this.cache.delete(`issue-${issueNumber}`);
    this.cache.delete(`issues-`);
  }

  /**
   * Assign users to an issue
   */
  async assignUsers(issueNumber: number, assignees: string[]): Promise<GitHubIssue> {
    const response = await this.client.patch<GitHubIssue>(
      `/repos/${this.owner}/${this.repo}/issues/${issueNumber}`,
      { assignees }
    );

    this.cache.delete(`issue-${issueNumber}`);
    this.cache.delete(`issues-`);

    return response.data;
  }

  /**
   * Search issues
   */
  async searchIssues(query: string, limit = 30): Promise<GitHubIssue[]> {
    const searchQuery = `repo:${this.owner}/${this.repo} ${query}`;
    
    const response = await this.client.get<{ items: GitHubIssue[] }>(
      `/search/issues?q=${encodeURIComponent(searchQuery)}&per_page=${limit}`
    );

    return response.data.items;
  }

  /**
   * Get authenticated user
   */
  async getAuthenticatedUser(): Promise<any> {
    const response = await this.client.get('/user');
    return response.data;
  }

  /**
   * Validate token and repository access
   */
  async validateAccess(): Promise<boolean> {
    try {
      await this.getAuthenticatedUser();
      await this.listIssues({ per_page: 1 });
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Clear cache (useful for testing or forced refresh)
   */
  clearCache(): void {
    this.cache.clear();
  }
}

export default GitHubAPIClient;
