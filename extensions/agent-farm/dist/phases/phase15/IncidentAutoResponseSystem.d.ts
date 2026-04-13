/**
 * Phase 15: Incident Auto-Response & Runbook Automation
 * Automated incident response execution
 */
import { SystemMetrics } from './DeploymentOrchestrator';
export interface Incident {
    incidentId: string;
    detectionTime: Date;
    type: 'deployment-failure' | 'health-degradation' | 'slo-violation';
    severity: 'low' | 'medium' | 'high' | 'critical';
    metrics: SystemMetrics;
    affectedComponents: string[];
    autoResponseExecuted: boolean;
}
export interface Runbook {
    runbookId: string;
    name: string;
    incidentType: string;
    steps: RunbookStep[];
    preconditions: string[];
    successCriteria: string[];
    estimatedDuration: number;
}
export interface RunbookStep {
    stepId: string;
    action: string;
    parameters: Record<string, any>;
    timeout: number;
    retryPolicy: 'none' | 'exponential' | 'fixed';
    maxRetries: number;
    onFailure: 'continue' | 'abort' | 'escalate';
}
export interface ResponseAction {
    action: 'auto-recover' | 'rollback' | 'escalate' | 'manual-intervention';
    confidence: number;
    reason: string;
    estimatedTime: number;
}
export interface RunbookContext {
    incidentId: string;
    metrics: SystemMetrics;
    affectedComponents: string[];
    previousAttempts?: number;
}
export interface RunbookResult {
    success: boolean;
    runbookId: string;
    duration: number;
    stepsExecuted: number;
    failedSteps: string[];
    recommendations: string[];
}
export interface RecoveryResult {
    success: boolean;
    recoveryAction: string;
    duration: number;
    metricsAfter: SystemMetrics;
}
export interface ResponseResult {
    success: boolean;
    incidentId: string;
    responseAction: ResponseAction;
    autoResponseResult?: RunbookResult | RecoveryResult;
    manualInterventionRequired: boolean;
}
export interface SeverityLevel {
    level: 'low' | 'medium' | 'high' | 'critical';
    score: number;
    escalationActions: string[];
}
export interface IncidentReport {
    incidentId: string;
    type: string;
    detectionTime: Date;
    resolutionTime: Date;
    duration: number;
    severity: SeverityLevel;
    responseAction: ResponseAction;
    rootCause: string;
    resolution: string;
    lessonsLearned: string[];
}
export declare class IncidentAutoResponseSystem {
    private incidents;
    private runbooks;
    private incidentHistory;
    constructor();
    detectIncident(metrics: SystemMetrics): Promise<Incident | null>;
    executeAutoResponse(incident: Incident): Promise<ResponseResult>;
    registerApplyRunbook(runbook: Runbook): Promise<void>;
    executeRunbook(runbookId: string, context: RunbookContext): Promise<RunbookResult>;
    determineResponseAction(incident: Incident): Promise<ResponseAction>;
    assessIncidentSeverity(incident: Incident): Promise<SeverityLevel>;
    escalateIncident(incident: Incident, severity: SeverityLevel): Promise<void>;
    attemptAutoRecovery(incident: Incident): Promise<RecoveryResult>;
    triggerManualIntervention(incident: Incident): Promise<void>;
    generateIncidentReport(incidentId: string): Promise<IncidentReport>;
    getIncidentHistory(timeWindow: {
        start: Date;
        end: Date;
    }): Promise<Incident[]>;
    private registerDefaultRunbooks;
    private generateIncidentId;
}
//# sourceMappingURL=IncidentAutoResponseSystem.d.ts.map