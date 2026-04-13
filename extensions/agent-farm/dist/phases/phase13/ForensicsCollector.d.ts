/**
 * Forensics Collector
 *
 * Comprehensive security event logging and investigation with:
 * - Immutable event log storage
 * - Full audit trail capture
 * - Tamper detection
 * - Investigation support
 * - Evidence preservation
 * - Compliance reporting
 */
export declare enum EventCategory {
    AUTHENTICATION = "authentication",
    AUTHORIZATION = "authorization",
    DATA_ACCESS = "data_access",
    CONFIGURATION = "configuration",
    SYSTEM = "system",
    NETWORK = "network",
    APPLICATION = "application",
    INCIDENT = "incident"
}
export interface ForensicEvent {
    eventId: string;
    timestamp: Date;
    category: EventCategory;
    severity: number;
    userId?: string;
    deviceId?: string;
    ipAddress?: string;
    action: string;
    resource: string;
    result: 'success' | 'failure' | 'partial';
    details: Record<string, any>;
    userAgent?: string;
    correlationId?: string;
    eventHash: string;
    chain: string[];
}
export interface InvestigationCase {
    caseId: string;
    title: string;
    createdAt: Date;
    createdBy: string;
    description: string;
    severity: number;
    linkedEvents: string[];
    findings: string[];
    status: 'open' | 'closed' | 'escalated';
    resolution?: string;
    evidence: EvidenceItem[];
}
export interface EvidenceItem {
    evidenceId: string;
    caseId: string;
    eventId: string;
    timestamp: Date;
    description: string;
    preservationTimestamp: Date;
    hash: string;
    metadata: Record<string, any>;
}
export interface ComplianceReport {
    reportId: string;
    reportType: string;
    periodStart: Date;
    periodEnd: Date;
    generatedAt: Date;
    totalEvents: number;
    failedEvents: number;
    criticalEvents: number;
    summary: string;
    sections: Map<string, string>;
}
/**
 * ForensicsCollector - Comprehensive logging and investigation support
 *
 * Features:
 * - Immutable event log (write-once)
 * - Tamper detection via hash chains
 * - Full audit trail
 * - Investigation case management
 * - Evidence preservation
 * - Compliance reporting (SOC2, HIPAA, PCI-DSS, etc.)
 */
export declare class ForensicsCollector {
    private eventLog;
    private investigationCases;
    private evidence;
    private lastEventHash;
    private readonly maxLogSize;
    private readonly eventRetentionDays;
    private complianceMetadata;
    constructor();
    /**
     * Initialize compliance framework metadata
     */
    private initializeComplianceMetadata;
    /**
     * Calculate SHA-256 hash (simulated)
     * In production: use crypto.subtle.digest
     */
    private calculateHash;
    /**
     * Record forensic event (write-once immutable log)
     */
    recordEvent(category: EventCategory, action: string, resource: string, result: 'success' | 'failure' | 'partial', options?: {
        userId?: string;
        deviceId?: string;
        ipAddress?: string;
        severity?: number;
        details?: Record<string, any>;
        userAgent?: string;
        correlationId?: string;
    }): string;
    /**
     * Verify event integrity using hash chain
     */
    verifyEventIntegrity(eventId: string): {
        valid: boolean;
        reason?: string;
    };
    /**
     * Create investigation case
     */
    createInvestigationCase(title: string, description: string, createdBy: string, severity?: number): string;
    /**
     * Link event to investigation case
     */
    linkEventToCase(caseId: string, eventId: string): boolean;
    /**
     * Add finding to investigation case
     */
    addFinding(caseId: string, finding: string): boolean;
    /**
     * Preserve evidence from event
     */
    preserveEvidence(caseId: string, eventId: string, description: string, metadata?: Record<string, any>): string;
    /**
     * Search events by criteria
     */
    searchEvents(criteria: {
        category?: EventCategory;
        userId?: string;
        deviceId?: string;
        ipAddress?: string;
        result?: 'success' | 'failure' | 'partial';
        startTime?: Date;
        endTime?: Date;
        minSeverity?: number;
        limit?: number;
    }): ForensicEvent[];
    /**
     * Generate compliance report
     */
    generateComplianceReport(reportType: 'SOC2' | 'HIPAA' | 'PCI-DSS' | 'GDPR', periodStart: Date, periodEnd: Date): ComplianceReport;
    /**
     * Get investigation case details
     */
    getInvestigationCase(caseId: string): InvestigationCase | undefined;
    /**
     * Close investigation case
     */
    closeInvestigationCase(caseId: string, resolution: string): boolean;
    /**
     * Get forensics statistics
     */
    getForensicsStats(): {
        totalEvents: number;
        totalCases: number;
        activeCases: number;
        totalEvidence: number;
        failureRate: number;
        criticalEventCount: number;
        oldestEvent?: Date;
        newestEvent?: Date;
    };
    /**
     * Retrieve events for audit by correlation ID
     */
    getEventsByCorrelationId(correlationId: string): ForensicEvent[];
    /**
     * Export evidence from case
     */
    getEvidenceFromCase(caseId: string): EvidenceItem[];
    /**
     * Archive events older than retention period (for compliance)
     */
    archiveOldEvents(): {
        archived: number;
        retention_policy: string;
    };
}
//# sourceMappingURL=ForensicsCollector.d.ts.map
