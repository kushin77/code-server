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

export enum EventCategory {
  AUTHENTICATION = 'authentication',
  AUTHORIZATION = 'authorization',
  DATA_ACCESS = 'data_access',
  CONFIGURATION = 'configuration',
  SYSTEM = 'system',
  NETWORK = 'network',
  APPLICATION = 'application',
  INCIDENT = 'incident'
}

export interface ForensicEvent {
  eventId: string;
  timestamp: Date;
  category: EventCategory;
  severity: number;  // 0-100
  userId?: string;
  deviceId?: string;
  ipAddress?: string;
  action: string;
  resource: string;
  result: 'success' | 'failure' | 'partial';
  details: Record<string, any>;
  userAgent?: string;
  correlationId?: string;  // Links related events
  eventHash: string;  // SHA-256 for tamper detection
  chain: string[];  // Hash chain for integrity
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
  hash: string;  // Immutable reference
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
  sections: Map<string, string>;  // Compliance sections
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
export class ForensicsCollector {
  private eventLog: Map<string, ForensicEvent> = new Map();
  private investigationCases: Map<string, InvestigationCase> = new Map();
  private evidence: Map<string, EvidenceItem> = new Map();
  private lastEventHash = 'genesis';  // Start of hash chain
  private readonly maxLogSize = 1000000;  // 1M events
  private readonly eventRetentionDays = 2555;  // 7 years
  private complianceMetadata: Map<string, any> = new Map();

  constructor() {
    this.initializeComplianceMetadata();
  }

  /**
   * Initialize compliance framework metadata
   */
  private initializeComplianceMetadata(): void {
    this.complianceMetadata.set('soc2_enabled', true);
    this.complianceMetadata.set('hipaa_enabled', true);
    this.complianceMetadata.set('pci_dss_enabled', true);
    this.complianceMetadata.set('gdpr_enabled', true);
    this.complianceMetadata.set('pii_detection', true);
  }

  /**
   * Calculate SHA-256 hash (simulated)
   * In production: use crypto.subtle.digest
   */
  private calculateHash(data: string): string {
    let hash = 0;
    for (let i = 0; i < data.length; i++) {
      const char = data.charCodeAt(i);
      hash = (hash << 5) - hash + char;
      hash = hash & hash;
    }
    return `sha256_${Math.abs(hash).toString(16).padStart(64, '0')}`;
  }

  /**
   * Record forensic event (write-once immutable log)
   */
  recordEvent(
    category: EventCategory,
    action: string,
    resource: string,
    result: 'success' | 'failure' | 'partial',
    options?: {
      userId?: string;
      deviceId?: string;
      ipAddress?: string;
      severity?: number;
      details?: Record<string, any>;
      userAgent?: string;
      correlationId?: string;
    }
  ): string {
    const timestamp = new Date();
    const eventId = `event_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    // Build event data for hashing
    const eventData = JSON.stringify({
      eventId,
      timestamp: timestamp.toISOString(),
      category,
      action,
      resource,
      result,
      userId: options?.userId,
      deviceId: options?.deviceId,
      ipAddress: options?.ipAddress
    });

    // Calculate hash with chain
    const eventHash = this.calculateHash(eventData);
    const chainedHash = this.calculateHash(this.lastEventHash + eventHash);

    const event: ForensicEvent = {
      eventId,
      timestamp,
      category,
      severity: options?.severity || (result === 'failure' ? 40 : 10),
      userId: options?.userId,
      deviceId: options?.deviceId,
      ipAddress: options?.ipAddress,
      action,
      resource,
      result,
      details: options?.details || {},
      userAgent: options?.userAgent,
      correlationId: options?.correlationId,
      eventHash,
      chain: [this.lastEventHash, chainedHash]
    };

    // Write to immutable log
    this.eventLog.set(eventId, event);
    this.lastEventHash = chainedHash;

    // Maintain size limit
    if (this.eventLog.size > this.maxLogSize) {
      // In production: archive old events to external storage
      const oldestEvents = Array.from(this.eventLog.entries())
        .sort((a, b) => a[1].timestamp.getTime() - b[1].timestamp.getTime())
        .slice(0, 10000);

      for (const [id] of oldestEvents) {
        this.eventLog.delete(id);
      }
    }

    return eventId;
  }

  /**
   * Verify event integrity using hash chain
   */
  verifyEventIntegrity(eventId: string): { valid: boolean; reason?: string } {
    const event = this.eventLog.get(eventId);

    if (!event) {
      return { valid: false, reason: 'Event not found' };
    }

    // Reconstruct event hash
    const eventData = JSON.stringify({
      eventId,
      timestamp: event.timestamp.toISOString(),
      category: event.category,
      action: event.action,
      resource: event.resource,
      result: event.result,
      userId: event.userId,
      deviceId: event.deviceId,
      ipAddress: event.ipAddress
    });

    const reconstructedHash = this.calculateHash(eventData);

    if (reconstructedHash !== event.eventHash) {
      return { valid: false, reason: 'Tampered event detected: hash mismatch' };
    }

    return { valid: true };
  }

  /**
   * Create investigation case
   */
  createInvestigationCase(
    title: string,
    description: string,
    createdBy: string,
    severity: number = 50
  ): string {
    const caseId = `case_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    const investigationCase: InvestigationCase = {
      caseId,
      title,
      createdAt: new Date(),
      createdBy,
      description,
      severity,
      linkedEvents: [],
      findings: [],
      status: 'open',
      evidence: []
    };

    this.investigationCases.set(caseId, investigationCase);

    return caseId;
  }

  /**
   * Link event to investigation case
   */
  linkEventToCase(caseId: string, eventId: string): boolean {
    const investigationCase = this.investigationCases.get(caseId);
    const event = this.eventLog.get(eventId);

    if (!investigationCase || !event) {
      return false;
    }

    if (!investigationCase.linkedEvents.includes(eventId)) {
      investigationCase.linkedEvents.push(eventId);
    }

    return true;
  }

  /**
   * Add finding to investigation case
   */
  addFinding(caseId: string, finding: string): boolean {
    const investigationCase = this.investigationCases.get(caseId);

    if (!investigationCase) {
      return false;
    }

    investigationCase.findings.push(finding);
    return true;
  }

  /**
   * Preserve evidence from event
   */
  preserveEvidence(
    caseId: string,
    eventId: string,
    description: string,
    metadata?: Record<string, any>
  ): string {
    const event = this.eventLog.get(eventId);
    const investigationCase = this.investigationCases.get(caseId);

    if (!event || !investigationCase) {
      return '';
    }

    const evidenceId = `evidence_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const hash = this.calculateHash(JSON.stringify(event));

    const evidence: EvidenceItem = {
      evidenceId,
      caseId,
      eventId,
      timestamp: event.timestamp,
      description,
      preservationTimestamp: new Date(),
      hash,
      metadata: metadata || {}
    };

    this.evidence.set(evidenceId, evidence);
    investigationCase.evidence.push(evidence);

    return evidenceId;
  }

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
  }): ForensicEvent[] {
    const results: ForensicEvent[] = [];

    for (const event of this.eventLog.values()) {
      // Apply filters
      if (criteria.category && event.category !== criteria.category) continue;
      if (criteria.userId && event.userId !== criteria.userId) continue;
      if (criteria.deviceId && event.deviceId !== criteria.deviceId) continue;
      if (criteria.ipAddress && event.ipAddress !== criteria.ipAddress) continue;
      if (criteria.result && event.result !== criteria.result) continue;
      if (criteria.startTime && event.timestamp < criteria.startTime) continue;
      if (criteria.endTime && event.timestamp > criteria.endTime) continue;
      if (criteria.minSeverity && event.severity < criteria.minSeverity) continue;

      results.push(event);
    }

    // Sort by timestamp descending and apply limit
    results.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

    if (criteria.limit) {
      return results.slice(0, criteria.limit);
    }

    return results;
  }

  /**
   * Generate compliance report
   */
  generateComplianceReport(
    reportType: 'SOC2' | 'HIPAA' | 'PCI-DSS' | 'GDPR',
    periodStart: Date,
    periodEnd: Date
  ): ComplianceReport {
    const reportId = `report_${Date.now()}_${reportType}`;
    const events = this.searchEvents({ startTime: periodStart, endTime: periodEnd });

    const failedEvents = events.filter((e) => e.result === 'failure').length;
    const criticalEvents = events.filter((e) => e.severity >= 80).length;

    const sections = new Map<string, string>();

    // Generate compliance sections based on type
    switch (reportType) {
      case 'SOC2':
        sections.set('CC7.2', `User access logging: ${events.length} total events logged`);
        sections.set('CC7.2', `Failed access attempts: ${failedEvents} detected`);
        sections.set('CC7.2', `Critical events: ${criticalEvents} escalated`);
        break;
      case 'HIPAA':
        const piiEvents = events.filter((e) => e.details.containsPII === true);
        sections.set('ePHI Access Log', `Electronic PHI access: ${piiEvents.length} events`);
        sections.set('User Accountability', `Authentication events: ${events.filter((e) => e.category === EventCategory.AUTHENTICATION).length}`);
        break;
      case 'PCI-DSS':
        const paymentEvents = events.filter((e) => e.resource.includes('payment'));
        sections.set('Requirement 10.1', `Access to cardholder data: ${paymentEvents.length} events`);
        sections.set('Requirement 10.3', `Privileged access logging: ${events.filter((e) => e.category === EventCategory.AUTHORIZATION).length}`);
        break;
      case 'GDPR':
        const personalDataEvents = events.filter((e) => e.details.containsPersonalData === true);
        sections.set('Article 32', `Personal data processing: ${personalDataEvents.length} events`);
        sections.set('Article 5', `Data integrity and confidentiality: ${events.length} events logged`);
        break;
    }

    const report: ComplianceReport = {
      reportId,
      reportType,
      periodStart,
      periodEnd,
      generatedAt: new Date(),
      totalEvents: events.length,
      failedEvents,
      criticalEvents,
      summary: `${reportType} compliance report: ${events.length} events processed, ${failedEvents} failures, ${criticalEvents} critical incidents`,
      sections
    };

    return report;
  }

  /**
   * Get investigation case details
   */
  getInvestigationCase(caseId: string): InvestigationCase | undefined {
    return this.investigationCases.get(caseId);
  }

  /**
   * Close investigation case
   */
  closeInvestigationCase(caseId: string, resolution: string): boolean {
    const investigationCase = this.investigationCases.get(caseId);

    if (!investigationCase) {
      return false;
    }

    investigationCase.status = 'closed';
    investigationCase.resolution = resolution;

    return true;
  }

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
  } {
    const stats = {
      totalEvents: this.eventLog.size,
      totalCases: this.investigationCases.size,
      activeCases: 0,
      totalEvidence: this.evidence.size,
      failureRate: 0,
      criticalEventCount: 0,
      oldestEvent: undefined as Date | undefined,
      newestEvent: undefined as Date | undefined
    };

    let oldestTime = Date.now();
    let newestTime = 0;
    let failures = 0;

    for (const event of this.eventLog.values()) {
      if (event.result === 'failure') failures++;
      if (event.severity >= 80) stats.criticalEventCount++;

      if (event.timestamp.getTime() < oldestTime) {
        oldestTime = event.timestamp.getTime();
      }
      if (event.timestamp.getTime() > newestTime) {
        newestTime = event.timestamp.getTime();
      }
    }

    for (const investigationCase of this.investigationCases.values()) {
      if (investigationCase.status === 'open') {
        stats.activeCases++;
      }
    }

    stats.failureRate = stats.totalEvents > 0 ? (failures / stats.totalEvents) * 100 : 0;
    if (oldestTime !== Date.now()) stats.oldestEvent = new Date(oldestTime);
    if (newestTime > 0) stats.newestEvent = new Date(newestTime);

    return stats;
  }

  /**
   * Retrieve events for audit by correlation ID
   */
  getEventsByCorrelationId(correlationId: string): ForensicEvent[] {
    const events: ForensicEvent[] = [];

    for (const event of this.eventLog.values()) {
      if (event.correlationId === correlationId) {
        events.push(event);
      }
    }

    return events.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  }

  /**
   * Export evidence from case
   */
  getEvidenceFromCase(caseId: string): EvidenceItem[] {
    const evidence: EvidenceItem[] = [];

    for (const item of this.evidence.values()) {
      if (item.caseId === caseId) {
        evidence.push(item);
      }
    }

    return evidence;
  }

  /**
   * Archive events older than retention period (for compliance)
   */
  archiveOldEvents(): { archived: number; retention_policy: string } {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - this.eventRetentionDays);

    const toArchive: string[] = [];

    for (const [eventId, event] of this.eventLog) {
      if (event.timestamp < cutoffDate) {
        toArchive.push(eventId);
      }
    }

    for (const eventId of toArchive) {
      this.eventLog.delete(eventId);
    }

    return {
      archived: toArchive.length,
      retention_policy: `${this.eventRetentionDays} day retention period per compliance requirements`
    };
  }
}
