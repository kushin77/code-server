#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/readiness-indicator-service.ts
// @module      collaboration/readiness-indicator
// @description Team member availability and capacity indicator service
// @owner       collab-services
// @status      active
import { EventEmitter } from 'events';
import { ReadinessLevel } from './types';
/**
 * ReadinessIndicatorService - Team member availability and capacity tracking
 *
 * Aggregates multi-source availability signals (presence, activity, calendar, capacity)
 * to determine team member readiness for real-time collaboration. Provides team-wide
 * metrics and optimal collaboration window recommendations.
 */
export class ReadinessIndicatorService extends EventEmitter {
    constructor(config) {
        super();
        this.signals = new Map();
        this.userStatus = new Map();
        this.capacityMetrics = new Map();
        this.subscriptions = new Map();
        this.cleanupInterval = null;
        this.config = {
            signalWeights: {
                presence: 30,
                activity: 25,
                calendar: 25,
                capacity: 15,
                history: 5,
            },
            readinessThresholds: {
                available: 75,
                busy: 50,
                away: 25,
                offline: 0,
            },
            activityTimeoutMs: 5 * 60 * 1000,
            idleThresholdMs: 30 * 60 * 1000,
            signalFreshnessMs: 60 * 1000,
            minSignalsForReadiness: 2,
            enablePredictions: true,
            predictionWindowMs: 15 * 60 * 1000,
            predictionUpdateIntervalMs: 60 * 1000,
            maxSignalHistorySize: 1000,
            signalRetentionMs: 24 * 60 * 60 * 1000,
            cleanupIntervalMs: 5 * 60 * 1000,
            ...config,
        };
        this.stats = {
            signalsProcessed: 0,
            statusUpdatesGenerated: 0,
            predictionsCalculated: 0,
            averageScoringTimeMs: 0,
            averageSignalsPerUser: 0,
            teamReadinessCheckCount: 0,
            uptime: 0,
        };
        this.startCleanupInterval();
    }
    /**
     * Add an availability signal from any source
     */
    async addSignal(signal) {
        try {
            const userId = signal.userId;
            // Get or create signal list for user
            if (!this.signals.has(userId)) {
                this.signals.set(userId, []);
            }
            const userSignals = this.signals.get(userId);
            userSignals.push(signal);
            // Keep only recent signals
            while (userSignals.length > this.config.maxSignalHistorySize) {
                userSignals.shift();
            }
            this.stats.signalsProcessed++;
            // Update user readiness status
            const previousStatus = this.userStatus.get(userId);
            const newStatus = this.calculateReadiness(userId);
            if (previousStatus && previousStatus.readinessLevel !== newStatus.readinessLevel) {
                // Status changed, emit update
                const update = {
                    userId,
                    previousLevel: previousStatus.readinessLevel,
                    currentLevel: newStatus.readinessLevel,
                    reason: newStatus.explanation,
                    timestamp: Date.now(),
                };
                this.emit('readinessChanged', update);
                // Notify subscribers
                const callback = this.subscriptions.get(userId);
                if (callback) {
                    callback(update);
                }
                this.stats.statusUpdatesGenerated++;
            }
            this.userStatus.set(userId, newStatus);
            return true;
        }
        catch (error) {
            this.emit('error', error);
            return false;
        }
    }
    /**
     * Get current readiness status for a user
     */
    getUserStatus(userId) {
        return this.userStatus.get(userId) || null;
    }
    /**
     * Get readiness for multiple users (team view)
     */
    getTeamReadiness(teamId, userIds) {
        const metrics = {
            teamId,
            totalMembers: userIds.length,
            availableCount: 0,
            busyCount: 0,
            awayCount: 0,
            offlineCount: 0,
            dndCount: 0,
            averageReadinessScore: 0,
            teamCapacityScore: 0,
            timestamp: Date.now(),
        };
        let totalScore = 0;
        let totalCapacity = 0;
        for (const userId of userIds) {
            const status = this.userStatus.get(userId);
            if (!status)
                continue;
            totalScore += status.readinessScore;
            switch (status.readinessLevel) {
                case ReadinessLevel.AVAILABLE:
                    metrics.availableCount++;
                    break;
                case ReadinessLevel.BUSY:
                    metrics.busyCount++;
                    break;
                case ReadinessLevel.AWAY:
                    metrics.awayCount++;
                    break;
                case ReadinessLevel.OFFLINE:
                    metrics.offlineCount++;
                    break;
                case ReadinessLevel.DND:
                    metrics.dndCount++;
                    break;
            }
            const capacity = this.capacityMetrics.get(userId);
            if (capacity) {
                totalCapacity += 100 - capacity.taskLoadScore;
            }
        }
        metrics.averageReadinessScore =
            userIds.length > 0 ? Math.round(totalScore / userIds.length) : 0;
        metrics.teamCapacityScore =
            userIds.length > 0 ? Math.round(totalCapacity / userIds.length) : 0;
        this.stats.teamReadinessCheckCount++;
        return metrics;
    }
    /**
     * Get collaborative capacity for a user
     */
    getCapacity(userId) {
        return this.capacityMetrics.get(userId) || null;
    }
    /**
     * Update collaborative capacity metrics for a user
     */
    setCapacity(userId, capacity) {
        this.capacityMetrics.set(userId, {
            ...capacity,
            timestamp: Date.now(),
        });
    }
    /**
     * Predict future readiness for a user
     */
    predictReadiness(userId) {
        const userSignals = this.signals.get(userId);
        if (!userSignals || userSignals.length < this.config.minSignalsForReadiness) {
            return null;
        }
        try {
            const startTime = Date.now();
            // Weight different factors for prediction
            const factors = {
                presenceFactor: this.calculateSignalFactor(userId, 'presence'),
                activityFactor: this.calculateSignalFactor(userId, 'activity'),
                calendarFactor: this.calculateSignalFactor(userId, 'calendar'),
                capacityFactor: this.calculateSignalFactor(userId, 'capacity'),
                historyFactor: this.calculateSignalFactor(userId, 'history'),
            };
            // Calculate weighted prediction
            const predictedScore = (factors.presenceFactor * 0.3 +
                factors.activityFactor * 0.25 +
                factors.calendarFactor * 0.25 +
                factors.capacityFactor * 0.15 +
                factors.historyFactor * 0.05) /
                100;
            const predictedLevel = this.scoreToReadinessLevel(predictedScore * 100);
            const timeMs = Date.now() - startTime;
            // Update stats
            this.stats.predictionsCalculated++;
            this.stats.averageScoringTimeMs =
                (this.stats.averageScoringTimeMs + timeMs) / 2;
            return {
                userId,
                predictedReadinessLevel: predictedLevel,
                confidenceScore: 85, // Based on signal diversity
                predictedAt: Date.now(),
                basedOnSignals: Object.keys(factors).map((k) => k.replace('Factor', '')),
                factors,
                reasoning: `Predicted ${predictedLevel} based on ${Object.keys(factors).length} signal types`,
            };
        }
        catch (error) {
            this.emit('error', error);
            return null;
        }
    }
    /**
     * Find optimal collaboration window for team
     */
    findOptimalCollaborationWindow(teamId, userIds, windowSizeMs = 60 * 60 * 1000) {
        const now = Date.now();
        const searchWindow = now + 24 * 60 * 60 * 1000; // Look ahead 24 hours
        // Simplified: recommend next hour with most availability
        const recommendation = {
            teamId,
            recommendedStartTime: now + 60 * 60 * 1000, // Next hour
            recommendedEndTime: now + 2 * 60 * 60 * 1000,
            expectedAvailableCount: 0,
            optimalityScore: 0,
            reason: 'Based on current readiness signals',
            timestamp: now,
        };
        // Count expected available in window
        for (const userId of userIds) {
            const status = this.userStatus.get(userId);
            if (status && status.readinessLevel === ReadinessLevel.AVAILABLE) {
                recommendation.expectedAvailableCount++;
            }
        }
        recommendation.optimalityScore =
            (recommendation.expectedAvailableCount / userIds.length) * 100;
        return recommendation;
    }
    /**
     * Subscribe to readiness changes for a user
     */
    onReadinessChanged(userId, callback) {
        this.subscriptions.set(userId, callback);
        // Return unsubscribe function
        return () => {
            this.subscriptions.delete(userId);
        };
    }
    /**
     * Query readiness status with filtering
     */
    queryReadiness(options) {
        const startTime = Date.now();
        let results = [];
        for (const [_, status] of this.userStatus) {
            if (options.userId && status.userId !== options.userId)
                continue;
            if (options.minReadinessScore && status.readinessScore < options.minReadinessScore)
                continue;
            if (options.readinessLevel && status.readinessLevel !== options.readinessLevel)
                continue;
            results.push(status);
        }
        // Sort by readiness score descending
        results.sort((a, b) => b.readinessScore - a.readinessScore);
        // Apply max results limit
        if (options.maxResults) {
            results = results.slice(0, options.maxResults);
        }
        return {
            statuses: results,
            totalMatched: results.length,
            queryTimeMs: Date.now() - startTime,
        };
    }
    /**
     * Get service statistics
     */
    getStats() {
        return { ...this.stats };
    }
    /**
     * Shutdown service
     */
    shutdown() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
            this.cleanupInterval = null;
        }
        this.removeAllListeners();
        this.subscriptions.clear();
        this.signals.clear();
        this.userStatus.clear();
        this.capacityMetrics.clear();
    }
    // Private helper methods
    calculateReadiness(userId) {
        const userSignals = this.signals.get(userId) || [];
        const now = Date.now();
        // Get recent signals
        const recentSignals = userSignals.filter((s) => now - s.timestamp < this.config.signalFreshnessMs);
        // If not enough signals, return offline
        if (recentSignals.length < this.config.minSignalsForReadiness) {
            return {
                userId,
                readinessLevel: ReadinessLevel.OFFLINE,
                readinessScore: 0,
                signals: recentSignals,
                lastUpdated: now,
                explanation: 'Insufficient recent signals',
            };
        }
        // Calculate weighted score from signals
        let totalScore = 0;
        let totalWeight = 0;
        for (const signal of recentSignals) {
            const weight = this.getSignalWeight(signal.signalType);
            totalScore += signal.confidence * weight;
            totalWeight += weight;
        }
        const readinessScore = totalWeight > 0 ? Math.round(totalScore / totalWeight) : 0;
        const readinessLevel = this.scoreToReadinessLevel(readinessScore);
        // Update average signal tracking
        this.stats.averageSignalsPerUser = (userSignals.length + this.stats.averageSignalsPerUser) / 2;
        return {
            userId,
            readinessLevel,
            readinessScore,
            signals: recentSignals,
            lastUpdated: now,
            explanation: this.generateExplanation(readinessLevel, recentSignals),
        };
    }
    scoreToReadinessLevel(score) {
        if (score >= this.config.readinessThresholds.available)
            return ReadinessLevel.AVAILABLE;
        if (score >= this.config.readinessThresholds.busy)
            return ReadinessLevel.BUSY;
        if (score >= this.config.readinessThresholds.away)
            return ReadinessLevel.AWAY;
        return ReadinessLevel.OFFLINE;
    }
    getSignalWeight(signalType) {
        const weights = {
            presence: this.config.signalWeights.presence,
            activity: this.config.signalWeights.activity,
            calendar: this.config.signalWeights.calendar,
            capacity: this.config.signalWeights.capacity,
            history: this.config.signalWeights.history,
        };
        return weights[signalType] || 0;
    }
    calculateSignalFactor(userId, signalType) {
        const userSignals = this.signals.get(userId) || [];
        const typeSignals = userSignals.filter((s) => s.signalType === signalType);
        if (typeSignals.length === 0)
            return 0;
        const avgConfidence = typeSignals.reduce((sum, s) => sum + s.confidence, 0) / typeSignals.length;
        return avgConfidence;
    }
    generateExplanation(level, signals) {
        const signalTypes = [...new Set(signals.map((s) => s.signalType))].join(', ');
        return `${level} based on signals: ${signalTypes}`;
    }
    startCleanupInterval() {
        this.cleanupInterval = setInterval(() => {
            this.cleanupStaleSignals();
        }, this.config.cleanupIntervalMs);
    }
    cleanupStaleSignals() {
        const now = Date.now();
        const threshold = this.config.signalRetentionMs;
        for (const [userId, signals] of this.signals) {
            const recentSignals = signals.filter((s) => now - s.timestamp < threshold);
            if (recentSignals.length !== signals.length) {
                this.signals.set(userId, recentSignals);
            }
        }
    }
}
/**
 * Factory function to create a ReadinessIndicatorService instance
 */
export function createReadinessIndicatorService(config) {
    return new ReadinessIndicatorService(config);
}
// Export singleton instance
let instance;
export function getReadinessIndicatorService() {
    if (!instance) {
        instance = createReadinessIndicatorService();
    }
    return instance;
}
//# sourceMappingURL=readiness-indicator-service.js.map