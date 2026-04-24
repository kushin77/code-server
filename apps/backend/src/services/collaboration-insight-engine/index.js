#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight-engine/index.ts
// @module      collaboration/collaboration-insight-engine
// @description Service exports and factory functions
// @owner       collab-services
// @status      active
import { CollaborationInsightEngine, createCollaborationInsightEngine } from './collaboration-insight-engine';
let instance = null;
/**
 * Create a new service instance
 */
export function create(config) {
    return new CollaborationInsightEngine(config);
}
/**
 * Get or create singleton instance
 */
export function getInstance(config) {
    if (!instance) {
        instance = createCollaborationInsightEngine(config);
    }
    return instance;
}
/**
 * Shutdown singleton instance
 */
export function shutdown() {
    if (instance) {
        instance.shutdown();
        instance = null;
    }
}
// Export service class and factory
export { CollaborationInsightEngine, createCollaborationInsightEngine };
//# sourceMappingURL=index.js.map