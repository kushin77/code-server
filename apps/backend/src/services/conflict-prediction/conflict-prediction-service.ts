#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/conflict-prediction-service.ts
// @module      collaboration/conflict-prediction
// @description Real-time conflict detection service for collaborative editing
// @owner       collab-services
// @status      active

import { EventEmitter } from 'events';
import { v4 as uuidv4 } from 'uuid';
import type {
  ActiveEdit,
  ConflictAlert,
  MergePreview,
  RiskScoreFactors,
  ConflictMetrics,
  ConflictPredictionConfig,
  ConflictServiceStats,
  ActivityReportResult,
  ConflictQueryOptions,
  ConflictQueryResult,
} from './types';

/**
 * ConflictPredictionService - Real-time conflict detection for collaborative editing
 *
 * Monitors active user edits and generates intelligent conflict alerts based on
 * risk scoring. Tracks concurrent edits at both file and function levels,
 * calculates risk metrics, and notifies subscribers of potential merge conflicts.
 */
export class ConflictPredictionService extends EventEmitter {
  private activeEdits: Map<string, ActiveEdit> = new Map();
  private userSubscriptions: Map<string, (alert: ConflictAlert) => void> = new Map();
  private alertHistory: ConflictAlert[] = [];
  private config: ConflictPredictionConfig;
  private cleanupInterval: NodeJS.Timeout | null = null;
  private stats: ConflictServiceStats;

  constructor(config?: Partial<ConflictPredictionConfig>) {
    super();

    this.config = {
      stalledEditThresholdMs: 5 * 60 * 1000, // 5 minutes
      riskScoringWeights: {
        concurrentEdit: 50,
        fileComplexity: 30,
        functionSpecificity: 20,
      },
      alertSeverityThresholds: {
        critical: 80,
        high: 60,
        medium: 40,
        low: 20,
      },
      cleanupIntervalMs: 30 * 1000, // 30 seconds
      maxCacheSize: 10000,
      ...config,
    };

    this.stats = {
      alertsGenerated: 0,
      totalAnalyzed: 0,
      averageRiskScore: 0,
      averageCalculationTimeMs: 0,
      cacheHitRate: 0,
      activeUsersCount: 0,
      filesBeingEdited: 0,
    };

    this.startCleanupInterval();
  }

  /**
   * Report a user's active edit activity
   * Analyzes for conflicts and generates alerts for affected users
   */
  async reportActivity(
    userId: string,
    filePath: string,
    functionName?: string,
  ): Promise<ActivityReportResult> {
    try {
      const timestamp = Date.now();
      const key = this.buildEditKey(userId, filePath, functionName);

      // Record the edit
      const edit: ActiveEdit = {
        userId,
        filePath,
        functionName: functionName || null,
        timestamp,
      };

      this.activeEdits.set(key, edit);

      // Check for conflicts
      const conflicts = this.findConflictingEdits(userId, filePath, functionName);
      const riskScore = this.calculateRiskScore(filePath, functionName, conflicts.length);

      const alerts: ConflictAlert[] = [];

      if (conflicts.length > 0 && riskScore >= this.config.alertSeverityThresholds.low) {
        // Generate alerts for each conflicting user
        for (const conflictingEdit of conflicts) {
          const alert = this.createAlert(
            userId,
            conflictingEdit.userId,
            edit,
            riskScore,
            conflicts,
          );
          alerts.push(alert);
          this.alertHistory.push(alert);

          // Notify target user if subscribed
          const callback = this.userSubscriptions.get(conflictingEdit.userId);
          if (callback) {
            callback(alert);
          }

          // Emit event for global listeners
          this.emit('conflict', alert);
        }

        this.stats.alertsGenerated += alerts.length;
      }

      this.stats.totalAnalyzed++;
      this.updateStats();

      return {
        success: true,
        alertsGenerated: alerts,
        riskScore,
      };
    } catch (error) {
      return {
        success: false,
        alertsGenerated: [],
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Preview potential conflicts for an upcoming merge
   */
  previewConflicts(
    userId: string,
    filePath: string,
    functionName?: string,
  ): ConflictAlert[] {
    const conflicts = this.findConflictingEdits(userId, filePath, functionName);
    const alerts: ConflictAlert[] = [];

    for (const conflictingEdit of conflicts) {
      const riskScore = this.calculateRiskScore(filePath, functionName, conflicts.length);
      const alert = this.createAlert(
        userId,
        conflictingEdit.userId,
        {
          userId,
          filePath,
          functionName: functionName || null,
          timestamp: Date.now(),
        },
        riskScore,
        conflicts,
      );
      alerts.push(alert);
    }

    return alerts;
  }

  /**
   * Calculate risk score for a file/function combination
   * Factors: concurrent edits, file complexity, function specificity
   */
  calculateRiskScore(filePath: string, functionName?: string, conflictCount: number = 0): number {
    const factors = this.getRiskScoreFactors(filePath, functionName, conflictCount);

    // Weighted average calculation
    const score =
      (factors.concurrentEditFactor * this.config.riskScoringWeights.concurrentEdit) / 100 +
      (factors.fileComplexityFactor * this.config.riskScoringWeights.fileComplexity) / 100 +
      (factors.functionSpecificityFactor * this.config.riskScoringWeights.functionSpecificity) / 100;

    return Math.min(100, Math.max(0, Math.round(score)));
  }

  /**
   * Get all active edits matching criteria
   */
  getMatchingEdits(userId?: string, filePath?: string, functionName?: string): ActiveEdit[] {
    const results: ActiveEdit[] = [];

    for (const [_, edit] of this.activeEdits.entries()) {
      if (userId && edit.userId !== userId) continue;
      if (filePath && edit.filePath !== filePath) continue;
      if (functionName && edit.functionName !== functionName) continue;

      results.push(edit);
    }

    return results;
  }

  /**
   * Subscribe to conflict alerts for a user
   */
  onConflictAlert(userId: string, callback: (alert: ConflictAlert) => void): () => void {
    this.userSubscriptions.set(userId, callback);

    // Return unsubscribe function
    return () => {
      this.userSubscriptions.delete(userId);
    };
  }

  /**
   * Get current metrics
   */
  getMetrics(): ConflictMetrics {
    const activeUsers = new Set<string>();
    const filesWithConflicts = new Set<string>();
    let totalRiskScore = 0;
    let criticalConflicts = 0;

    for (const [_, edit] of this.activeEdits.entries()) {
      activeUsers.add(edit.userId);
      filesWithConflicts.add(edit.filePath);
    }

    for (const alert of this.alertHistory.slice(-1000)) {
      totalRiskScore += alert.riskScore;
      if (alert.severity === 'critical') {
        criticalConflicts++;
      }
    }

    return {
      totalActiveEdits: this.activeEdits.size,
      activeUsers,
      filesWithConflicts: filesWithConflicts.size,
      averageRiskScore:
        this.alertHistory.length > 0 ? Math.round(totalRiskScore / this.alertHistory.length) : 0,
      criticalConflicts,
      timestamp: Date.now(),
    };
  }

  /**
   * Get service statistics
   */
  getStats(): ConflictServiceStats {
    return { ...this.stats };
  }

  /**
   * Query alerts with filtering
   */
  queryAlerts(options: ConflictQueryOptions): ConflictQueryResult {
    const startTime = Date.now();
    let results = [...this.alertHistory];

    if (options.userId) {
      results = results.filter(
        (a) => a.targetUserId === options.userId || a.otherUserId === options.userId,
      );
    }

    if (options.filePath) {
      results = results.filter((a) => a.filePath === options.filePath);
    }

    if (options.functionName) {
      results = results.filter((a) => a.functionName === options.functionName);
    }

    if (options.minRiskScore) {
      results = results.filter((a) => a.riskScore >= options.minRiskScore!);
    }

    // Sort by timestamp descending
    results.sort((a, b) => b.timestamp - a.timestamp);

    // Apply max results limit
    if (options.maxResults) {
      results = results.slice(0, options.maxResults);
    }

    return {
      alerts: results,
      totalMatched: results.length,
      queryTimeMs: Date.now() - startTime,
    };
  }

  /**
   * Clear alert history (for testing or maintenance)
   */
  clearHistory(): void {
    this.alertHistory = [];
    this.stats.alertsGenerated = 0;
  }

  /**
   * Shutdown the service
   */
  shutdown(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
    this.removeAllListeners();
    this.userSubscriptions.clear();
    this.activeEdits.clear();
  }

  // Private helper methods

  private buildEditKey(userId: string, filePath: string, functionName?: string): string {
    return `${userId}:${filePath}:${functionName || 'file'}`;
  }

  private findConflictingEdits(
    userId: string,
    filePath: string,
    functionName?: string,
  ): ActiveEdit[] {
    const conflicts: ActiveEdit[] = [];

    for (const [_, edit] of this.activeEdits.entries()) {
      // Skip the reporting user's own edits
      if (edit.userId === userId) continue;

      // Check if editing same file
      if (edit.filePath !== filePath) continue;

      // If function-level conflict, both must specify the same function
      if (functionName && edit.functionName && edit.functionName === functionName) {
        conflicts.push(edit);
      } else if (!functionName && !edit.functionName) {
        // File-level conflict (neither specifying function)
        conflicts.push(edit);
      } else if (!functionName || !edit.functionName) {
        // One is file-level, one is function-level - still a conflict
        conflicts.push(edit);
      }
    }

    return conflicts;
  }

  private getRiskScoreFactors(
    filePath: string,
    functionName?: string,
    conflictCount: number = 0,
  ): RiskScoreFactors {
    // Concurrent edit factor: increases with number of conflicting users
    const concurrentEditFactor = Math.min(100, conflictCount * 25); // 25 per concurrent user

    // File complexity factor: simulated based on file characteristics
    const isComplex = this.isComplexFile(filePath);
    const fileComplexityFactor = isComplex ? 75 : 40;

    // Function specificity factor: higher for function-level vs file-level
    const functionSpecificityFactor = functionName ? 60 : 30;

    return {
      concurrentEditFactor,
      fileComplexityFactor,
      functionSpecificityFactor,
    };
  }

  private isComplexFile(filePath: string): boolean {
    // Files with these characteristics are more likely to have conflicts
    const complexPatterns = ['/api/', '/schema/', '/config/', '/core/', '/services/'];
    return complexPatterns.some((pattern) => filePath.includes(pattern));
  }

  private createAlert(
    reportingUserId: string,
    targetUserId: string,
    sourceEdit: ActiveEdit,
    riskScore: number,
    conflictingEdits: ActiveEdit[],
  ): ConflictAlert {
    const severity = this.calculateSeverity(riskScore);

    return {
      id: uuidv4(),
      targetUserId,
      otherUserId: reportingUserId,
      filePath: sourceEdit.filePath,
      functionName: sourceEdit.functionName,
      riskScore,
      message: this.generateAlertMessage(reportingUserId, sourceEdit, severity),
      severity,
      timestamp: Date.now(),
      conflictingEdits,
    };
  }

  private calculateSeverity(riskScore: number): 'low' | 'medium' | 'high' | 'critical' {
    if (riskScore >= this.config.alertSeverityThresholds.critical) return 'critical';
    if (riskScore >= this.config.alertSeverityThresholds.high) return 'high';
    if (riskScore >= this.config.alertSeverityThresholds.medium) return 'medium';
    return 'low';
  }

  private generateAlertMessage(
    userId: string,
    edit: ActiveEdit,
    severity: string,
  ): string {
    const target = edit.functionName
      ? `function ${edit.functionName}`
      : `file ${edit.filePath}`;
    return `${severity.toUpperCase()}: User ${userId} is editing ${target}`;
  }

  private updateStats(): void {
    const metrics = this.getMetrics();
    this.stats.activeUsersCount = metrics.activeUsers.size;
    this.stats.filesBeingEdited = metrics.filesWithConflicts;
    this.stats.averageRiskScore = metrics.averageRiskScore;
  }

  private startCleanupInterval(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanupStaledEdits();
    }, this.config.cleanupIntervalMs);
  }

  private cleanupStaledEdits(): void {
    const now = Date.now();
    const threshold = this.config.stalledEditThresholdMs;
    const keysToDelete: string[] = [];

    for (const [key, edit] of this.activeEdits.entries()) {
      if (now - edit.timestamp > threshold) {
        keysToDelete.push(key);
      }
    }

    keysToDelete.forEach((key) => this.activeEdits.delete(key));

    // Keep only last 10k alerts
    if (this.alertHistory.length > 10000) {
      this.alertHistory = this.alertHistory.slice(-10000);
    }
  }
}

/**
 * Factory function to create a ConflictPredictionService instance
 */
export function createConflictPredictionService(
  config?: Partial<ConflictPredictionConfig>,
): ConflictPredictionService {
  return new ConflictPredictionService(config);
}

// Export singleton instance
let instance: ConflictPredictionService;

export function getConflictPredictionService(): ConflictPredictionService {
  if (!instance) {
    instance = createConflictPredictionService();
  }
  return instance;
}
