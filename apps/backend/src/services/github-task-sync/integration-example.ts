#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/integration-example.ts
// @module      services/github-task-sync/integration-example
// @description Example integration of GitHub task sync with Express
// @owner       collab-9
// @status      active

import express, { Express } from 'express';
import { GitHubTaskSyncService } from './index';
import { initializeGitHubTaskSyncRoutes } from '../../routes/github-task-sync';

/**
 * Create example Express app with GitHub task sync integration
 */
export function createGitHubTaskSyncExampleApp(): Express {
  const app = express();

  // Middleware
  app.use(express.json());

  // Initialize service
  const service = new GitHubTaskSyncService({
    githubToken: process.env.GITHUB_TOKEN || 'test-token',
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
    pollingIntervalMs: 30000, // 30 seconds
  });

  // Mount routes
  app.use('/api/github-task-sync', initializeGitHubTaskSyncRoutes(service));

  // Example route for testing
  app.get('/', (req, res) => {
    res.json({
      service: 'GitHub Task Sync Example',
      endpoints: {
        'GET /api/github-task-sync/issues': 'List all issues',
        'GET /api/github-task-sync/issues/:issueNumber': 'Get single issue',
        'POST /api/github-task-sync/issues': 'Create new issue',
        'PATCH /api/github-task-sync/issues/:issueNumber': 'Update issue',
        'POST /api/github-task-sync/issues/:issueNumber/close': 'Close issue',
        'POST /api/github-task-sync/issues/:issueNumber/reopen': 'Reopen issue',
        'POST /api/github-task-sync/sync': 'Manual sync from GitHub',
        'GET /api/github-task-sync/status': 'Get sync status',
        'GET /api/github-task-sync/conflicts': 'View conflicts',
        'DELETE /api/github-task-sync/conflicts': 'Clear conflicts',
        'GET /api/github-task-sync/health': 'Health check',
      },
    });
  });

  // Service event listeners
  service.on('initialized', (data) => {
    console.log('[GitHub Task Sync] Service initialized', data);
  });

  service.on('sync-complete', (result) => {
    console.log('[GitHub Task Sync] Sync complete', {
      synced: result.synced,
      created: result.created,
      updated: result.updated,
      errors: result.errors.length,
    });
  });

  service.on('issue-created-from-ide', (data) => {
    console.log('[GitHub Task Sync] Issue created from IDE', data);
  });

  service.on('issue-updated-from-ide', (data) => {
    console.log('[GitHub Task Sync] Issue updated from IDE', data);
  });

  service.on('sync-error', (error) => {
    console.error('[GitHub Task Sync] Sync error', error);
  });

  return app;
}

/**
 * Setup and run example app
 */
export async function setupGitHubTaskSyncIntegration(): Promise<GitHubTaskSyncService> {
  const app = createGitHubTaskSyncExampleApp();
  const PORT = process.env.PORT || 3009;

  // Initialize and start service
  const service = new GitHubTaskSyncService({
    githubToken: process.env.GITHUB_TOKEN || 'test-token',
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
    pollingIntervalMs: 30000,
  });

  await service.initialize();
  service.startPolling();

  // Start Express server
  app.listen(PORT, () => {
    console.log(`[GitHub Task Sync] Listening on port ${PORT}`);
    console.log(`[GitHub Task Sync] Documentation:`);
    console.log(`  - GET http://localhost:${PORT}/`);
    console.log(`[GitHub Task Sync] Polling started every 30 seconds`);
  });

  return service;
}

/**
 * Initialize GitHub task sync routes in existing Express app
 */
export function initializeGitHubTaskSyncInApp(
  app: Express,
  service: GitHubTaskSyncService
): void {
  app.use('/api/github-task-sync', initializeGitHubTaskSyncRoutes(service));

  console.log('[GitHub Task Sync] Routes initialized');
}

// Example usage in main.ts
export async function initializeGitHubTaskSyncRuntime(): Promise<{
  service: GitHubTaskSyncService;
  routes: any;
}> {
  const service = new GitHubTaskSyncService({
    githubToken: process.env.GITHUB_TOKEN || 'test-token',
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
    pollingIntervalMs: 30000,
  });

  await service.initialize();

  // Optionally start polling
  if (process.env.ENABLE_GITHUB_POLLING === 'true') {
    service.startPolling();
    console.log('[GitHub Task Sync] Polling enabled');
  }

  const routes = initializeGitHubTaskSyncRoutes(service);

  return { service, routes };
}

export default {
  createGitHubTaskSyncExampleApp,
  setupGitHubTaskSyncIntegration,
  initializeGitHubTaskSyncInApp,
  initializeGitHubTaskSyncRuntime,
};
