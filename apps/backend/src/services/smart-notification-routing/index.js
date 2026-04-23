#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/index.ts
// @module      collaboration/smart-notification-routing
// @description Service exports and factory functions
// @owner       collab-services
// @status      active
import { SmartNotificationRoutingService, createSmartNotificationRoutingService } from './smart-notification-routing-service';
let instance = null;
/**
 * Create a new service instance
 */
export function createSmartNotificationRouting(config) {
    return new SmartNotificationRoutingService(config);
}
/**
 * Get or create singleton instance
 */
export function getSmartNotificationRoutingService(config) {
    if (!instance) {
        instance = createSmartNotificationRouting(config);
    }
    return instance;
}
/**
 * Shutdown singleton instance
 */
export function shutdownSmartNotificationRoutingService() {
    if (instance) {
        instance.shutdown();
        instance = null;
    }
}
// Export service class and factory
export { SmartNotificationRoutingService, createSmartNotificationRoutingService };
//# sourceMappingURL=index.js.map