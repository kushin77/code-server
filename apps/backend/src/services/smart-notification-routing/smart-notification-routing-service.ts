#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/smart-notification-routing-service.ts
// @module      collaboration/smart-notification-routing
// @description Intelligent multi-channel notification routing based on context and preferences
// @owner       collab-6.2
// @status      active

import { EventEmitter } from 'events';
import type {
  NotificationRoute,
  EscalationLevel,
  ChannelPreference,
  RoutingContext,
  RoutingDecision,
  DeliveryAck,
  ChannelStatus,
} from './types';

/**
 * SmartNotificationRoutingService - Intelligent multi-channel notification delivery
 */
export class SmartNotificationRoutingService extends EventEmitter {
  private userPreferences: Map<string, ChannelPreference> = new Map();
  private channelStatus: Map<NotificationRoute, ChannelStatus> = new Map();
  private routingDecisions: Map<string, RoutingDecision> = new Map();
  private deliveryAcks: Map<string, DeliveryAck> = new Map();

  // Signal weights for routing decision
  private weights = {
    readiness: 0.35,
    priority: 0.30,
    preferences: 0.20,
    timeOfDay: 0.10,
    deviceAvailability: 0.05,
  };

  constructor() {
    super();
    this.initializeChannelStatus();
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    // Initialize channel status
    this.initializeChannelStatus();
  }

  /**
   * Initialize channel status
   */
  private initializeChannelStatus(): void {
    const channels: NotificationRoute[] = ['in-app', 'email', 'slack', 'sms', 'push'];
    for (const channel of channels) {
      this.channelStatus.set(channel, {
        channel,
        isAvailable: true,
        capacity: 100,
        lastUpdated: new Date(),
      });
    }
  }

  /**
   * Make routing decision for notification
   */
  async makeRoutingDecision(context: RoutingContext): Promise<RoutingDecision> {
    // Score channels based on context
    const scores = this.scoreChannels(context);

    // Select primary route
    const selectedRoute = Object.entries(scores)
      .sort(([, scoreA], [, scoreB]) => scoreB - scoreA)[0][0] as NotificationRoute;

    // Get secondary routes (for escalation)
    const secondaryRoutes = Object.entries(scores)
      .sort(([, scoreA], [, scoreB]) => scoreB - scoreA)
      .slice(1, 3)
      .map(([route]) => route as NotificationRoute);

    // Determine escalation level
    const escalationLevel = this.getEscalationLevel(context.priority);

    // Calculate delivery delay
    const deliveryDelay = this.calculateDeliveryDelay(context, selectedRoute);

    const decision: RoutingDecision = {
      notificationId: context.notificationId,
      userId: context.userId,
      selectedRoute,
      secondaryRoutes,
      escalationPolicy: escalationLevel,
      deliveryDelay,
      batchable: !context.conversationContext?.urgency?.includes('critical'),
      reason: `Selected ${selectedRoute} for readiness=${context.readinessLevel}, priority=${context.priority}`,
      confidence: Math.round((scores[selectedRoute] + 50) / 2),
      timestamp: new Date(),
    };

    this.routingDecisions.set(context.notificationId, decision);
    return decision;
  }

  /**
   * Score each channel for notification
   */
  private scoreChannels(context: RoutingContext): Record<NotificationRoute, number> {
    const scores: Record<NotificationRoute, number> = {
      'in-app': 0,
      'email': 0,
      'slack': 0,
      'sms': 0,
      'push': 0,
    };

    // Base score from readiness
    const readinessScores: Record<string, number> = {
      available: 100,
      busy: 70,
      away: 30,
      offline: 0,
    };

    const baseScore = readinessScores[context.readinessLevel] || 50;

    // Priority weighting
    const priorityScores: Record<string, number> = {
      P0: 100,
      P1: 80,
      P2: 50,
      P3: 30,
    };

    const priorityScore = priorityScores[context.priority] || 50;

    // For available users, prefer in-app
    if (context.readinessLevel === 'available') {
      scores['in-app'] = baseScore + priorityScore;
      scores['slack'] = baseScore + priorityScore - 10;
      scores['email'] = baseScore + priorityScore - 20;
      scores['push'] = baseScore + priorityScore - 30;
      scores['sms'] = baseScore + priorityScore - 40;
    } else if (context.readinessLevel === 'busy') {
      scores['email'] = baseScore + priorityScore;
      scores['slack'] = baseScore + priorityScore - 5;
      scores['in-app'] = baseScore + priorityScore - 15;
      scores['push'] = baseScore + priorityScore - 25;
      scores['sms'] = baseScore + priorityScore - 35;
    } else if (context.readinessLevel === 'away') {
      scores['email'] = baseScore + priorityScore;
      scores['push'] = baseScore + priorityScore;
      scores['slack'] = baseScore + priorityScore - 10;
      scores['sms'] = baseScore + priorityScore - 20;
      scores['in-app'] = baseScore + priorityScore - 30;
    } else {
      // offline
      scores['sms'] = priorityScore;
      scores['push'] = priorityScore - 10;
      scores['email'] = priorityScore - 20;
      scores['slack'] = 0;
      scores['in-app'] = 0;
    }

    return scores;
  }

  /**
   * Get escalation level based on priority
   */
  private getEscalationLevel(priority: string): EscalationLevel {
    const p = parseInt(priority.replace('P', ''), 10);
    return Math.max(1, Math.min(5, 6 - p)) as EscalationLevel;
  }

  /**
   * Calculate delivery delay
   */
  private calculateDeliveryDelay(context: RoutingContext, route: NotificationRoute): number {
    // Immediate delivery for critical
    if (context.conversationContext?.urgency === 'critical' || context.priority === 'P0') {
      return 0;
    }

    // Batch window delay for batching-supported channels
    if (route === 'in-app' || route === 'email' || route === 'push') {
      return 30000; // 30 second batch window
    }

    return 1000; // 1 second default
  }

  /**
   * Record delivery acknowledgment
   */
  async recordDeliveryAck(ack: DeliveryAck): Promise<void> {
    this.deliveryAcks.set(ack.notificationId, ack);
    this.emit('deliveryAck', ack);
  }

  /**
   * Get user preferences
   */
  async getUserPreferences(userId: string): Promise<ChannelPreference | null> {
    if (this.userPreferences.has(userId)) {
      return this.userPreferences.get(userId)!;
    }
    return null;
  }

  /**
   * Update channel status
   */
  async updateChannelStatus(
    channel: NotificationRoute,
    available: boolean,
    capacity: number,
    reason?: string
  ): Promise<void> {
    const status: ChannelStatus = {
      channel,
      isAvailable: available,
      capacity,
      lastUpdated: new Date(),
      reason,
    };

    this.channelStatus.set(channel, status);
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.removeAllListeners();
    this.userPreferences.clear();
    this.routingDecisions.clear();
    this.deliveryAcks.clear();
  }
}

/**
 * Factory function to create service instance
 */
export function createSmartNotificationRoutingService(): SmartNotificationRoutingService {
  return new SmartNotificationRoutingService();
}

export * from './types';
