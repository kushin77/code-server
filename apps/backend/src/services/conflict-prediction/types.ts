#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/types.ts
// @module      collaboration/conflict-prediction
// @description Type definitions for ConflictPredictionService
// @owner       collab-services
// @status      active

/**
 * Represents an active edit by a user in a file or function
 */
export interface ActiveEdit {
  userId: string;
  filePath: string;
  functionName: string | null;
  timestamp: number; // milliseconds since epoch
  lineStart?: number;
  lineEnd?: number;
}

/**
 * Alert when multiple users edit overlapping code
 */
export interface ConflictAlert {
  id: string;
  targetUserId: string;
  otherUserId: string;
  filePath: string;
  functionName: string | null;
  riskScore: number; // 0-100
  message: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  timestamp: number;
  conflictingEdits: ActiveEdit[];
}

/**
 * Preview of potential merge conflicts
 */
export interface MergePreview {
  fileId: string;
  conflicts: number;
  resolution: string;
  riskLevel: 'low' | 'medium' | 'high' | 'critical';
  affectedUsers: string[];
  timestamp: number;
}

/**
 * Risk scoring factors used in conflict calculation
 */
export interface RiskScoreFactors {
  concurrentEditFactor: number; // 0-100, weight 50%
  fileComplexityFactor: number; // 0-100, weight 30%
  functionSpecificityFactor: number; // 0-100, weight 20%
}

/**
 * Metrics about active edits and conflicts
 */
export interface ConflictMetrics {
  totalActiveEdits: number;
  activeUsers: Set<string>;
  filesWithConflicts: number;
  averageRiskScore: number;
  criticalConflicts: number;
  timestamp: number;
}

/**
 * Configuration for the conflict prediction service
 */
export interface ConflictPredictionConfig {
  stalledEditThresholdMs: number; // default: 5 minutes
  riskScoringWeights: {
    concurrentEdit: number; // 50%
    fileComplexity: number; // 30%
    functionSpecificity: number; // 20%
  };
  alertSeverityThresholds: {
    critical: number; // >= 80
    high: number; // >= 60
    medium: number; // >= 40
    low: number; // >= 20
  };
  cleanupIntervalMs: number; // how often to clean stale edits
  maxCacheSize: number; // max in-memory edits to track
}

/**
 * Statistics about the service performance
 */
export interface ConflictServiceStats {
  alertsGenerated: number;
  totalAnalyzed: number;
  averageRiskScore: number;
  averageCalculationTimeMs: number;
  cacheHitRate: number;
  activeUsersCount: number;
  filesBeingEdited: number;
}

/**
 * Result of reporting an edit activity
 */
export interface ActivityReportResult {
  success: boolean;
  alertsGenerated: ConflictAlert[];
  riskScore?: number;
  error?: string;
}

/**
 * Options for querying conflicts
 */
export interface ConflictQueryOptions {
  userId?: string;
  filePath?: string;
  functionName?: string;
  minRiskScore?: number;
  maxResults?: number;
}

/**
 * Result of a conflict query
 */
export interface ConflictQueryResult {
  alerts: ConflictAlert[];
  totalMatched: number;
  queryTimeMs: number;
}
