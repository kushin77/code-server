/**
 * Anomaly detection service managing profiles, scoring, and alerting.
 */
import { AnomalyDetectionEngine, DEFAULT_ANOMALY_CONFIG } from './engine';
export class AnomalyDetectionService {
    constructor(config = {}) {
        this.profiles = new Map();
        this.alertsPerUser = new Map();
        this.config = { ...DEFAULT_ANOMALY_CONFIG, ...config };
        this.engine = new AnomalyDetectionEngine(this.config);
    }
    async getOrCreateProfile(userId, recentEvents) {
        if (this.profiles.has(userId)) {
            return this.profiles.get(userId);
        }
        if (recentEvents.length >= this.config.minSamplesForProfile) {
            try {
                const profile = this.engine.buildProfile(userId, recentEvents);
                this.profiles.set(userId, profile);
                return profile;
            }
            catch (error) {
                return null;
            }
        }
        return null;
    }
    isInGracePeriod(profile) {
        const age = Date.now() - profile.createdAt;
        return age < this.config.gracePeriodMs;
    }
    getAlertsInLastDay(userId) {
        const alerts = this.alertsPerUser.get(userId) || [];
        const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
        return alerts.filter((a) => a.timestamp > oneDayAgo).length;
    }
    determineSeverity(score) {
        if (score > 0.9)
            return 'critical';
        if (score > 0.8)
            return 'high';
        if (score > 0.65)
            return 'medium';
        return 'low';
    }
    generateAlerts(event, anomalyScore) {
        const alerts = [];
        const threshold = this.config.anomalyScoreThreshold;
        if (anomalyScore.overallScore < threshold) {
            return alerts;
        }
        const severity = this.determineSeverity(anomalyScore.overallScore);
        const topAnomaly = anomalyScore.topAnomalies[0];
        const alert = {
            alertId: `alert-${event.sessionId}-${Date.now()}`,
            userId: event.userId,
            sessionId: event.sessionId,
            timestamp: Date.now(),
            severity,
            title: `Anomaly detected: ${topAnomaly?.dimension || 'Unusual access pattern'}`,
            description: topAnomaly?.description || 'Session access pattern deviates from baseline',
            anomalyType: topAnomaly?.dimension || 'composite',
            anomalyScore,
            action: severity === 'critical' ? 'mfa-challenge' : 'notify',
        };
        alerts.push(alert);
        return alerts;
    }
    async detectAnomalies(event, recentEvents) {
        const startTime = Date.now();
        try {
            const profile = await this.getOrCreateProfile(event.userId, recentEvents);
            if (!profile) {
                return {
                    sessionId: event.sessionId,
                    userId: event.userId,
                    timestamp: event.timestamp,
                    isAnomaly: false,
                    alerts: [],
                    processingTimeMs: Date.now() - startTime,
                };
            }
            const anomalyScore = this.engine.scoreSession(event, profile);
            let alerts = [];
            const isAnomaly = anomalyScore.overallScore >= this.config.anomalyScoreThreshold;
            if (isAnomaly) {
                alerts = this.generateAlerts(event, anomalyScore);
                const alertCount = this.getAlertsInLastDay(event.userId);
                if (alertCount >= this.config.maxAlertsPerUserPerDay) {
                    alerts = alerts.slice(0, Math.max(1, this.config.maxAlertsPerUserPerDay - alertCount));
                }
                const userAlerts = this.alertsPerUser.get(event.userId) || [];
                for (const alert of alerts) {
                    userAlerts.push({ timestamp: alert.timestamp, sessionId: alert.sessionId });
                }
                this.alertsPerUser.set(event.userId, userAlerts);
            }
            return {
                sessionId: event.sessionId,
                userId: event.userId,
                timestamp: event.timestamp,
                isAnomaly,
                anomalyScore: isAnomaly ? anomalyScore : undefined,
                alerts,
                processingTimeMs: Date.now() - startTime,
            };
        }
        catch (error) {
            return {
                sessionId: event.sessionId,
                userId: event.userId,
                timestamp: event.timestamp,
                isAnomaly: false,
                alerts: [],
                processingTimeMs: Date.now() - startTime,
            };
        }
    }
    async retrain(userId, recentEvents) {
        if (recentEvents.length >= this.config.minSamplesForProfile) {
            const profile = this.engine.buildProfile(userId, recentEvents);
            this.profiles.set(userId, profile);
        }
    }
    getProfileStats(userId) {
        const profile = this.profiles.get(userId);
        return profile ? {
            userId: profile.userId,
            profileId: profile.profileId,
            sampleCount: profile.sampleCount,
            loginTimes: profile.loginTimes,
            sessionDuration: profile.sessionDuration,
            trainingData: profile.trainingData,
        } : null;
    }
    clearCache() {
        this.profiles.clear();
        this.alertsPerUser.clear();
    }
}
let instance = null;
export function getAnomalyDetectionService(config) {
    if (!instance) {
        instance = new AnomalyDetectionService(config);
    }
    return instance;
}
//# sourceMappingURL=service.js.map