/**
 * Phase 15: Compliance & Audit Logging
 * Full compliance audit trail and reporting
 */
export interface DeploymentAuditLog {
    timestamp: Date;
    deploymentId: string;
    action: 'deploy' | 'rollback' | 'pause' | 'resume';
    version: string;
    actor: string;
    ipAddress: string;
    result: 'success' | 'failure';
    details: string;
}
export interface AccessAuditLog {
    timestamp: Date;
    userId: string;
    action: string;
    resource: string;
    ipAddress: string;
    result: 'allowed' | 'denied';
    reason?: string;
}
export interface ConfigurationAuditLog {
    timestamp: Date;
    source: string;
    configKey: string;
    oldValue: string;
    newValue: string;
    actor: string;
    approved: boolean;
}
export interface SOC2Report {
    period: {
        start: Date;
        end: Date;
    };
    deployments: DeploymentSummary[];
    incidentCount: number;
    sloViolations: number;
    securityEvents: number;
    complianceStatus: 'compliant' | 'non-compliant';
    recommendations: string[];
}
export interface DeploymentSummary {
    deploymentId: string;
    version: string;
    timestamp: Date;
    actor: string;
    status: 'success' | 'failure' | 'rolled-back';
    duration: number;
}
export interface AuditTrail {
    startTime: Date;
    endTime: Date;
    logs: (DeploymentAuditLog | AccessAuditLog | ConfigurationAuditLog)[];
    total: number;
}
export interface ChangeLog {
    startTime: Date;
    endTime: Date;
    changes: ConfigurationAuditLog[];
    total: number;
}
export interface IntegrityVerification {
    verified: boolean;
    startTime: Date;
    endTime: Date;
    logsChecked: number;
    integrityViolations: string[];
}
export interface ComplianceValidation {
    compliant: boolean;
    requirements: ComplianceRequirement[];
    violations: string[];
}
export interface ComplianceRequirement {
    requirement: string;
    status: 'met' | 'not-met' | 'partial';
    evidence: string;
}
export interface DateRange {
    start: Date;
    end: Date;
}
export declare class ComplianceAuditSystem {
    private deploymentLogs;
    private accessLogs;
    private configurationLogs;
    logDeploymentAction(action: DeploymentAuditLog): Promise<void>;
    logAccessEvent(event: AccessAuditLog): Promise<void>;
    logConfigurationChange(change: ConfigurationAuditLog): Promise<void>;
    generateSOC2Report(dateRange: DateRange): Promise<SOC2Report>;
    generateAuditTrail(dateRange: DateRange): Promise<AuditTrail>;
    generateChangeLog(dateRange: DateRange): Promise<ChangeLog>;
    verifyAuditIntegrity(start: Date, end: Date): Promise<IntegrityVerification>;
    validateComplianceRequirements(): Promise<ComplianceValidation>;
    exportAuditLogs(format: 'json' | 'csv' | 'syslog'): Promise<Buffer>;
}
//# sourceMappingURL=ComplianceAuditSystem.d.ts.map
