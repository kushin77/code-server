/**
 * Phase 9: Production Readiness
 * Exports for SLOs, runbooks, incident response, and operational excellence
 */

export { SLOTracker } from '../../ml/SLOTracker';
export type { SLI, SLO, SLIStatus, SLOStatus, MetricPoint } from '../../ml/SLOTracker';

export { RunbookManager } from '../../ml/RunbookManager';
export type { Runbook, RunbookStep, ExecutionLog, StepType } from '../../ml/RunbookManager';

export { IncidentResponseManager } from '../../ml/IncidentResponseManager';
export type {
  Incident,
  IncidentSeverity,
  IncidentStatus,
  IncidentTimeline,
  IncidentMetrics,
} from '../../ml/IncidentResponseManager';

export { ProductionReadinessPhase9Agent } from '../../agents/ProductionReadinessPhase9Agent';
export type { ProductionStatus } from '../../agents/ProductionReadinessPhase9Agent';

/**
 * Phase 9 Configuration Examples
 */
export const Phase9Examples = {
  slo: {
    name: 'api-availability',
    description: 'API service availability SLO',
    service: 'api-gateway',
    slis: [
      {
        name: 'availability',
        description: 'Successful requests percentage',
        type: 'availability' as const,
        unit: 'percentage',
        threshold: 99.9,
        window: 24 * 60 * 60 * 1000, // 1 day
      },
      {
        name: 'latency',
        description: 'P99 request latency',
        type: 'latency' as const,
        unit: 'milliseconds',
        threshold: 200,
        window: 60 * 60 * 1000, // 1 hour
      },
    ],
    targetPercentage: 99.9,
    errorBudget: 1000, // milliseconds of downtime per month
    period: 30,
  },

  runbook: {
    id: 'rb-high-latency',
    name: 'High Latency Response',
    description: 'Response procedure for high API latency',
    trigger: 'high_latency',
    severity: 'high' as const,
    owner: 'platform-team',
    steps: [
      {
        id: 'step-1',
        title: 'Verify Issue',
        description: 'Confirm high latency is present',
        type: 'verify' as const,
        command: 'curl -w "%{time_total}" https://api.example.com/health',
        expectedOutput: '> 0.5',
        successOptions: ['step-2'],
        failureOptions: ['step-5'],
        timeout: 30000,
      },
      {
        id: 'step-2',
        title: 'Check Database Load',
        description: 'Inspect database connection pool',
        type: 'execute' as const,
        command: 'kubectl exec -it db-0 -- psql -c "SELECT count(*) FROM pg_stat_activity;"',
        successOptions: ['step-3'],
        timeout: 60000,
      },
      {
        id: 'step-3',
        title: 'Scale Up API Instances',
        description: 'Increase API replica count',
        type: 'execute' as const,
        command: 'kubectl scale deployment api-gateway --replicas=5',
        successOptions: ['step-4'],
        timeout: 120000,
      },
      {
        id: 'step-4',
        title: 'Verify Resolution',
        description: 'Check if latency has improved',
        type: 'verify' as const,
        command: 'curl -w "%{time_total}" https://api.example.com/health',
        successOptions: [],
        timeout: 30000,
      },
      {
        id: 'step-5',
        title: 'Escalate',
        description: 'Escalate to on-call engineer',
        type: 'escalate' as const,
        successOptions: [],
      },
    ],
    estimatedDuration: 5 * 60 * 1000, // 5 minutes
    version: 1,
    tags: ['latency', 'api', 'performance'],
  },

  incident: {
    title: 'High API Latency',
    description: 'Users reporting slow API responses',
    severity: 'high' as const,
    affectedServices: ['api-gateway', 'database'],
  },
};

/**
 * Phase 9 Feature Summary
 *
 * SLOTracker:
 * - SLI and SLO management
 * - Metric recording and analysis
 * - Error budget tracking
 * - SLI status calculation
 * - Trend analysis (improving/stable/degrading)
 * - At-risk SLO detection
 *
 * RunbookManager:
 * - Runbook creation and versioning
 * - Step-by-step procedure execution
 * - Decision point handling
 * - Failure and rollback support
 * - Execution history and statistics
 *
 * IncidentResponseManager:
 * - Incident creation and lifecycle
 * - Severity and status management
 * - Timeline tracking
 * - Root cause analysis
 * - Escalation handling
 * - Incident metrics and trends
 *
 * ProductionReadinessPhase9Agent:
 * - Unified operations interface
 * - SLO registration and monitoring
 * - Runbook execution
 * - Incident management
 * - Production health reporting
 * - MTTR and MTBF tracking
 */
