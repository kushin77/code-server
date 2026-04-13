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
export declare enum ThreatLevel {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4
}
export declare enum AnomalyType {
    BRUTE_FORCE = "brute_force",
    DATA_EXFILTRATION = "data_exfiltration",
    PRIVILEGE_ESCALATION = "privilege_escalation",
    LATERAL_MOVEMENT = "lateral_movement",
    MALWARE_ACTIVITY = "malware_activity",
    INSIDER_THREAT = "insider_threat",
    DDoS_ATTACK = "ddos_attack",
    INJECTION_ATTACK = "injection_attack",
    CONFIGURATION_DRIFT = "configuration_drift",
    ZERO_DAY = "zero_day"
}
export interface SecurityEvent {
    eventId: string;
    timestamp: Date;
    userId?: string;
    deviceId?: string;
    action: string;
    resource: string;
    result: 'success' | 'failure';
    metadata: Record<string, any>;
}
export interface AnomalySignal {
    signalId: string;
    anomalyType: AnomalyType;
    timestamp: Date;
    severity: ThreatLevel;
    riskScore: number;
    description: string;
    evidenceItems: EventEvidence[];
    mitigation?: string;
}
export interface EventEvidence {
    eventId: string;
    timestamp: Date;
    contributionToAnomaly: number;
    eventDescription: string;
}
export interface ThreatProfile {
    profileId: string;
    userId: string;
    baselineActivities: Map<string, number>;
    anomalies: AnomalySignal[];
    threatLevel: ThreatLevel;
    riskScore: number;
    lastUpdated: Date;
}
export interface DetectionRule {
    ruleId: string;
    name: string;
    anomalyType: AnomalyType;
    condition: (events: SecurityEvent[]) => boolean;
    riskScoreCalculator: (events: SecurityEvent[]) => number;
    enabled: boolean;
}
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
export declare class ThreatDetectionEngine {
    private rules;
    private eventStream;
    private anomalySignals;
    private userProfiles;
    private readonly maxEventStreamSize;
    private readonly baselineWindowDays;
    private readonly detectionInterval;
    constructor();
    /**
     * Register default detection rules
     */
    private registerDefaultRules;
    /**
     * Register a custom detection rule
     */
    registerRule(rule: DetectionRule): void;
    /**
     * Process incoming security event
     */
    processSecurityEvent(event: SecurityEvent): void;
    /**
     * Run all enabled detection rules
     */
    private runDetectionRules;
    /**
     * Calculate threat level from risk score
     */
    private calculateSeverity;
    /**
     * Update user threat profile
     */
    private updateUserProfile;
    /**
     * Get threat profile for user
     */
    getUserThreatProfile(userId: string): ThreatProfile | undefined;
    /**
     * Get all active anomalies above threshold
     */
    getActiveAnomalies(minSeverity?: ThreatLevel): AnomalySignal[];
    /**
     * Get detection statistics
     */
    getDetectionStats(): {
        totalEvents: number;
        totalAnomalies: number;
        criticalAnomalies: number;
        highAnomalies: number;
        rulesEnabled: number;
        activeProfiles: number;
    };
    /**
     * Get anomalies for specific type
     */
    getAnomaliesByType(anomalyType: AnomalyType): AnomalySignal[];
    /**
     * Clear old anomalies (maintenance)
     */
    clearOldAnomalies(maxAgeHours?: number): number;
    /**
     * Disable/enable detection rule
     */
    setRuleEnabled(ruleId: string, enabled: boolean): boolean;
}
//# sourceMappingURL=ThreatDetectionEngine.d.ts.map
