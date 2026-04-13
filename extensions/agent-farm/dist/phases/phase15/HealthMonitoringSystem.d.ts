/**
 * Phase 15: Health Monitoring & Rollback System
 * Real-time health detection and automatic recovery
 */
import { SystemMetrics } from './DeploymentOrchestrator';
export interface HealthCheckResults {
    apiHealth: ComponentHealth;
    databaseHealth: ComponentHealth;
    cacheHealth: ComponentHealth;
    storageHealth: ComponentHealth;
    overallHealth: 'healthy' | 'degraded' | 'critical';
    timestamp: Date;
}
export interface ComponentHealth {
    component: string;
    status: 'healthy' | 'degraded' | 'failed';
    responseTime: number;
    errorRate: number;
    lastCheck: Date;
    healthScore: number;
}
export interface Anomaly {
    type: 'latency' | 'error-rate' | 'throughput' | 'resource-usage';
    severity: 'low' | 'medium' | 'high' | 'critical';
    value: number;
    threshold: number;
    component?: string;
}
export interface SeverityAssessment {
    overallSeverity: 'low' | 'medium' | 'high' | 'critical';
    anomalyCount: number;
    recommendedAction: 'continue' | 'pause' | 'rollback';
    confidence: number;
}
export interface RecoveryResult {
    success: boolean;
    action: string;
    duration: number;
    metricsAfter: SystemMetrics;
}
export interface HealthStatus {
    environment: string;
    overallHealth: 'healthy' | 'degraded' | 'critical';
    componentHealths: ComponentHealth[];
    lastCheckTime: Date;
    nextCheckTime: Date;
}
export interface HealthReport {
    period: {
        start: Date;
        end: Date;
    };
    healthEvents: HealthCheckResults[];
    anomalies: Anomaly[];
    recoveryAttempts: RecoveryResult[];
    overallHealthScore: number;
    uptime: number;
    mttr: number;
}
export interface TimeWindow {
    start: Date;
    end: Date;
}
export declare class HealthMonitoringSystem {
    private healthHistory;
    private anomalyThresholds;
    private isMonitoring;
    private monitoredEnvironments;
    startHealthMonitoring(deploymentId: string): Promise<void>;
    stopHealthMonitoring(deploymentId: string): Promise<void>;
    runHealthChecks(environment: 'staging' | 'production'): Promise<HealthCheckResults>;
    validateComponentHealth(component: {
        name: string;
        address: string;
    }): Promise<ComponentHealth>;
    collectMetrics(environment: 'staging' | 'production'): Promise<SystemMetrics>;
    detectAnomalies(metrics: SystemMetrics): Promise<Anomaly[]>;
    assessAnomalySeverity(anomalies: Anomaly[]): Promise<SeverityAssessment>;
    triggerRollbackIfNeeded(metrics: SystemMetrics): Promise<boolean>;
    executeHealthRecovery(health: ComponentHealth): Promise<RecoveryResult>;
    getHealthStatus(environment: string): HealthStatus;
    generateHealthReport(timeWindow: TimeWindow): HealthReport;
    private recordHealthCheck;
    private calculateOverallHealth;
}
//# sourceMappingURL=HealthMonitoringSystem.d.ts.map
