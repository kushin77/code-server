/**
 * Phase 15: Production Deployment & Rollout
 * Comprehensive production deployment orchestration system
 */
export { DeploymentOrchestrator, DeploymentConfig, StagedDeploymentConfig, CanaryConfig, ProgressiveConfig, ProductionConfig, DeploymentResult, StageResult, CanaryResult, RollbackResult, SystemMetrics, SLOValidation, DeploymentStatus, StageProgress, MetricsComparison, DeploymentReport, DeploymentStage, } from './DeploymentOrchestrator';
export { CanaryDeploymentEngine, CanaryDeployment, CanaryMetrics, HealthEvaluation, PromotionResult, CanaryStatus, CanaryReport, } from './CanaryDeploymentEngine';
export { HealthMonitoringSystem, HealthCheckResults, ComponentHealth, Anomaly, SeverityAssessment, RecoveryResult, HealthStatus, HealthReport, TimeWindow, } from './HealthMonitoringSystem';
export { BlueGreenDeploymentManager, EnvironmentState, EnvironmentMetrics, BlueGreenStatus, ValidationResult, SmokeTestResults, TrafficShiftResult, EnvironmentComparison, } from './BlueGreenDeploymentManager';
export { TrafficManagementSystem, TrafficRule, CircuitState, DeploymentTarget, TrafficMetrics, LoadBalancingResult, DrainResult, TrafficReport, } from './TrafficManagementSystem';
export { ComplianceAuditSystem, DeploymentAuditLog, AccessAuditLog, ConfigurationAuditLog, SOC2Report, DeploymentSummary, AuditTrail, ChangeLog, IntegrityVerification, ComplianceValidation, ComplianceRequirement, DateRange, } from './ComplianceAuditSystem';
export { SLODrivenDeploymentEngine, SLOTargets, SLOValidation as SLOValidationEngine, SLOViolation, GateValidation, SLOReport, } from './SLODrivenDeploymentEngine';
export { IncidentAutoResponseSystem, Incident, Runbook, RunbookStep, ResponseAction, RunbookContext, RunbookResult, ResponseResult, SeverityLevel, IncidentReport, } from './IncidentAutoResponseSystem';
/**
 * Phase 15 Integrated Deployment System
 *
 * Provides complete production deployment orchestration with:
 * - Multi-stage deployment management (Orchestrator)
 * - Gradual rollout with validation (Canary Engine)
 * - Real-time health monitoring and automatic recovery (Health System)
 * - Zero-downtime environment switching (Blue-Green Manager)
 * - Intelligent traffic routing and failure isolation (Traffic Manager)
 * - Full compliance audit logging and SOC2 reporting (Compliance System)
 * - Metric-based deployment gates (SLO-Driven Engine)
 * - Automated incident response and runbook execution (Auto-Response System)
 */
export interface Phase15Config {
    deploymentStrategy: 'blue-green' | 'canary' | 'rolling';
    rollbackStrategy: 'automatic' | 'manual';
    canaryPercentage: number;
    progressiveStages: number[];
    healthCheckInterval: number;
    sloComplianceRequired: boolean;
    complianceReporting: boolean;
    incidentAutoResponse: boolean;
}
export interface Phase15Capabilities {
    multiStageDeployment: boolean;
    canaryDeployment: boolean;
    healthMonitoring: boolean;
    blueGreenSwitching: boolean;
    trafficManagement: boolean;
    complianceAudit: boolean;
    sloEnforcement: boolean;
    incidentResponse: boolean;
    totalModules: number;
    totalLinesOfCode: number;
}
/**
 * Provides comprehensive capabilities overview for Phase 15
 */
export declare const PHASE_15_CAPABILITIES: Phase15Capabilities;
/**
 * Default Phase 15 configuration for production deployments
 */
export declare const DEFAULT_PHASE_15_CONFIG: Phase15Config;
/**
 * SLO Targets for production systems
 */
export declare const PRODUCTION_SLO_TARGETS: {
    authenticationLatencyP99: number;
    policyEvaluationP99: number;
    threatDetectionThroughput: number;
    dataExfiltrationPrevention: string;
    errorRate: number;
    availability: number;
};
/**
 * Deployment stages and their characteristics
 */
export declare const DEPLOYMENT_STAGES: {
    preValidation: {
        name: string;
        duration: number;
        critical: boolean;
        autoProgress: boolean;
    };
    canary: {
        name: string;
        duration: number;
        critical: boolean;
        autoProgress: boolean;
    };
    progressive: {
        name: string;
        duration: number;
        critical: boolean;
        autoProgress: boolean;
    };
    production: {
        name: string;
        duration: number;
        critical: boolean;
        autoProgress: boolean;
    };
    postDeployment: {
        name: string;
        duration: number;
        critical: boolean;
        autoProgress: boolean;
    };
};
//# sourceMappingURL=index.d.ts.map