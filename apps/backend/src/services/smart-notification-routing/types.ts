#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/types.ts
// @module      collaboration/smart-notification-routing
// @description Type definitions for smart notification routing service
// @owner       collab-4.6
// @status      active

/**
 * User presence state
 * - 'online': User is actively using the IDE
 * - 'away': User is away from the IDE (no activity for N minutes)
 * - 'in-meeting': Calendar indicates user is in a meeting
 * - 'dnd': Do-not-disturb mode enabled by user
 * - 'offline': User not connected
 * - 'coding': User actively editing code (focus mode)
 */
export type Presence = 'online' | 'away' | 'in-meeting' | 'dnd' | 'offline' | 'coding';

/**
 * User physical/logical location context
 */
export type Location = 'office' | 'meeting-room' | 'remote' | 'travel' | 'unknown';

/**
 * Device context (where user is accessing the system)
 */
export type Device = 'ide' | 'mobile' | 'web' | 'desktop' | 'unknown';

/**
 * Calendar status from integrated calendar system
 */
export type CalendarStatus = 'busy' | 'free' | 'in-meeting' | 'unknown' | 'unavailable';

/**
 * Event priority level for routing decisions
 * - 'critical': Must deliver immediately (e.g., blocking issue, @mention with urgent tag)
 * - 'high': Deliver soon (e.g., direct @mention)
 * - 'normal': Standard notification (e.g., activity, comments)
 * - 'low': Batch with other low-priority items (e.g., async activity)
 */
export type EventPriority = 'critical' | 'high' | 'normal' | 'low';

/**
 * Collaboration event type
 */
export type EventType = 'mention' | 'comment' | 'activity' | 'share' | 'edit' | 'review' | 'blocked';

/**
 * User status context including presence, location, device, and calendar
 * @see UserStatusContext for optional additional metadata
 */
export interface UserStatus {
  id: string;
  userId: string;
  presence: Presence;
  location?: Location;
  currentDevice?: Device;
  calendarStatus?: CalendarStatus;
  lastActivity: Date;
  updatedAt: Date;
}

/**
 * Optional context metadata when updating user status
 * Allows callers to provide richer context without modifying core UserStatus
 */
export interface UserStatusContext {
  location?: string;
  currentDevice?: string;
  calendarStatus?: string;
  metadata?: Record<string, any>;
}

/**
 * Collaboration event to be routed to one or more users
 */
export interface CollaborationEvent {
  id: string;
  type: EventType;
  priority: EventPriority;
  userId: string;
  targetUsers?: string[];
  context: Record<string, any>;
  timestamp: Date;
  message: string;
}

/**
 * Result of routing an event to users
 * Indicates which users received immediate notification vs deferred/suppressed
 */
export interface RoutingResult {
  eventId: string;
  routed: string[];      // Users who received immediate notification
  deferred: string[];    // Users receiving batched notification later
  suppressed: string[];  // Users in DND/offline
  total: number;
  timestamp: Date;
}

/**
 * Result of batch delivery processing (processing deferred queue)
 */
export interface BatchDeliveryResult {
  batchId: string;
  processed: number;
  failed: number;
  skipped: number;
  timestamp: Date;
}

/**
 * Configuration for routing behavior per presence state
 * Allows customization of how events are handled for different user states
 */
export interface RoutingPolicy {
  presence: Presence;
  criticalDelay?: number;      // Delay in ms for critical events (0 = immediate)
  highDelay?: number;          // Delay in ms for high priority events
  normalDelay?: number;        // Delay in ms for normal priority
  lowDelay?: number;           // Delay in ms for low priority
  batchSize?: number;          // Max notifications to batch together
  deliverDevices?: Device[];   // Which devices to notify
}

/**
 * Delivery method and timing for a notification
 */
export interface DeliveryPlan {
  userId: string;
  deliveryTime: Date;
  method: 'immediate' | 'batch' | 'suppress';
  devices: Device[];
  reason: string;
}

/**
 * Statistics for monitoring routing performance
 */
export interface RoutingMetrics {
  totalEvents: number;
  routedCount: number;
  deferredCount: number;
  suppressedCount: number;
  avgDeliveryDelay: number;
  batchSize: number;
  timestamp: Date;
}
