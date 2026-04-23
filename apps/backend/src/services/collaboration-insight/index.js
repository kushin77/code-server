#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-insight/index.ts
// @module      collaboration/insight
// @description Exports for CollaborationInsightEngine
// @owner       collab-6.2
// @status      active
export { CollaborationInsightEngine } from './collaboration-insight-engine';
/**
 * Factory function to create and initialize CollaborationInsightEngine
 */
export async function createCollaborationInsightEngine(config) {
    const engine = new CollaborationInsightEngine(config);
    await engine.initialize();
    return engine;
}
//# sourceMappingURL=index.js.map