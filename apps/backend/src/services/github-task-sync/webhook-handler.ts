#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/webhook-handler.ts
// @module      services/github-task-sync/webhook-handler
// @description GitHub webhook event handler for real-time issue sync
// @owner       collab-9
// @status      active

import crypto from 'crypto';
import { EventEmitter } from 'events';
import { getLogger } from '../../utils/logger';

const logger = getLogger('GitHubWebhookHandler');

export interface WebhookPayload {
  action: string;
  issue?: {
    number: number;
    title: string;
    body: string;
    state: 'open' | 'closed';
    assignee?: { login: string } | null;
    labels: Array<{ name: string }>;
    created_at: string;
    updated_at: string;
    closed_at?: string | null;
    url: string;
    html_url: string;
  };
  pull_request?: any;
  repository: {
    name: string;
    full_name: string;
  };
  sender: {
    login: string;
    avatar_url: string;
  };
  created_at?: string;
}

export interface WebhookVerificationOptions {
  secret: string;
  maxAge?: number; // milliseconds (default: 5 minutes)
}

export interface WebhookEvent {
  id: string;
  timestamp: Date;
  action: string;
  issueNumber?: number;
  payload: WebhookPayload;
  signature: string;
}

/**
 * GitHub Webhook Handler
 * Verifies webhook signatures and processes GitHub events
 */
export class GitHubWebhookHandler extends EventEmitter {
  private options: WebhookVerificationOptions;

  constructor(options: WebhookVerificationOptions) {
    super();
    this.options = {
      maxAge: 5 * 60 * 1000, // 5 minutes default
      ...options,
    };
  }

  /**
   * Verify webhook signature (HMAC-SHA256)
   * GitHub sends: X-Hub-Signature-256: sha256=<signature>
   */
  verifySignature(payload: string, signature: string): boolean {
    try {
      // Extract algorithm and hash from signature header
      const [algorithm, providedHash] = signature.split('=');

      if (algorithm !== 'sha256') {
        logger.warn('Invalid webhook signature algorithm', { algorithm });
        return false;
      }

      // Calculate HMAC-SHA256 of payload
      const hash = crypto
        .createHmac('sha256', this.options.secret)
        .update(payload, 'utf-8')
        .digest('hex');

      // Constant-time comparison to prevent timing attacks
      const isValid = crypto.timingSafeEqual(
        Buffer.from(hash),
        Buffer.from(providedHash)
      );

      return isValid;
    } catch (error) {
      logger.error('Webhook signature verification error', { error });
      return false;
    }
  }

  /**
   * Process webhook event
   * Validates signature, timestamp, and event structure
   */
  async processWebhook(
    body: string,
    signature: string,
    deliveryId: string,
    deliveryTime: string
  ): Promise<WebhookEvent | null> {
    try {
      // Verify signature first
      if (!this.verifySignature(body, signature)) {
        logger.warn('Webhook signature verification failed', { deliveryId });
        this.emit('signature-invalid', { deliveryId });
        return null;
      }

      // Parse payload
      let payload: WebhookPayload;
      try {
        payload = JSON.parse(body);
      } catch (error) {
        logger.error('Failed to parse webhook payload', { error, deliveryId });
        this.emit('parse-error', { deliveryId });
        return null;
      }

      // Validate timestamp (max age check)
      const webhookTimestamp = new Date(deliveryTime).getTime();
      const currentTimestamp = Date.now();
      const age = currentTimestamp - webhookTimestamp;

      if (age > this.options.maxAge!) {
        logger.warn('Webhook timestamp too old', {
          age,
          maxAge: this.options.maxAge,
          deliveryId,
        });
        this.emit('timestamp-expired', { deliveryId, age });
        return null;
      }

      // Validate payload structure
      if (!payload.repository || !payload.action) {
        logger.warn('Invalid webhook payload structure', { deliveryId });
        this.emit('payload-invalid', { deliveryId });
        return null;
      }

      // Create webhook event
      const event: WebhookEvent = {
        id: deliveryId,
        timestamp: new Date(deliveryTime),
        action: payload.action,
        issueNumber: payload.issue?.number,
        payload,
        signature,
      };

      logger.info('Webhook received and verified', {
        deliveryId,
        action: payload.action,
        repository: payload.repository.full_name,
        issue: payload.issue?.number,
      });

      this.emit('webhook-processed', event);

      return event;
    } catch (error) {
      logger.error('Unexpected error in webhook processing', { error });
      this.emit('processing-error', { error, deliveryId });
      return null;
    }
  }

  /**
   * Filter webhook events to only handle issue-related events
   */
  isIssueEvent(event: WebhookEvent): boolean {
    const issueActions = [
      'opened',
      'closed',
      'reopened',
      'edited',
      'assigned',
      'unassigned',
      'labeled',
      'unlabeled',
    ];

    return (
      event.payload.issue !== undefined &&
      issueActions.includes(event.action)
    );
  }

  /**
   * Extract issue changes from webhook event
   */
  extractIssueChanges(event: WebhookEvent): {
    issueNumber: number;
    action: string;
    changes: Record<string, any>;
  } | null {
    if (!event.payload.issue) {
      return null;
    }

    const changes: Record<string, any> = {};

    // Determine what changed based on action
    switch (event.action) {
      case 'opened':
        changes.created = true;
        break;

      case 'closed':
      case 'reopened':
        changes.state = event.payload.issue.state;
        break;

      case 'edited':
        // For edited events, check what fields changed
        changes.title = event.payload.issue.title;
        changes.description = event.payload.issue.body;
        break;

      case 'assigned':
        changes.assignees = event.payload.issue.assignee
          ? [event.payload.issue.assignee.login]
          : [];
        break;

      case 'unassigned':
        changes.assignees = [];
        break;

      case 'labeled':
        changes.labels = event.payload.issue.labels.map((l) => l.name);
        break;

      case 'unlabeled':
        changes.labels = event.payload.issue.labels.map((l) => l.name);
        break;
    }

    return {
      issueNumber: event.payload.issue.number,
      action: event.action,
      changes,
    };
  }

  /**
   * Validate webhook secret format
   */
  static validateSecretFormat(secret: string): boolean {
    // GitHub webhook secrets should be strings
    return typeof secret === 'string' && secret.length > 0;
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.removeAllListeners();
  }
}

/**
 * Webhook signature header name
 */
export const WEBHOOK_SIGNATURE_HEADER = 'X-Hub-Signature-256';

/**
 * Webhook delivery ID header name
 */
export const WEBHOOK_DELIVERY_ID_HEADER = 'X-GitHub-Delivery';

/**
 * Webhook timestamp header name
 */
export const WEBHOOK_DELIVERY_TIME_HEADER = 'X-GitHub-Hook-Installation-Target-ID';

export default GitHubWebhookHandler;