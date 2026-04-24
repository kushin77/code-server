#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/integration-example.ts
// @module      services/github-task-sync/integration-example
// @description Example integration of GitHub task sync with Express
// @owner       collab-9
// @status      active

import express, { Express } from 'express';
import http from 'http';
import { GitHubTaskSyncService } from './index';
import { initializeGitHubTaskSyncRoutes } from '../../routes/github-task-sync';
import { GitHubWebhookHandler } from './webhook-handler';
import WebSocketBroadcaster from './websocket-broadcast';
import WebSocketManager from './websocket-manager';

/**
 * Create example Express app with GitHub task sync integration
 */
export function createGitHubTaskSyncExampleApp(
  httpServer?: http.Server
): Express {
  const app = express();

  // Middleware
  app.use(express.json({ limit: '10mb' })); // Increase body size for GitHub webhooks

  // Initialize service
  const service = new GitHubTaskSyncService({
    githubToken: process.env.GITHUB_TOKEN || 'test-token',
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
    pollingIntervalMs: 30000, // 30 seconds
  });

  // Initialize webhook handler (Phase 2: Real-time GitHub webhooks)
  const webhookSecret = process.env.GITHUB_WEBHOOK_SECRET || 'test-secret';
  const webhookHandler = new GitHubWebhookHandler({ secret: webhookSecret });
  service.setWebhookHandler(webhookHandler);

  // Initialize WebSocket infrastructure (Phase 2: Real-time IDE updates)
  if (httpServer) {
    const broadcaster = new WebSocketBroadcaster(httpServer);
    service.setBroadcaster(broadcaster);

    const wsManager = new WebSocketManager();
    wsManager.attach(httpServer);
    service.setWebhookHandler(webhookHandler);

    console.log('[GitHub Task Sync] WebSocket broadcaster initialized');
    console.log('[GitHub Task Sync] WebSocket manager initialized on /ws/task-sync');
  }

  // Mount routes
  app.use('/api/github-task-sync', initializeGitHubTaskSyncRoutes(service));

  // Example route for testing
  app.get('/', (req, res) => {
    res.json({
      service: 'GitHub Task Sync Example',
      phase: 'Phase 1 (polling) + Phase 2 (webhooks)',
      endpoints: {
        'GET /api/github-task-sync/issues': 'List all issues',
        'GET /api/github-task-sync/issues/:issueNumber': 'Get single issue',
        'POST /api/github-task-sync/issues': 'Create new issue',
        'PATCH /api/github-task-sync/issues/:issueNumber': 'Update issue',
        'POST /api/github-task-sync/issues/:issueNumber/close': 'Close issue',
        'POST /api/github-task-sync/issues/:issueNumber/reopen': 'Reopen issue',
        'POST /api/github-task-sync/webhook': 'GitHub webhook receiver (Phase 2)',
        'POST /api/github-task-sync/sync': 'Manual sync from GitHub',
        'GET /api/github-task-sync/status': 'Get sync status',
        'GET /api/github-task-sync/conflicts': 'View conflicts',
        'DELETE /api/github-task-sync/conflicts': 'Clear conflicts',
        'GET /api/github-task-sync/health': 'Health check',
      },
      websocket: {
        path: '/ws/task-sync',
        description: 'Real-time task sync via WebSocket (Phase 2)',
        auth: 'Required - send auth message with token and userId',
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

  service.on('webhook-processed', (data) => {
    console.log('[GitHub Task Sync] Webhook processed', data);
  });

  service.on('sync-error', (error) => {
    console.error('[GitHub Task Sync] Sync error', error);
  });

  // Webhook handler event listeners
  webhookHandler.on('webhook-processed', (event) => {
    console.log('[GitHub Task Sync] Webhook received and verified', {
      deliveryId: event.id,
      action: event.action,
      issue: event.issueNumber,
    });
  });

  webhookHandler.on('signature-invalid', (data) => {
    console.warn('[GitHub Task Sync] Webhook signature invalid', data);
  });

  webhookHandler.on('timestamp-expired', (data) => {
    console.warn('[GitHub Task Sync] Webhook timestamp expired', data);
  });

  return app;
}

/**
 * Setup and run example app with full Phase 2 integration
 */
export async function setupGitHubTaskSyncIntegration(): Promise<{ app: Express; service: GitHubTaskSyncService }> {
  const httpServer = new http.Server();
  const app = createGitHubTaskSyncExampleApp(httpServer);
  const PORT = process.env.PORT || 3009;

  // Initialize and start service
  const service = new GitHubTaskSyncService({
    githubToken: process.env.GITHUB_TOKEN || 'test-token',
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
    pollingIntervalMs: 30000,
  });

  await service.initialize();

  // Start polling (Phase 1 - fallback/redundancy)
  service.startPolling();

  // Attach HTTP server to app for WebSocket support
  httpServer.on('request', app);

  // Start HTTP server
  httpServer.listen(PORT, () => {
    console.log(`[GitHub Task Sync] Listening on http://localhost:${PORT}`);
    console.log(`[GitHub Task Sync] Phase 1 (polling): Every 30 seconds`);
    console.log(`[GitHub Task Sync] Phase 2 (webhooks): POST http://localhost:${PORT}/api/github-task-sync/webhook`);
    console.log(`[GitHub Task Sync] Phase 2 (WebSocket): ws://localhost:${PORT}/ws/task-sync`);
    console.log(`[GitHub Task Sync] Documentation: GET http://localhost:${PORT}/`);
  });

  return { app, service };
}

/**
 * Initialize GitHub task sync routes in existing Express app
 */
export function initializeGitHubTaskSyncInApp(
  app: Express,
  service: GitHubTaskSyncService,
  httpServer?: http.Server
): void {
  // Initialize webhook handler
  const webhookSecret = process.env.GITHUB_WEBHOOK_SECRET || 'test-secret';
  const webhookHandler = new GitHubWebhookHandler({ secret: webhookSecret });
  service.setWebhookHandler(webhookHandler);

  // Initialize WebSocket infrastructure if HTTP server provided
  if (httpServer) {
    const broadcaster = new WebSocketBroadcaster(httpServer);
    service.setBroadcaster(broadcaster);

    const wsManager = new WebSocketManager();
    wsManager.attach(httpServer);

    console.log('[GitHub Task Sync] WebSocket broadcaster initialized');
    console.log('[GitHub Task Sync] WebSocket manager initialized on /ws/task-sync');
  }

  app.use('/api/github-task-sync', initializeGitHubTaskSyncRoutes(service));

  console.log('[GitHub Task Sync] Routes initialized');
  console.log('[GitHub Task Sync] Webhook endpoint ready at POST /api/github-task-sync/webhook');
}

/**
 * Initialize GitHub task sync runtime (for main application)
 */
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

  // Initialize webhook handler for Phase 2
  const webhookSecret = process.env.GITHUB_WEBHOOK_SECRET || 'test-secret';
  const webhookHandler = new GitHubWebhookHandler({ secret: webhookSecret });
  service.setWebhookHandler(webhookHandler);

  // Start polling (Phase 1 - fallback/redundancy)
  if (process.env.ENABLE_GITHUB_POLLING !== 'false') {
    service.startPolling();
    console.log('[GitHub Task Sync] Polling enabled (Phase 1)');
  }

  console.log('[GitHub Task Sync] Webhook handler ready (Phase 2)');

  const routes = initializeGitHubTaskSyncRoutes(service);

  return { service, routes };
}

export default {
  createGitHubTaskSyncExampleApp,
  setupGitHubTaskSyncIntegration,
  initializeGitHubTaskSyncInApp,
  initializeGitHubTaskSyncRuntime,
};
