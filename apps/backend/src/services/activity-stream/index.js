#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/index.ts
// @module      collaboration/activity-stream
// @description Exports for ActivityStreamService
// @owner       collab-6.2
// @status      active
export { ActivityStreamService } from './activity-stream-service';
export { ActivityType } from './types';
/**
 * Factory function to create and initialize ActivityStreamService
 */
export async function createActivityStreamService(config) {
    const service = new ActivityStreamService(config);
    await service.initialize();
    return service;
}
//# sourceMappingURL=index.js.map