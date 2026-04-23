#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/types.ts
// @module      collaboration/smart-notification-routing
// @description Type definitions for smart notification routing service
// @owner       collab-6.2
// @status      active

/**
 * Notification delivery channel
 */
export type NotificationRoute = 'in-app' | 'email' | 'slack' | 'sms' | 'push';

/**
 * Stored user-facing status for routing and presence updates
 */
export type UserStatus = 'online' | 'away' | 'busy' | 'dnd' | 'offline';

/**
 * Normalized routing status snapshot
 */
export interface UserStatusInfo {
  userId: string;
  currentStatus: UserStatus;
  calendarStatus?: string;
  location?: string;
  currentDevice?: 'ide' | 'mobile' | 'desktop' | 'unknown';
  meetingModeActive: boolean;
  lastStatusChange: Date;
}

/**
 * Escalation level for notification delivery
 */
export type EscalationLevel = 1 | 2 | 3 | 4 | 5;

/**
 * Delivery status
 */
export type DeliveryStatus = 'pending' | 'sent' | 'delivered' | 'failed' | 'acknowledged';

/**
 * User's channel preferences
 */
export interface ChannelPreference {
  userId: string;
  preferredChannels: NotificationRoute[];
  channelPriority: Partial<Record<NotificationRoute, number>>; // 1-5, higher = preferred
  doNotDisturb: {
    enabled: boolean;
    startTime?: string; // HH:MM format
    endTime?: string;
    timezone?: string;
  };
  quietHours?: {
    enabled: boolean;
    startTime: string;
    endTime: string;
    timezone: string;
  };
  focusTimeExclusion: boolean; // Suppress notifications during focus time
  meetingModeExclusion: boolean; // Suppress during meetings
  channelOptOuts: NotificationRoute[];
  batchPreference?: {
    enabled: boolean;
    windowMinutes: number; // Group notifications into windows
  };
  escalationPolicy: EscalationPolicy;
}

/**
 * Escalation policy for notification delivery
 */
export interface EscalationPolicy {
  policyId: string;
  userId: string;
  levels: EscalationLevel[];
  levelRoutes: Record<EscalationLevel, NotificationRoute[]>;
  levelDelays: Record<EscalationLevel, number>; // milliseconds
  enableForPriority: string[]; // P0, P1, P2 etc
  maxEscalationLevel: EscalationLevel;
  criteriaForEscalation?: {
    noAcknowledgeTimeout?: number; // ms
    noReadTimeout?: number; // ms
    failedDeliveryRetries?: number;
  };
}

/**
 * Routing context for making delivery decisions
 */
export interface RoutingContext {
  userId: string;
  notificationId: string;
  notificationType: string;
  priority: string; // P0, P1, P2, P3
  timestamp: Date;
  readinessLevel: 'available' | 'busy' | 'away' | 'offline';
  isInFocusTime: boolean;
  isInMeeting: boolean;
  deviceAvailability: {
    hasDesktopClient: boolean;
    hasWebClient: boolean;
    hasMobileApp: boolean;
    lastActiveChannel?: NotificationRoute;
    lastActiveTime?: Date;
  };
  conversationContext?: {
    threadId: string;
    urgency: 'routine' | 'important' | 'critical';
    mentions: string[];
    requiresApproval: boolean;
  };
  userPreferences: ChannelPreference;
  recentDeliveries?: DeliveryRecord[];
}

/**
 * Routing decision result
 */
export interface RoutingDecision {
  notificationId: string;
  userId: string;
  selectedRoute: NotificationRoute;
  secondaryRoutes: NotificationRoute[];
  escalationPolicy: EscalationLevel;
  deliveryDelay: number; // milliseconds
  batchable: boolean;
  batchWindowId?: string;
  reason: string;
  confidence: number; // 0-100
  timestamp: Date;
}

/**
 * Delivery acknowledgment
 */
export interface DeliveryAck {
  notificationId: string;
  userId: string;
  deliveryRoute: NotificationRoute;
  status: DeliveryStatus;
  ackTime?: Date;
  readTime?: Date;
  actedUpon: boolean;
  actionTaken?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Delivery record for history
 */
export interface DeliveryRecord {
  notificationId: string;
  userId: string;
  route: NotificationRoute;
  sentTime: Date;
  deliveredTime?: Date;
  status: DeliveryStatus;
  attempts: number;
  lastError?: string;
}

/**
 * Channel availability status
 */
export interface ChannelStatus {
  channel: NotificationRoute;
  isAvailable: boolean;
  capacity: number; // percentage (0-100)
  lastUpdated: Date;
  reason?: string;
  estimatedRecovery?: Date;
}

/**
 * Routing metrics
 */
export interface RoutingMetrics {
  notificationId: string;
  userId: string;
  totalAttempts: number;
  channelsUsed: NotificationRoute[];
  escalationsTriggered: number;
  finalStatus: DeliveryStatus;
  timeToFirstDelivery: number; // ms
  timeToAcknowledgment?: number; // ms
  timeToAction?: number; // ms
}

/**
 * Batch delivery window
 */
export interface BatchDeliveryWindow {
  windowId: string;
  userId: string;
  notificationIds: string[];
  startTime: Date;
  endTime: Date;
  targetRoute: NotificationRoute;
  status: 'scheduled' | 'sent' | 'delivered';
  deliveredAt?: Date;
}

/**
 * Channel configuration
 */
export interface ChannelConfig {
  channel: NotificationRoute;
  enabled: boolean;
  rateLimit: number; // notifications per minute
  batchingSupported: boolean;
  maxBatchSize: number;
  retryPolicy: {
    maxRetries: number;
    backoffMs: number;
  };
  timeoutMs: number;
  costPerNotification?: number; // For SMS/expensive channels
}

/**
 * Routing policy configuration
 */
export interface RoutingPolicyConfig {
  readinessWeighting: {
    available: number; // 0-100
    busy: number;
    away: number;
    offline: number;
  };
  priorityWeighting: {
    p0: number;
    p1: number;
    p2: number;
    p3: number;
  };
  timeOfDayFactors: {
    businessHours: number;
    afterHours: number;
    weekend: number;
  };
  escalationTimeouts: Record<EscalationLevel, number>; // ms
  maxConcurrentDeliveries: number;
  batchingWindow: number; // ms
}
