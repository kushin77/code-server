/**
 * Phase 9: Production Readiness Agent
 * Orchestrates SLOs, runbooks, and incident response for enterprise operations
 */

import { Agent } from '../phases';
import { SLOTracker, SLO, SLI } from '../ml/SLOTracker';
import { RunbookManager, Runbook } from '../ml/RunbookManager';
import { IncidentResponseManager, Incident, IncidentSeverity } from '../ml/IncidentResponseManager';

export interface ProductionStatus {
  timestamp: number;
  overallHealth: 'healthy' | 'degraded' | 'unhealthy';
  sloCompliance: number; // percentage
  activeIncidents: number;
  criticalIncidents: number;
  runbooksAvailable: number;
  mttr: number; // Mean Time To Recovery in milliseconds
  mtbf: number; // Mean Time Between Failures in milliseconds
  errorBudgetUtilization: number; // percentage
}

export class ProductionReadinessPhase9Agent extends Agent {
  private sloTracker: SLOTracker;
  private runbookManager: RunbookManager;
  private incidentManager: IncidentResponseManager;
  private environment: string;

  constructor(context: any, environment: string = 'production') {
    super('ProductionReadinessPhase9Agent', context);
    this.environment = environment;
    this.sloTracker = new SLOTracker();
    this.runbookManager = new RunbookManager();
    this.incidentManager = new IncidentResponseManager();
  }

  /**
   * Register SLO
   */
  registerSLO(slo: SLO): void {
    this.sloTracker.registerSLO(slo);
    this.log(`Registered SLO: ${slo.name} (target: ${slo.targetPercentage}%)`);
  }

  /**
   * Record metric for SLO
   */
  recordMetric(sloName: string, sliName: string, value: number): void {
    this.sloTracker.recordMetric(sloName, sliName, value);
  }

  /**
   * Get SLO status
   */
  getSLOStatus(sloName: string): any {
    return this.sloTracker.getSLOStatus(sloName);
  }

  /**
   * Get all SLO statuses
   */
  getAllSLOStatuses(): any {
    const statuses = this.sloTracker.getAllSLOStatuses();
    return Object.fromEntries(statuses);
  }

  /**
   * Register runbook
   */
  registerRunbook(runbook: Runbook): void {
    this.runbookManager.registerRunbook(runbook);
    this.log(`Registered runbook: ${runbook.name} (trigger: ${runbook.trigger})`);
  }

  /**
   * Get runbooks by trigger
   */
  getRunbooksByTrigger(trigger: string): Runbook[] {
    return this.runbookManager.getRunbooksByTrigger(trigger);
  }

  /**
   * Execute runbook
   */
  executeRunbook(runbookId: string, executedBy: string): any {
    const execution = this.runbookManager.startExecution(runbookId, executedBy);
    if (execution) {
      this.log(`Started execution of runbook ${runbookId}`);
    }
    return execution;
  }

  /**
   * Create incident
   */
  createIncident(
    title: string,
    description: string,
    severity: IncidentSeverity,
    affectedServices: string[],
    detectionTime?: number
  ): Incident {
    const incident = this.incidentManager.createIncident(title, description, severity, affectedServices, detectionTime);
    this.log(`Created incident: ${incident.id} (${severity}) - ${title}`);

    // Auto-trigger runbooks for critical incidents
    if (severity === 'critical') {
      const runbooks = this.runbookManager.getRunbooksByTrigger('incident');
      if (runbooks.length > 0) {
        runbooks.forEach((rb) => {
          this.executeRunbook(rb.id, 'auto-response');
        });
      }
    }

    return incident;
  }

  /**
   * Acknowledge incident
   */
  acknowledgeIncident(incidentId: string, acknowledgedBy: string): Incident | undefined {
    const incident = this.incidentManager.acknowledgeIncident(incidentId, acknowledgedBy);
    if (incident) {
      this.log(`Acknowledged incident: ${incidentId}`);
    }
    return incident;
  }

  /**
   * Update incident status
   */
  updateIncidentStatus(
    incidentId: string,
    newStatus: string,
    updatedBy: string,
    notes?: string
  ): Incident | undefined {
    const incident = this.incidentManager.updateStatus(incidentId, newStatus as any, updatedBy, notes);
    if (incident) {
      this.log(`Updated incident ${incidentId} status to ${newStatus}`);
    }
    return incident;
  }

  /**
   * Resolve incident
   */
  resolveIncident(incidentId: string, resolution: string, resolvedBy: string, rootCause?: string): Incident | undefined {
    const incident = this.incidentManager.resolveIncident(incidentId, resolution, resolvedBy, rootCause);
    if (incident) {
      this.log(`Resolved incident: ${incidentId}`);
    }
    return incident;
  }

  /**
   * Get active incidents
   */
  getActiveIncidents(): Incident[] {
    return this.incidentManager.getActiveIncidents();
  }

  /**
   * Get incident metrics
   */
  getIncidentMetrics(): any {
    return this.incidentManager.getIncidents();
  }

  /**
   * Get production status
   */
  getProductionStatus(): ProductionStatus {
    // Get SLO compliance
    const sloStats = this.sloTracker.getStats();
    const sloCompliance = sloStats.avgCompliancePercentage;

    // Get incident metrics
    const incidents = this.incidentManager.getActiveIncidents();
    const criticalIncidents = incidents.filter((i) => i.severity === 'critical').length;
    const allIncidents = this.incidentManager.getIncidents();

    // Determine overall health
    let overallHealth: 'healthy' | 'degraded' | 'unhealthy';
    if (sloCompliance >= 99 && criticalIncidents === 0) {
      overallHealth = 'healthy';
    } else if (sloCompliance >= 95 && criticalIncidents < 2) {
      overallHealth = 'degraded';
    } else {
      overallHealth = 'unhealthy';
    }

    // Calculate MTTR and MTBF
    const mttr = allIncidents.avgMitigationTime || 0;
    const mtbf = allIncidents.totalIncidents > 0 ? (7 * 24 * 60 * 60 * 1000) / allIncidents.totalIncidents : Infinity; // MTBF in ms

    // Get error budget utilization
    const errorBudgetSummary = this.sloTracker.getErrorBudgetSummary();
    const avgErrorBudgetUsed = errorBudgetSummary.length > 0 
      ? (errorBudgetSummary.reduce((sum, item) => {
          // Calculate budget percentage used (inverse of remaining)
          const slo = this.sloTracker['slos']?.get(item.sloName);
          if (!slo) return sum;
          return sum + (1 - (item.remaining / slo.errorBudget));
        }, 0) / errorBudgetSummary.length) * 100
      : 0;

    return {
      timestamp: Date.now(),
      overallHealth,
      sloCompliance,
      activeIncidents: incidents.length,
      criticalIncidents,
      runbooksAvailable: this.runbookManager['runbooks']?.size || 0,
      mttr,
      mtbf,
      errorBudgetUtilization: Math.min(100, Math.max(0, avgErrorBudgetUsed)),
    };
  }

  /**
   * Get comprehensive status report
   */
  getStatusReport(): {
    production: ProductionStatus;
    slos: Record<string, any>;
    incidents: any;
    runbooks: any;
  } {
    return {
      production: this.getProductionStatus(),
      slos: this.getAllSLOStatuses(),
      incidents: this.getIncidentMetrics(),
      runbooks: this.runbookManager['getStats']?.() || {},
    };
  }

  /**
   * Health check
   */
  async healthCheck(): Promise<{
    status: 'healthy' | 'degraded' | 'unhealthy';
    checks: Record<string, boolean>;
  }> {
    const prodStatus = this.getProductionStatus();
    const checks = {
      sloCompliance: prodStatus.sloCompliance >= 99,
      noActiveCriticalIncidents: prodStatus.criticalIncidents === 0,
      mttr: prodStatus.mttr < 30 * 60 * 1000, // < 30 minutes
      errorBudget: prodStatus.errorBudgetUtilization < 80,
    };

    const allHealthy = Object.values(checks).every((v) => v);
    const someHealthy = Object.values(checks).some((v) => v);

    return {
      status: allHealthy ? 'healthy' : someHealthy ? 'degraded' : 'unhealthy',
      checks,
    };
  }

  /**
   * Execute Phase 9 Agent
   */
  async execute(input: any): Promise<ProductionStatus> {
    const { action, slo, runbook, incident } = input;

    switch (action) {
      case 'registerSLO':
        this.registerSLO(slo);
        break;
      case 'registerRunbook':
        this.registerRunbook(runbook);
        break;
      case 'createIncident':
        this.createIncident(
          incident.title,
          incident.description,
          incident.severity,
          incident.affectedServices,
          incident.detectionTime
        );
        break;
      case 'acknowledgeIncident':
        this.acknowledgeIncident(incident.id, incident.acknowledgedBy);
        break;
      case 'resolveIncident':
        this.resolveIncident(incident.id, incident.resolution, incident.resolvedBy, incident.rootCause);
        break;
    }

    return this.getProductionStatus();
  }
}

export default ProductionReadinessPhase9Agent;
