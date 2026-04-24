#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/types.ts
// @module      collaboration/readiness-indicator
// @description Type definitions for ReadinessIndicatorService
// @owner       collab-services
// @status      active

/**
 * Readiness level for team member availability
 */
export enum ReadinessLevel {
  AVAILABLE = 'available', // Ready for real-time collaboration
  BUSY = 'busy', // Available but limited capacity
  AWAY = 'away', // Not at desk, may return soon
  OFFLINE = 'offline', // Not available for collaboration
  DND = 'dnd', // Do not disturb
}

/**
 * Type of availability signal
 */
export enum SignalType {
  PRESENCE = 'presence',
  ACTIVITY = 'activity',
  CALENDAR = 'calendar',
  CAPACITY = 'capacity',
  HISTORY = 'history',
}

/**
 * Single availability signal from a source
 */
export interface AvailabilitySignal {
  userId: string;
  signalType: SignalType;
  readinessLevel: ReadinessLevel;
  confidence: number; // 0-100, reliability of signal
  timestamp: number;
  metadata?: Record<string, unknown>;
  source: string; // e.g., 'calendar', 'activity-tracker', 'presence-service'
}

/**
 * Aggregated readiness status for a user
 */
export interface UserReadinessStatus {
  userId: string;
  readinessLevel: ReadinessLevel;
  readinessScore: number; // 0-100
  signals: AvailabilitySignal[];
  lastUpdated: number;
  estimatedAvailableAt?: number; // timestamp when next available
  explanation: string;
}

/**
 * Availability window showing when user is/will be available
 */
export interface AvailabilityWindow {
  userId: string;
  startTime: number;
  endTime: number;
  readinessLevel: ReadinessLevel;
  reason?: string; // e.g., "In meeting", "Focused work"
  isEstimate: boolean;
  confidence: number; // 0-100
}

/**
 * Collaborative capacity of a user
 */
export interface CollaborativeCapacity {
  userId: string;
  activeFileCount: number;
  activeSessionCount: number;
  taskLoadScore: number; // 0-100
  responseLatencyMs: number; // average response time
  contextSwitchCost: number; // estimated cost of interrupting
  recommendedInteractionWindowMs: number;
  timestamp: number;
}

/**
 * Team-wide readiness metrics
 */
export interface TeamReadinessMetrics {
  teamId: string;
  totalMembers: number;
  availableCount: number; // fully available
  busyCount: number; // available but limited
  awayCount: number;
  offlineCount: number;
  dndCount: number;
  averageReadinessScore: number;
  teamCapacityScore: number; // 0-100
  optimalCollaborationWindow?: AvailabilityWindow;
  timestamp: number;
}

/**
 * Readiness prediction for future availability
 */
export interface ReadinessPrediction {
  userId: string;
  predictedReadinessLevel: ReadinessLevel;
  confidenceScore: number; // 0-100
  predictedAt: number;
  basedOnSignals: SignalType[];
  factors: {
    presenceFactor: number;
    activityFactor: number;
    calendarFactor: number;
    capacityFactor: number;
    historyFactor: number;
  };
  reasoning: string;
}

/**
 * Activity signal from user
 */
export interface ActivitySignal {
  userId: string;
  type: 'keyboard' | 'mouse' | 'cursor' | 'focus' | 'idle';
  timestamp: number;
  duration?: number; // how long activity lasted
  intensity?: number; // 0-100
}

/**
 * Calendar event affecting readiness
 */
export interface CalendarEvent {
  userId: string;
  title: string;
  startTime: number;
  endTime: number;
  type: 'meeting' | 'focus-time' | 'out-of-office' | 'break';
  isConfirmed: boolean;
  attendees?: string[];
}

/**
 * Configuration for ReadinessIndicatorService
 */
export interface ReadinessIndicatorConfig {
  // Signal weights (must sum to 100)
  signalWeights: {
    presence: number; // 30%
    activity: number; // 25%
    calendar: number; // 25%
    capacity: number; // 15%
    history: number; // 5%
  };

  // Readiness thresholds
  readinessThresholds: {
    available: number; // >= 75
    busy: number; // >= 50
    away: number; // >= 25
    offline: number; // < 25
  };

  // Activity tracking
  activityTimeoutMs: number; // 5 minutes
  idleThresholdMs: number; // 30 minutes

  // Signal freshness
  signalFreshnessMs: number; // max age of signal before recheck
  minSignalsForReadiness: number; // 2

  // Prediction
  enablePredictions: boolean;
  predictionWindowMs: number; // how far ahead to predict
  predictionUpdateIntervalMs: number;

  // Cleanup
  maxSignalHistorySize: number;
  signalRetentionMs: number;
  cleanupIntervalMs: number;
}

/**
 * Service statistics
 */
export interface ReadinessIndicatorStats {
  signalsProcessed: number;
  statusUpdatesGenerated: number;
  predictionsCalculated: number;
  averageScoringTimeMs: number;
  averageSignalsPerUser: number;
  teamReadinessCheckCount: number;
  uptime: number; // milliseconds
}

/**
 * Query options for finding user readiness
 */
export interface ReadinessQueryOptions {
  userId?: string;
  minReadinessScore?: number;
  readinessLevel?: ReadinessLevel;
  maxResults?: number;
  includeHistorical?: boolean;
}

/**
 * Query result
 */
export interface ReadinessQueryResult {
  statuses: UserReadinessStatus[];
  totalMatched: number;
  queryTimeMs: number;
}

/**
 * Subscription update for readiness changes
 */
export interface ReadinessUpdate {
  userId: string;
  previousLevel: ReadinessLevel;
  currentLevel: ReadinessLevel;
  reason: string;
  timestamp: number;
}

/**
 * Team collaboration window recommendation
 */
export interface CollaborationWindowRecommendation {
  teamId: string;
  recommendedStartTime: number;
  recommendedEndTime: number;
  expectedAvailableCount: number;
  optimalityScore: number; // 0-100
  reason: string;
  timestamp: number;
}
