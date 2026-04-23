#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/index.ts
// @module      collaboration/smart-notification-routing
// @description Service exports and factory functions
// @owner       collab-services
// @status      active

import { SmartNotificationRoutingService, createSmartNotificationRoutingService } from './smart-notification-routing-service';
import type { SmartNotificationRoutingConfig } from './types';

let instance: SmartNotificationRoutingService | null = null;

/**
 * Create a new service instance
 */
export function createSmartNotificationRouting(
  config?: Partial<SmartNotificationRoutingConfig>,
): SmartNotificationRoutingService {
  return new SmartNotificationRoutingService(config);
}

/**
 * Get or create singleton instance
 */
export function getSmartNotificationRoutingService(
  config?: Partial<SmartNotificationRoutingConfig>,
): SmartNotificationRoutingService {
  if (!instance) {
    instance = createSmartNotificationRouting(config);
  }
  return instance;
}

/**
 * Shutdown singleton instance
 */
export function shutdownSmartNotificationRoutingService(): void {
  if (instance) {
    instance.shutdown();
    instance = null;
  }
}

// Export service class and factory
export { SmartNotificationRoutingService, createSmartNotificationRoutingService };
export type { SmartNotificationRoutingConfig } from './types';

// Export all types
export type {
  NotificationRoute,
  EscalationLevel,
  DeliveryStatus,
  ChannelPreference,
  EscalationPolicy,
  RoutingContext,
  RoutingDecision,
  DeliveryAck,
  DeliveryRecord,
  ChannelStatus,
  RoutingMetrics,
  BatchDeliveryWindow,
  ChannelConfig,
  RoutingPolicyConfig,
} from './types';
