/**
 * Incident Response Manager
 * Handles incident creation, escalation, and resolution
 */

export type IncidentSeverity = 'critical' | 'high' | 'medium' | 'low';
export type IncidentStatus = 'new' | 'acknowledged' | 'investigating' | 'mitigating' | 'resolved' | 'closed';

export interface IncidentTimeline {
  timestamp: number;
  event: string;
  actor: string;
  details?: any;
}

export interface Incident {
  id: string;
  title: string;
  description: string;
  severity: IncidentSeverity;
  status: IncidentStatus;
  affectedServices: string[];
  rootCause?: string;
  assignedTo?: string;
  createdAt: number;
  acknowledgedAt?: number;
  resolvedAt?: number;
  closedAt?: number;
  detectionTime?: number; // time to detect incident
  mitigationTime?: number; // time to mitigate
  resolution?: string;
  timeline: IncidentTimeline[];
  tags: string[];
  runbookId?: string;
  relatedIncidents?: string[];
}

export interface IncidentMetrics {
  totalIncidents: number;
  criticalIncidents: number;
  avgDetectionTime: number; // milliseconds
  avgMitigationTime: number; // milliseconds
  avgResolutionTime: number; // milliseconds
  recurrenceRate: number; // % of repeated issues
  topAffectedServices: string[];
  topRootCauses: string[];
}

export class IncidentResponseManager {
  private incidents: Map<string, Incident> = new Map();
  private activeSeverityLock: boolean = false;
  private escalationChain: string[] = []; // escalation contacts
  private readonly maxHistoryLength = 1000;

  constructor() {}

  /**
   * Create new incident
   */
  createIncident(
    title: string,
    description: string,
    severity: IncidentSeverity,
    affectedServices: string[],
    detectionTime?: number
  ): Incident {
    const now = Date.now();
    const incident: Incident = {
      id: `inc-${now}-${Math.random().toString(36).substr(2, 9)}`,
      title,
      description,
      severity,
      status: 'new',
      affectedServices,
      createdAt: now,
      detectionTime,
      timeline: [
        {
          timestamp: now,
          event: 'Incident created',
          actor: 'system',
          details: { severity, affectedServices },
        },
      ],
      tags: [],
    };

    this.incidents.set(incident.id, incident);

    // Auto-escalate critical incidents
    if (severity === 'critical') {
      this.escalate(incident.id);
    }

    return incident;
  }

  /**
   * Acknowledge incident
   */
  acknowledgeIncident(incidentId: string, acknowledgedBy: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.status = 'acknowledged';
    incident.acknowledgedAt = Date.now();
    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Incident acknowledged',
      actor: acknowledgedBy,
    });

    return incident;
  }

  /**
   * Assign incident
   */
  assignIncident(incidentId: string, assignedTo: string, assignedBy: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.assignedTo = assignedTo;
    incident.timeline.push({
      timestamp: Date.now(),
      event: `Incident assigned to ${assignedTo}`,
      actor: assignedBy,
    });

    return incident;
  }

  /**
   * Update incident status
   */
  updateStatus(incidentId: string, newStatus: IncidentStatus, updatedBy: string, notes?: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    const oldStatus = incident.status;
    incident.status = newStatus;

    if (newStatus === 'investigating') {
      // Already has status
    } else if (newStatus === 'mitigating') {
      incident.mitigationTime = Date.now() - (incident.acknowledgedAt || incident.createdAt);
    } else if (newStatus === 'resolved') {
      incident.resolvedAt = Date.now();
    } else if (newStatus === 'closed') {
      incident.closedAt = Date.now();
    }

    incident.timeline.push({
      timestamp: Date.now(),
      event: `Status changed from ${oldStatus} to ${newStatus}`,
      actor: updatedBy,
      details: notes,
    });

    return incident;
  }

  /**
   * Add root cause
   */
  addRootCause(incidentId: string, rootCause: string, identifiedBy: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.rootCause = rootCause;
    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Root cause identified',
      actor: identifiedBy,
      details: { rootCause },
    });

    return incident;
  }

  /**
   * Link runbook
   */
  linkRunbook(incidentId: string, runbookId: string, linkedBy: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.runbookId = runbookId;
    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Runbook linked',
      actor: linkedBy,
      details: { runbookId },
    });

    return incident;
  }

  /**
   * Resolve incident
   */
  resolveIncident(
    incidentId: string,
    resolution: string,
    resolvedBy: string,
    rootCause?: string
  ): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.resolution = resolution;
    if (rootCause) {
      incident.rootCause = rootCause;
    }
    incident.status = 'resolved';
    incident.resolvedAt = Date.now();

    // Calculate metrics
    if (incident.acknowledgedAt) {
      incident.mitigationTime = incident.resolvedAt - incident.acknowledgedAt;
    }

    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Incident resolved',
      actor: resolvedBy,
      details: { resolution, rootCause },
    });

    return incident;
  }

  /**
   * Close incident
   */
  closeIncident(incidentId: string, closedBy: string): Incident | undefined {
    const incident = this.incidents.get(incidentId);
    if (!incident) return undefined;

    incident.status = 'closed';
    incident.closedAt = Date.now();
    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Incident closed',
      actor: closedBy,
    });

    return incident;
  }

  /**
   * Escalate incident
   */
  escalate(incidentId: string, escalatedBy?: string): boolean {
    const incident = this.incidents.get(incidentId);
    if (!incident) return false;

    incident.timeline.push({
      timestamp: Date.now(),
      event: 'Incident escalated',
      actor: escalatedBy || 'system',
      details: { escalationChain: this.escalationChain },
    });

    // Set severity lock to prevent downgrade
    if (incident.severity === 'critical') {
      this.activeSeverityLock = true;
    }

    return true;
  }

  /**
   * Get incident
   */
  getIncident(incidentId: string): Incident | undefined {
    return this.incidents.get(incidentId);
  }

  /**
   * List incidents
   */
  listIncidents(filter?: {
    status?: IncidentStatus;
    severity?: IncidentSeverity;
    affectedService?: string;
    assignedTo?: string;
  }): Incident[] {
    const results: Incident[] = [];
    this.incidents.forEach((incident) => {
      if (filter) {
        if (filter.status && incident.status !== filter.status) return;
        if (filter.severity && incident.severity !== filter.severity) return;
        if (filter.affectedService && !incident.affectedServices.includes(filter.affectedService)) return;
        if (filter.assignedTo && incident.assignedTo !== filter.assignedTo) return;
      }
      results.push(incident);
    });
    return results.sort((a, b) => b.createdAt - a.createdAt);
  }

  /**
   * Get active incidents
   */
  getActiveIncidents(): Incident[] {
    const active: Incident[] = [];
    this.incidents.forEach((incident) => {
      if (incident.status !== 'closed') {
        active.push(incident);
      }
    });
    return active.sort((a, b) => {
      // Sort by severity first, then by creation time
      const severityWeight: Record<IncidentSeverity, number> = { critical: 4, high: 3, medium: 2, low: 1 };
      const diff = severityWeight[b.severity] - severityWeight[a.severity];
      return diff !== 0 ? diff : b.createdAt - a.createdAt;
    });
  }

  /**
   * Get incident metrics
   */
  getIncidents(): IncidentMetrics {
    const all = Array.from(this.incidents.values());
    const closed = all.filter((i) => i.status === 'closed');

    let totalDetectionTime = 0;
    let totalMitigationTime = 0;
    let totalResolutionTime = 0;
    let detectionCount = 0;
    let mitigationCount = 0;
    let resolutionCount = 0;

    const serviceMap: Map<string, number> = new Map();
    const rootCauseMap: Map<string, number> = new Map();

    closed.forEach((incident) => {
      if (incident.detectionTime) {
        totalDetectionTime += incident.detectionTime;
        detectionCount++;
      }
      if (incident.mitigationTime) {
        totalMitigationTime += incident.mitigationTime;
        mitigationCount++;
      }
      if (incident.resolvedAt && incident.createdAt) {
        totalResolutionTime += incident.resolvedAt - incident.createdAt;
        resolutionCount++;
      }

      incident.affectedServices.forEach((service) => {
        serviceMap.set(service, (serviceMap.get(service) || 0) + 1);
      });

      if (incident.rootCause) {
        rootCauseMap.set(incident.rootCause, (rootCauseMap.get(incident.rootCause) || 0) + 1);
      }
    });

    // Calculate recurrence rate
    const rootCauseFreq = Array.from(rootCauseMap.values());
    const recurrenceCount = rootCauseFreq.filter((freq) => freq > 1).reduce((sum, freq) => sum + freq, 0);
    const recurrenceRate = closed.length > 0 ? (recurrenceCount / closed.length) * 100 : 0;

    const topServices = Array.from(serviceMap.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([service]) => service);

    const topCauses = Array.from(rootCauseMap.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([cause]) => cause);

    return {
      totalIncidents: all.length,
      criticalIncidents: all.filter((i) => i.severity === 'critical').length,
      avgDetectionTime: detectionCount > 0 ? totalDetectionTime / detectionCount : 0,
      avgMitigationTime: mitigationCount > 0 ? totalMitigationTime / mitigationCount : 0,
      avgResolutionTime: resolutionCount > 0 ? totalResolutionTime / resolutionCount : 0,
      recurrenceRate,
      topAffectedServices: topServices,
      topRootCauses: topCauses,
    };
  }

  /**
   * Set escalation chain
   */
  setEscalationChain(chain: string[]): void {
    this.escalationChain = chain;
  }

  /**
   * Get escalation chain
   */
  getEscalationChain(): string[] {
    return this.escalationChain;
  }
}

export default IncidentResponseManager;
