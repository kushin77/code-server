/**
 * Phase 15: SLO-Driven Deployment Engine
 * Metric-based deployment gate decisions
 */
import { SystemMetrics } from './DeploymentOrchestrator';
export interface SLOTargets {
    authenticationLatencyP99: number;
    policyEvaluationP99: number;
    threatDetectionThroughput: number;
    dataExfiltrationPrevention: string;
    errorRate: number;
    availability: number;
}
export interface SLOValidation {
    meetsAuthLatency: boolean;
    meetsPolicyEval: boolean;
    meetsThreatDetection: boolean;
    meetsErrorRate: boolean;
    meetsAvailability: boolean;
    overallCompliance: boolean;
    violations: SLOViolation[];
}
export interface SLOViolation {
    metric: string;
    target: number;
    actual: number;
    severity: 'warning' | 'critical';
}
export interface GateValidation {
    canProgress: boolean;
    violations: string[];
    recommendations: string[];
    nextCheckTime?: Date;
}
export interface MetricsComparison {
    latencyImprovement: number;
    errorRateImprovement: number;
    availabilityImprovement: number;
    overallImprovement: number;
    degradedMetrics: string[];
}
export interface SLOReport {
    period: {
        start: Date;
        end: Date;
    };
    metrics: SystemMetrics[];
    violations: SLOViolation[];
    compliancePercentage: number;
    observations: string[];
    recommendations: string[];
}
export interface TimeWindow {
    start: Date;
    end: Date;
}
export declare class SLODrivenDeploymentEngine {
    private sloTargets;
    private baselineMetrics;
    private metricsHistory;
    validateSLOCompliance(metrics: SystemMetrics): Promise<SLOValidation>;
    checkDeploymentGates(stage: string, metrics: SystemMetrics): Promise<GateValidation>;
    establishBaselineMetrics(environment: 'staging' | 'production'): Promise<void>;
    updateBaselineMetrics(metrics: SystemMetrics): Promise<void>;
    compareMetricsWithBaseline(current: SystemMetrics): Promise<MetricsComparison>;
    updateSLOThresholds(slos: SLOTargets): Promise<void>;
    getCurrentSLOThresholds(): Promise<SLOTargets>;
    generateSLOReport(timeWindow: TimeWindow): Promise<SLOReport>;
    detectSLOViolations(metrics: SystemMetrics): Promise<SLOViolation[]>;
}
//# sourceMappingURL=SLODrivenDeploymentEngine.d.ts.map
