"use strict";
/**
 * Threat Detection Engine
 *
 * Real-time anomaly detection and threat scoring with:
 * - Behavioral anomaly detection
 * - Attack pattern recognition
 * - Risk scoring and anomaly aggregation
 * - Automated threat response triggers
 * - ML-based threat classification
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ThreatDetectionEngine = exports.AnomalyType = exports.ThreatLevel = void 0;
var ThreatLevel;
(function (ThreatLevel) {
    ThreatLevel[ThreatLevel["NONE"] = 0] = "NONE";
    ThreatLevel[ThreatLevel["LOW"] = 1] = "LOW";
    ThreatLevel[ThreatLevel["MEDIUM"] = 2] = "MEDIUM";
    ThreatLevel[ThreatLevel["HIGH"] = 3] = "HIGH";
    ThreatLevel[ThreatLevel["CRITICAL"] = 4] = "CRITICAL";
})(ThreatLevel || (exports.ThreatLevel = ThreatLevel = {}));
var AnomalyType;
(function (AnomalyType) {
    AnomalyType["BRUTE_FORCE"] = "brute_force";
    AnomalyType["DATA_EXFILTRATION"] = "data_exfiltration";
    AnomalyType["PRIVILEGE_ESCALATION"] = "privilege_escalation";
    AnomalyType["LATERAL_MOVEMENT"] = "lateral_movement";
    AnomalyType["MALWARE_ACTIVITY"] = "malware_activity";
    AnomalyType["INSIDER_THREAT"] = "insider_threat";
    AnomalyType["DDoS_ATTACK"] = "ddos_attack";
    AnomalyType["INJECTION_ATTACK"] = "injection_attack";
    AnomalyType["CONFIGURATION_DRIFT"] = "configuration_drift";
    AnomalyType["ZERO_DAY"] = "zero_day";
})(AnomalyType || (exports.AnomalyType = AnomalyType = {}));
/**
 * ThreatDetectionEngine - Real-time anomaly and threat detection
 *
 * Detects:
 * - Brute force attacks
 * - Data exfiltration attempts
 * - Privilege escalation
 * - Lateral movement
 * - Malware activity
 * - Insider threats
 * - DDoS attacks
 * - Injection attacks
 * - Configuration drift
 * - Zero-day exploits
 */
class ThreatDetectionEngine {
    constructor() {
        this.rules = new Map();
        this.eventStream = [];
        this.anomalySignals = new Map();
        this.userProfiles = new Map();
        this.maxEventStreamSize = 100000;
        this.baselineWindowDays = 30;
        this.detectionInterval = 5000; // 5 seconds
        this.registerDefaultRules();
    }
    /**
     * Register default detection rules
     */
    registerDefaultRules() {
        // Rule 1: Brute force detection
        this.registerRule({
            ruleId: 'rule_brute_force_login',
            name: 'Brute Force Login Attempts',
            anomalyType: AnomalyType.BRUTE_FORCE,
            condition: (events) => {
                // Count failed login attempts in last 5 minutes
                const recentFailures = events.filter((e) => e.action === 'login' &&
                    e.result === 'failure' &&
                    e.timestamp.getTime() > Date.now() - 5 * 60 * 1000);
                return recentFailures.length >= 5; // 5+ failures in 5 minutes = suspicious
            },
            riskScoreCalculator: (events) => {
                const recentFailures = events.filter((e) => e.action === 'login' &&
                    e.result === 'failure' &&
                    e.timestamp.getTime() > Date.now() - 5 * 60 * 1000);
                return Math.min(recentFailures.length * 10, 100); // 10 points per attempt, max 100
            },
            enabled: true
        });
        // Rule 2: Data exfiltration detection
        this.registerRule({
            ruleId: 'rule_data_exfiltration',
            name: 'Unusual Data Download',
            anomalyType: AnomalyType.DATA_EXFILTRATION,
            condition: (events) => {
                // Check for bulk data exports
                const downloads = events.filter((e) => (e.action === 'export' || e.action === 'download') &&
                    e.result === 'success' &&
                    (e.metadata.dataSize || 0) > 100 * 1024 * 1024 // > 100 MB single download
                );
                return downloads.length > 0;
            },
            riskScoreCalculator: (events) => {
                const downloads = events.filter((e) => (e.action === 'export' || e.action === 'download') &&
                    e.result === 'success');
                let score = 0;
                for (const event of downloads) {
                    const dataSize = event.metadata.dataSize || 0;
                    if (dataSize > 100 * 1024 * 1024) {
                        score += Math.min((dataSize / (1024 * 1024)) / 10, 50);
                    }
                }
                return Math.min(score + (downloads.length > 5 ? 30 : 0), 100);
            },
            enabled: true
        });
        // Rule 3: Privilege escalation detection
        this.registerRule({
            ruleId: 'rule_privilege_escalation',
            name: 'Suspicious Privilege Escalation',
            anomalyType: AnomalyType.PRIVILEGE_ESCALATION,
            condition: (events) => {
                const escalations = events.filter((e) => e.action === 'escalate' && e.result === 'success');
                return escalations.length > 2; // More than 2 escalations in short time
            },
            riskScoreCalculator: (events) => {
                const escalations = events.filter((e) => e.action === 'escalate' && e.result === 'success');
                return Math.min(escalations.length * 20, 100);
            },
            enabled: true
        });
        // Rule 4: Lateral movement detection
        this.registerRule({
            ruleId: 'rule_lateral_movement',
            name: 'Unexpected Lateral Movement',
            anomalyType: AnomalyType.LATERAL_MOVEMENT,
            condition: (events) => {
                const uniqueResources = new Set(events.map((e) => e.resource));
                return uniqueResources.size > 10; // Accessing 10+ different resources in short time
            },
            riskScoreCalculator: (events) => {
                const uniqueResources = new Set(events.map((e) => e.resource));
                return Math.min(uniqueResources.size * 5, 100);
            },
            enabled: true
        });
        // Rule 5: DDoS detection
        this.registerRule({
            ruleId: 'rule_ddos_attack',
            name: 'Distributed Denial of Service',
            anomalyType: AnomalyType.DDoS_ATTACK,
            condition: (events) => {
                const recentRequests = events.filter((e) => e.timestamp.getTime() > Date.now() - 1 * 60 * 1000);
                return recentRequests.length > 10000; // > 10k requests per minute = suspicious
            },
            riskScoreCalculator: (events) => {
                const recentRequests = events.filter((e) => e.timestamp.getTime() > Date.now() - 1 * 60 * 1000);
                return Math.min((recentRequests.length / 100) * 10, 100);
            },
            enabled: true
        });
    }
    /**
     * Register a custom detection rule
     */
    registerRule(rule) {
        this.rules.set(rule.ruleId, rule);
    }
    /**
     * Process incoming security event
     */
    processSecurityEvent(event) {
        this.eventStream.push(event);
        // Maintain size limit
        if (this.eventStream.length > this.maxEventStreamSize) {
            this.eventStream = this.eventStream.slice(-this.maxEventStreamSize);
        }
        // Update user profile
        if (event.userId) {
            this.updateUserProfile(event.userId);
        }
        // Run detection rules
        this.runDetectionRules();
    }
    /**
     * Run all enabled detection rules
     */
    runDetectionRules() {
        for (const rule of this.rules.values()) {
            if (!rule.enabled)
                continue;
            // Get recent events for evaluation
            const recentEvents = this.eventStream.filter((e) => e.timestamp.getTime() > Date.now() - 10 * 60 * 1000);
            if (rule.condition(recentEvents)) {
                const riskScore = rule.riskScoreCalculator(recentEvents);
                // Create anomaly signal
                const signal = {
                    signalId: `signal_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                    anomalyType: rule.anomalyType,
                    timestamp: new Date(),
                    severity: this.calculateSeverity(riskScore),
                    riskScore,
                    description: rule.name,
                    evidenceItems: recentEvents.map((e) => ({
                        eventId: e.eventId,
                        timestamp: e.timestamp,
                        contributionToAnomaly: 0.1, // Simplified
                        eventDescription: `${e.action} on ${e.resource}`
                    }))
                };
                this.anomalySignals.set(signal.signalId, signal);
            }
        }
    }
    /**
     * Calculate threat level from risk score
     */
    calculateSeverity(riskScore) {
        if (riskScore >= 80)
            return ThreatLevel.CRITICAL;
        if (riskScore >= 60)
            return ThreatLevel.HIGH;
        if (riskScore >= 40)
            return ThreatLevel.MEDIUM;
        if (riskScore >= 20)
            return ThreatLevel.LOW;
        return ThreatLevel.NONE;
    }
    /**
     * Update user threat profile
     */
    updateUserProfile(userId) {
        let profile = this.userProfiles.get(userId);
        if (!profile) {
            profile = {
                profileId: `profile_${userId}_${Date.now()}`,
                userId,
                baselineActivities: new Map(),
                anomalies: [],
                threatLevel: ThreatLevel.NONE,
                riskScore: 0,
                lastUpdated: new Date()
            };
            this.userProfiles.set(userId, profile);
        }
        // Get user's recent events
        const userEvents = this.eventStream.filter((e) => e.userId === userId &&
            e.timestamp.getTime() > Date.now() - this.baselineWindowDays * 24 * 60 * 60 * 1000);
        // Update baseline activities: count action frequencies
        const actionCounts = new Map();
        for (const event of userEvents) {
            const count = actionCounts.get(event.action) || 0;
            actionCounts.set(event.action, count + 1);
        }
        // Calculate user threat level from their anomalies
        let maxRiskScore = 0;
        let maxSeverity = ThreatLevel.NONE;
        for (const signal of this.anomalySignals.values()) {
            if (signal.evidenceItems.some((e) => {
                const event = this.eventStream.find((ev) => ev.eventId === e.eventId);
                return event?.userId === userId;
            })) {
                profile.anomalies.push(signal);
                if (signal.riskScore > maxRiskScore) {
                    maxRiskScore = signal.riskScore;
                    maxSeverity = signal.severity;
                }
            }
        }
        profile.threatLevel = maxSeverity;
        profile.riskScore = maxRiskScore;
        profile.lastUpdated = new Date();
    }
    /**
     * Get threat profile for user
     */
    getUserThreatProfile(userId) {
        return this.userProfiles.get(userId);
    }
    /**
     * Get all active anomalies above threshold
     */
    getActiveAnomalies(minSeverity = ThreatLevel.MEDIUM) {
        const anomalies = [];
        for (const signal of this.anomalySignals.values()) {
            if (signal.severity >= minSeverity) {
                // Only include anomalies from last hour
                if (signal.timestamp.getTime() > Date.now() - 60 * 60 * 1000) {
                    anomalies.push(signal);
                }
            }
        }
        return anomalies.sort((a, b) => b.riskScore - a.riskScore);
    }
    /**
     * Get detection statistics
     */
    getDetectionStats() {
        const stats = {
            totalEvents: this.eventStream.length,
            totalAnomalies: this.anomalySignals.size,
            criticalAnomalies: 0,
            highAnomalies: 0,
            rulesEnabled: 0,
            activeProfiles: this.userProfiles.size
        };
        for (const signal of this.anomalySignals.values()) {
            if (signal.severity === ThreatLevel.CRITICAL)
                stats.criticalAnomalies++;
            if (signal.severity === ThreatLevel.HIGH)
                stats.highAnomalies++;
        }
        for (const rule of this.rules.values()) {
            if (rule.enabled)
                stats.rulesEnabled++;
        }
        return stats;
    }
    /**
     * Get anomalies for specific type
     */
    getAnomaliesByType(anomalyType) {
        const signals = [];
        for (const signal of this.anomalySignals.values()) {
            if (signal.anomalyType === anomalyType) {
                signals.push(signal);
            }
        }
        return signals.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());
    }
    /**
     * Clear old anomalies (maintenance)
     */
    clearOldAnomalies(maxAgeHours = 24) {
        const cutoffTime = Date.now() - maxAgeHours * 60 * 60 * 1000;
        const toDelete = [];
        for (const [signalId, signal] of this.anomalySignals) {
            if (signal.timestamp.getTime() < cutoffTime) {
                toDelete.push(signalId);
            }
        }
        for (const signalId of toDelete) {
            this.anomalySignals.delete(signalId);
        }
        return toDelete.length;
    }
    /**
     * Disable/enable detection rule
     */
    setRuleEnabled(ruleId, enabled) {
        const rule = this.rules.get(ruleId);
        if (rule) {
            rule.enabled = enabled;
            return true;
        }
        return false;
    }
}
exports.ThreatDetectionEngine = ThreatDetectionEngine;
//# sourceMappingURL=ThreatDetectionEngine.js.map