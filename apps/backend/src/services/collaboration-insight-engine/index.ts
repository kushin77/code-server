#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight-engine/index.ts
// @module      collaboration/collaboration-insight-engine
// @description Service exports and factory functions
// @owner       collab-services
// @status      active

import { CollaborationInsightEngine, createCollaborationInsightEngine } from './collaboration-insight-engine';
import type { CollaborationInsightEngineConfig } from './types';

let instance: CollaborationInsightEngine | null = null;

/**
 * Create a new service instance
 */
export function create(
  config?: Partial<CollaborationInsightEngineConfig>,
): CollaborationInsightEngine {
  return new CollaborationInsightEngine(config);
}

/**
 * Get or create singleton instance
 */
export function getInstance(
  config?: Partial<CollaborationInsightEngineConfig>,
): CollaborationInsightEngine {
  if (!instance) {
    instance = createCollaborationInsightEngine(config);
  }
  return instance;
}

/**
 * Shutdown singleton instance
 */
export function shutdown(): void {
  if (instance) {
    instance.shutdown();
    instance = null;
  }
}

// Export service class and factory
export { CollaborationInsightEngine, createCollaborationInsightEngine };
export type * from './types';
