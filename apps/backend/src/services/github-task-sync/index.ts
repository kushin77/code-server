#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/index.ts
// @module      services/github-task-sync
// @description Bidirectional GitHub issue sync service for IDE task integration
// @owner       collab-9
// @status      active

import { EventEmitter } from 'events';
import { GitHubAPIClient, GitHubIssue, CreateIssueInput, UpdateIssueInput } from './github-api-client';
import { getLogger } from '../../lib/logger';

const logger = getLogger('GitHubTaskSyncService');

export interface TaskRecord {
  id: string;
  issueNumber: number;
  title: string;
  description: string;
  state: 'open' | 'closed';
  assignees: string[];
  labels: string[];
  lastSyncAt: Date;
  lastModifiedAt: Date;
  gitHubUrl: string;
}

export interface SyncResult {
  synced: number;
  created: number;
  updated: number;
  deleted: number;
  errors: Array<{ issue: number; error: string }>;
}

export interface ConflictResolution {
  strategy: 'github-wins' | 'ide-wins' | 'manual';
  reason?: string;
}

/**
 * GitHub Task Sync Service
 * 
 * Provides bidirectional synchronization between GitHub issues and IDE task panel:
 * - Fetch issues from GitHub
 * - Create new issues from IDE
 * - Update issues from IDE (title, description, state, labels, assignees)
 * - Conflict resolution (last-write-wins for simple fields)
 * - Real-time polling for changes
 * - Event emission for UI updates
 */
export class GitHubTaskSyncService extends EventEmitter {
  private apiClient: GitHubAPIClient;
  private localTasks: Map<number, TaskRecord> = new Map();
  private syncInProgress = false;
  private pollingInterval: NodeJS.Timeout | null = null;
  private lastSyncTime = 0;
  private conflictLog: Array<any> = [];

  constructor(private config: {
    githubToken: string;
    owner: string;
    repo: string;
    pollingIntervalMs?: number;
  }) {
    super();

    this.apiClient = new GitHubAPIClient(
      config.githubToken,
      config.owner,
      config.repo
    );

    // Relay API client events
    this.apiClient.on('rate-limited', (data) => {
      logger.warn('GitHub API rate limit approaching', data);
      this.emit('rate-limited', data);
    });

    this.apiClient.on('issue-created', (data) => {
      logger.info(`Issue created: #${data.issueNumber}`);
      this.emit('issue-created', data);
    });

    this.apiClient.on('issue-updated', (data) => {
      logger.info(`Issue updated: #${data.issueNumber}`);
      this.emit('issue-updated', data);
    });
  }

  /**
   * Initialize the service and start polling
   */
  async initialize(): Promise<void> {
    try {
      const isValid = await this.apiClient.validateAccess();
      if (!isValid) {
        throw new Error('Invalid GitHub token or repo access');
      }

      logger.info('GitHub Task Sync service initialized');
      this.emit('initialized', { owner: this.config.owner, repo: this.config.repo });
    } catch (error) {
      logger.error('Failed to initialize GitHub Task Sync service', error);
      throw error;
    }
  }

  /**
   * Start polling for changes (default: every 30 seconds)
   */
  startPolling(): void {
    if (this.pollingInterval) {
      logger.warn('Polling already started');
      return;
    }

    const interval = this.config.pollingIntervalMs || 30000;

    this.pollingInterval = setInterval(async () => {
      try {
        await this.syncFromGitHub();
      } catch (error) {
        logger.error('Polling sync error', error);
        this.emit('sync-error', error);
      }
    }, interval);

    logger.info(`Started polling every ${interval}ms`);
    this.emit('polling-started', { intervalMs: interval });
  }

  /**
   * Stop polling for changes
   */
  stopPolling(): void {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
      this.pollingInterval = null;
      logger.info('Stopped polling');
      this.emit('polling-stopped', {});
    }
  }

  /**
   * Sync issues from GitHub to local cache
   */
  async syncFromGitHub(filters?: {
    state?: 'open' | 'closed' | 'all';
    labels?: string[];
  }): Promise<SyncResult> {
    if (this.syncInProgress) {
      logger.debug('Sync already in progress, skipping');
      return { synced: 0, created: 0, updated: 0, deleted: 0, errors: [] };
    }

    this.syncInProgress = true;

    try {
      logger.info('Starting sync from GitHub', filters);
      const result: SyncResult = {
        synced: 0,
        created: 0,
        updated: 0,
        deleted: 0,
        errors: [],
      };

      // Fetch issues from GitHub
      const gitHubIssues = await this.apiClient.listIssues({
        state: filters?.state || 'all',
        labels: filters?.labels,
        per_page: 100,
      });

      logger.info(`Fetched ${gitHubIssues.length} issues from GitHub`);

      // Update local cache
      for (const issue of gitHubIssues) {
        try {
          const taskRecord = this.convertGitHubIssueToTask(issue);
          
          const existingTask = this.localTasks.get(issue.number);
          if (existingTask) {
            // Check for conflicts
            if (existingTask.lastModifiedAt > new Date(issue.updated_at)) {
              logger.warn(`Conflict detected for issue #${issue.number}: local modified after GitHub`);
              this.recordConflict(issue.number, 'github-vs-local', existingTask, taskRecord);
              result.created++;
            } else {
              this.localTasks.set(issue.number, taskRecord);
              result.updated++;
            }
          } else {
            this.localTasks.set(issue.number, taskRecord);
            result.created++;
          }

          result.synced++;
        } catch (error: any) {
          logger.error(`Error syncing issue #${issue.number}`, error);
          result.errors.push({
            issue: issue.number,
            error: error.message,
          });
        }
      }

      this.lastSyncTime = Date.now();

      logger.info('Sync from GitHub complete', {
        synced: result.synced,
        created: result.created,
        updated: result.updated,
        errors: result.errors.length,
      });

      this.emit('sync-complete', result);
      return result;
    } finally {
      this.syncInProgress = false;
    }
  }

  /**
   * Create a new GitHub issue from IDE
   */
  async createIssueFromIDE(input: CreateIssueInput): Promise<TaskRecord> {
    logger.info('Creating issue from IDE', { title: input.title });

    const gitHubIssue = await this.apiClient.createIssue(input);
    const taskRecord = this.convertGitHubIssueToTask(gitHubIssue);

    this.localTasks.set(gitHubIssue.number, taskRecord);

    logger.info(`Issue created: #${gitHubIssue.number}`);
    this.emit('issue-created-from-ide', { issueNumber: gitHubIssue.number });

    return taskRecord;
  }

  /**
   * Update a GitHub issue from IDE
   */
  async updateIssueFromIDE(issueNumber: number, input: UpdateIssueInput): Promise<TaskRecord> {
    logger.info('Updating issue from IDE', { issueNumber, title: input.title });

    const gitHubIssue = await this.apiClient.updateIssue(issueNumber, input);
    const taskRecord = this.convertGitHubIssueToTask(gitHubIssue);

    this.localTasks.set(issueNumber, taskRecord);

    logger.info(`Issue updated: #${issueNumber}`);
    this.emit('issue-updated-from-ide', { issueNumber });

    return taskRecord;
  }

  /**
   * Close an issue from IDE
   */
  async closeIssueFromIDE(issueNumber: number, reason?: string): Promise<TaskRecord> {
    logger.info('Closing issue from IDE', { issueNumber });

    const gitHubIssue = await this.apiClient.closeIssue(issueNumber, reason);
    const taskRecord = this.convertGitHubIssueToTask(gitHubIssue);

    this.localTasks.set(issueNumber, taskRecord);

    logger.info(`Issue closed: #${issueNumber}`);
    this.emit('issue-closed-from-ide', { issueNumber });

    return taskRecord;
  }

  /**
   * Reopen an issue from IDE
   */
  async reopenIssueFromIDE(issueNumber: number): Promise<TaskRecord> {
    logger.info('Reopening issue from IDE', { issueNumber });

    const gitHubIssue = await this.apiClient.reopenIssue(issueNumber);
    const taskRecord = this.convertGitHubIssueToTask(gitHubIssue);

    this.localTasks.set(issueNumber, taskRecord);

    logger.info(`Issue reopened: #${issueNumber}`);
    this.emit('issue-reopened-from-ide', { issueNumber });

    return taskRecord;
  }

  /**
   * Get a task by issue number
   */
  getTask(issueNumber: number): TaskRecord | undefined {
    return this.localTasks.get(issueNumber);
  }

  /**
   * Get all tasks
   */
  getAllTasks(): TaskRecord[] {
    return Array.from(this.localTasks.values());
  }

  /**
   * Get open tasks
   */
  getOpenTasks(): TaskRecord[] {
    return this.getAllTasks().filter((t) => t.state === 'open');
  }

  /**
   * Get closed tasks
   */
  getClosedTasks(): TaskRecord[] {
    return this.getAllTasks().filter((t) => t.state === 'closed');
  }

  /**
   * Get sync status
   */
  getSyncStatus(): {
    lastSyncTime: number;
    totalTasks: number;
    openTasks: number;
    closedTasks: number;
    conflictCount: number;
  } {
    return {
      lastSyncTime: this.lastSyncTime,
      totalTasks: this.localTasks.size,
      openTasks: this.getOpenTasks().length,
      closedTasks: this.getClosedTasks().length,
      conflictCount: this.conflictLog.length,
    };
  }

  /**
   * Convert GitHub issue to task record
   */
  private convertGitHubIssueToTask(issue: GitHubIssue): TaskRecord {
    return {
      id: `github-${issue.number}`,
      issueNumber: issue.number,
      title: issue.title,
      description: issue.body,
      state: issue.state as 'open' | 'closed',
      assignees: issue.assignee ? [issue.assignee.login] : [],
      labels: issue.labels.map((l) => l.name),
      lastSyncAt: new Date(),
      lastModifiedAt: new Date(issue.updated_at),
      gitHubUrl: issue.html_url,
    };
  }

  /**
   * Record a conflict for audit trail
   */
  private recordConflict(
    issueNumber: number,
    type: string,
    local: TaskRecord,
    remote: TaskRecord
  ): void {
    this.conflictLog.push({
      timestamp: new Date(),
      issueNumber,
      type,
      local,
      remote,
    });

    logger.warn(`Conflict recorded for issue #${issueNumber}:${type}`);
  }

  /**
   * Get conflict log
   */
  getConflictLog(): Array<any> {
    return [...this.conflictLog];
  }

  /**
   * Clear conflict log
   */
  clearConflictLog(): void {
    this.conflictLog = [];
  }

  /**
   * Health check
   */
  async healthCheck(): Promise<{ status: string; details: any }> {
    try {
      const user = await this.apiClient.getAuthenticatedUser();
      const syncStatus = this.getSyncStatus();

      return {
        status: 'healthy',
        details: {
          authenticatedAs: user.login,
          ...syncStatus,
        },
      };
    } catch (error: any) {
      return {
        status: 'unhealthy',
        details: { error: error.message },
      };
    }
  }
}

export default GitHubTaskSyncService;
