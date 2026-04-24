#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization-engine/index.ts
// @module      collaboration/communication-optimization-engine
// @description Service exports and factory functions
// @owner       collab-services
// @status      active

import { CommunicationOptimizationEngine, createCommunicationOptimizationEngine } from './communication-optimization-engine';
import type { CommunicationOptimizationEngineConfig } from './types';

let instance: CommunicationOptimizationEngine | null = null;

/**
 * Create a new service instance
 */
export function create(
  config?: Partial<CommunicationOptimizationEngineConfig>,
): CommunicationOptimizationEngine {
  return new CommunicationOptimizationEngine(config);
}

/**
 * Get or create singleton instance
 */
export function getInstance(
  config?: Partial<CommunicationOptimizationEngineConfig>,
): CommunicationOptimizationEngine {
  if (!instance) {
    instance = createCommunicationOptimizationEngine(config);
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
export { CommunicationOptimizationEngine, createCommunicationOptimizationEngine };
export type * from './types';
