/**
 * Phase 15: Production Deployment & Rollout
 * Comprehensive production deployment orchestration system
 */

// Deployment Orchestrator exports
export {
  DeploymentOrchestrator,
  DeploymentConfig,
  StagedDeploymentConfig,
  CanaryConfig,
  ProgressiveConfig,
  ProductionConfig,
  DeploymentResult,
  StageResult,
  CanaryResult,
  RollbackResult,
  SystemMetrics,
  SLOValidation,
  DeploymentStatus,
  StageProgress,
  MetricsComparison,
  DeploymentReport,
  DeploymentStage,
} from './DeploymentOrchestrator';

// Canary Deployment Engine exports
export {
  CanaryDeploymentEngine,
  CanaryDeployment,
  CanaryMetrics,
  HealthEvaluation,
  PromotionResult,
  CanaryStatus,
  CanaryReport,
} from './CanaryDeploymentEngine';

// Health Monitoring System exports
export {
  HealthMonitoringSystem,
  HealthCheckResults,
  ComponentHealth,
  Anomaly,
  SeverityAssessment,
  RecoveryResult,
  HealthStatus,
  HealthReport,
  TimeWindow,
} from './HealthMonitoringSystem';

// Blue-Green Deployment Manager exports
export {
  BlueGreenDeploymentManager,
  EnvironmentState,
  EnvironmentMetrics,
  BlueGreenStatus,
  ValidationResult,
  SmokeTestResults,
  TrafficShiftResult,
  EnvironmentComparison,
} from './BlueGreenDeploymentManager';

// Traffic Management System exports
export {
  TrafficManagementSystem,
  TrafficRule,
  CircuitState,
  DeploymentTarget,
  TrafficMetrics,
  LoadBalancingResult,
  DrainResult,
  TrafficReport,
} from './TrafficManagementSystem';

// Compliance & Audit System exports
export {
  ComplianceAuditSystem,
  DeploymentAuditLog,
  AccessAuditLog,
  ConfigurationAuditLog,
  SOC2Report,
  DeploymentSummary,
  AuditTrail,
  ChangeLog,
  IntegrityVerification,
  ComplianceValidation,
  ComplianceRequirement,
  DateRange,
} from './ComplianceAuditSystem';

// SLO-Driven Deployment Engine exports
export {
  SLODrivenDeploymentEngine,
  SLOTargets,
  SLOValidation as SLOValidationEngine,
  SLOViolation,
  GateValidation,
  SLOReport,
} from './SLODrivenDeploymentEngine';

// Incident Auto-Response System exports
export {
  IncidentAutoResponseSystem,
  Incident,
  Runbook,
  RunbookStep,
  ResponseAction,
  RunbookContext,
  RunbookResult,
  ResponseResult,
  SeverityLevel,
  IncidentReport,
} from './IncidentAutoResponseSystem';

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
export const PHASE_15_CAPABILITIES: Phase15Capabilities = {
  multiStageDeployment: true,
  canaryDeployment: true,
  healthMonitoring: true,
  blueGreenSwitching: true,
  trafficManagement: true,
  complianceAudit: true,
  sloEnforcement: true,
  incidentResponse: true,
  totalModules: 8,
  totalLinesOfCode: 2200,
};

/**
 * Default Phase 15 configuration for production deployments
 */
export const DEFAULT_PHASE_15_CONFIG: Phase15Config = {
  deploymentStrategy: 'blue-green',
  rollbackStrategy: 'automatic',
  canaryPercentage: 5,
  progressiveStages: [25, 50, 100],
  healthCheckInterval: 30,
  sloComplianceRequired: true,
  complianceReporting: true,
  incidentAutoResponse: true,
};

/**
 * SLO Targets for production systems
 */
export const PRODUCTION_SLO_TARGETS = {
  authenticationLatencyP99: 100,       // ms
  policyEvaluationP99: 50,             // ms
  threatDetectionThroughput: 5000,    // events/sec
  dataExfiltrationPrevention: 'blocking-gt-100mb',
  errorRate: 1,                        // percentage
  availability: 99.95,                 // percentage
};

/**
 * Deployment stages and their characteristics
 */
export const DEPLOYMENT_STAGES = {
  preValidation: {
    name: 'Pre-Deployment Validation',
    duration: 300,
    critical: true,
    autoProgress: false,
  },
  canary: {
    name: 'Canary Deployment',
    duration: 600,
    critical: true,
    autoProgress: true,
  },
  progressive: {
    name: 'Progressive Rollout',
    duration: 1200,
    critical: true,
    autoProgress: true,
  },
  production: {
    name: 'Production Promotion',
    duration: 600,
    critical: true,
    autoProgress: false,
  },
  postDeployment: {
    name: 'Post-Deployment Verification',
    duration: 300,
    critical: false,
    autoProgress: false,
  },
};
