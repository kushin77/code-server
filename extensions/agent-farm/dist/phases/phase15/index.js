"use strict";
/**
 * Phase 15: Production Deployment & Rollout
 * Comprehensive production deployment orchestration system
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEPLOYMENT_STAGES = exports.PRODUCTION_SLO_TARGETS = exports.DEFAULT_PHASE_15_CONFIG = exports.PHASE_15_CAPABILITIES = exports.IncidentAutoResponseSystem = exports.SLODrivenDeploymentEngine = exports.ComplianceAuditSystem = exports.TrafficManagementSystem = exports.BlueGreenDeploymentManager = exports.HealthMonitoringSystem = exports.CanaryDeploymentEngine = exports.DeploymentOrchestrator = void 0;
// Deployment Orchestrator exports
var DeploymentOrchestrator_1 = require("./DeploymentOrchestrator");
Object.defineProperty(exports, "DeploymentOrchestrator", { enumerable: true, get: function () { return DeploymentOrchestrator_1.DeploymentOrchestrator; } });
// Canary Deployment Engine exports
var CanaryDeploymentEngine_1 = require("./CanaryDeploymentEngine");
Object.defineProperty(exports, "CanaryDeploymentEngine", { enumerable: true, get: function () { return CanaryDeploymentEngine_1.CanaryDeploymentEngine; } });
// Health Monitoring System exports
var HealthMonitoringSystem_1 = require("./HealthMonitoringSystem");
Object.defineProperty(exports, "HealthMonitoringSystem", { enumerable: true, get: function () { return HealthMonitoringSystem_1.HealthMonitoringSystem; } });
// Blue-Green Deployment Manager exports
var BlueGreenDeploymentManager_1 = require("./BlueGreenDeploymentManager");
Object.defineProperty(exports, "BlueGreenDeploymentManager", { enumerable: true, get: function () { return BlueGreenDeploymentManager_1.BlueGreenDeploymentManager; } });
// Traffic Management System exports
var TrafficManagementSystem_1 = require("./TrafficManagementSystem");
Object.defineProperty(exports, "TrafficManagementSystem", { enumerable: true, get: function () { return TrafficManagementSystem_1.TrafficManagementSystem; } });
// Compliance & Audit System exports
var ComplianceAuditSystem_1 = require("./ComplianceAuditSystem");
Object.defineProperty(exports, "ComplianceAuditSystem", { enumerable: true, get: function () { return ComplianceAuditSystem_1.ComplianceAuditSystem; } });
// SLO-Driven Deployment Engine exports
var SLODrivenDeploymentEngine_1 = require("./SLODrivenDeploymentEngine");
Object.defineProperty(exports, "SLODrivenDeploymentEngine", { enumerable: true, get: function () { return SLODrivenDeploymentEngine_1.SLODrivenDeploymentEngine; } });
// Incident Auto-Response System exports
var IncidentAutoResponseSystem_1 = require("./IncidentAutoResponseSystem");
Object.defineProperty(exports, "IncidentAutoResponseSystem", { enumerable: true, get: function () { return IncidentAutoResponseSystem_1.IncidentAutoResponseSystem; } });
/**
 * Provides comprehensive capabilities overview for Phase 15
 */
exports.PHASE_15_CAPABILITIES = {
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
exports.DEFAULT_PHASE_15_CONFIG = {
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
exports.PRODUCTION_SLO_TARGETS = {
    authenticationLatencyP99: 100, // ms
    policyEvaluationP99: 50, // ms
    threatDetectionThroughput: 5000, // events/sec
    dataExfiltrationPrevention: 'blocking-gt-100mb',
    errorRate: 1, // percentage
    availability: 99.95, // percentage
};
/**
 * Deployment stages and their characteristics
 */
exports.DEPLOYMENT_STAGES = {
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
//# sourceMappingURL=index.js.map