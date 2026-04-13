/**
 * Runbook Manager
 * Stores and executes operational runbooks for incident response and maintenance
 */

export type StepType = 'verify' | 'execute' | 'notify' | 'wait' | 'decision' | 'rollback' | 'escalate';

export interface RunbookStep {
  id: string;
  title: string;
  description: string;
  type: StepType;
  command?: string; // command to execute
  expectedOutput?: string; // for verification
  condition?: string; // for decision points
  successOptions?: string[]; // next steps on success
  failureOptions?: string[]; // next steps on failure
  rollbackStep?: string; // step to execute on rollback
  timeout?: number; // milliseconds, undefined = no timeout
  retryable?: boolean;
  maxRetries?: number;
}

export interface Runbook {
  id: string;
  name: string;
  description: string;
  trigger: string; // trigger condition (e.g., "high_latency", "service_down")
  severity: 'critical' | 'high' | 'medium' | 'low';
  owner: string;
  steps: RunbookStep[];
  estimatedDuration: number; // milliseconds
  createdAt: Date;
  updatedAt: Date;
  version: number;
  deprecated?: boolean;
  tags: string[];
}

export interface ExecutionLog {
  id: string;
  runbookId: string;
  startTime: number;
  endTime?: number;
  status: 'running' | 'completed' | 'failed' | 'paused' | 'cancelled';
  currentStepId?: string;
  completedSteps: string[];
  failedSteps: string[];
  output: Map<string, string>; // step outputs
  errors: Map<string, string>; // step errors
  decisions: Map<string, string>; // decisions made during execution
  executedBy: string;
}

export class RunbookManager {
  private runbooks: Map<string, Runbook> = new Map();
  private executions: Map<string, ExecutionLog> = new Map();
  private readonly executionLimit = 1000; // keep last 1000 executions

  constructor() {}

  /**
   * Register a runbook
   */
  registerRunbook(runbook: Runbook): void {
    runbook.createdAt = new Date();
    runbook.updatedAt = new Date();
    this.runbooks.set(runbook.id, runbook);
  }

  /**
   * Update a runbook
   */
  updateRunbook(runbookId: string, updates: Partial<Runbook>): boolean {
    const runbook = this.runbooks.get(runbookId);
    if (!runbook) return false;

    Object.assign(runbook, updates);
    runbook.updatedAt = new Date();
    runbook.version++;
    this.runbooks.set(runbookId, runbook);
    return true;
  }

  /**
   * Get runbook by ID
   */
  getRunbook(runbookId: string): Runbook | undefined {
    return this.runbooks.get(runbookId);
  }

  /**
   * Get runbooks by trigger
   */
  getRunbooksByTrigger(trigger: string): Runbook[] {
    const matching: Runbook[] = [];
    this.runbooks.forEach((runbook) => {
      if (runbook.trigger === trigger && !runbook.deprecated) {
        matching.push(runbook);
      }
    });
    return matching;
  }

  /**
   * List all active runbooks
   */
  listRunbooks(filter?: { severity?: string; owner?: string; tags?: string[] }): Runbook[] {
    const active: Runbook[] = [];
    this.runbooks.forEach((runbook) => {
      if (runbook.deprecated) return;

      if (filter) {
        if (filter.severity && runbook.severity !== filter.severity) return;
        if (filter.owner && runbook.owner !== filter.owner) return;
        if (filter.tags && !filter.tags.some((tag) => runbook.tags.includes(tag))) return;
      }

      active.push(runbook);
    });
    return active;
  }

  /**
   * Start execution of a runbook
   */
  startExecution(runbookId: string, executedBy: string): ExecutionLog | undefined {
    const runbook = this.runbooks.get(runbookId);
    if (!runbook) return undefined;

    const execution: ExecutionLog = {
      id: `exec-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      runbookId,
      startTime: Date.now(),
      status: 'running',
      currentStepId: runbook.steps[0]?.id,
      completedSteps: [],
      failedSteps: [],
      output: new Map(),
      errors: new Map(),
      decisions: new Map(),
      executedBy,
    };

    this.executions.set(execution.id, execution);
    return execution;
  }

  /**
   * Record step completion
   */
  recordStepCompletion(executionId: string, stepId: string, output: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;

    execution.completedSteps.push(stepId);
    execution.output.set(stepId, output);

    // Determine next step
    const runbook = this.runbooks.get(execution.runbookId);
    if (!runbook) return false;

    const currentStep = runbook.steps.find((s) => s.id === stepId);
    if (!currentStep) return false;

    // Move to next step based on success
    if (currentStep.successOptions && currentStep.successOptions.length > 0) {
      execution.currentStepId = currentStep.successOptions[0]; // default to first option
    } else {
      // Find next step in sequence
      const currentIndex = runbook.steps.findIndex((s) => s.id === stepId);
      if (currentIndex < runbook.steps.length - 1) {
        execution.currentStepId = runbook.steps[currentIndex + 1].id;
      } else {
        // Execution complete
        execution.status = 'completed';
        execution.endTime = Date.now();
      }
    }

    return true;
  }

  /**
   * Record step failure
   */
  recordStepFailure(executionId: string, stepId: string, error: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;

    execution.failedSteps.push(stepId);
    execution.errors.set(stepId, error);

    // Determine next step based on failure options
    const runbook = this.runbooks.get(execution.runbookId);
    if (!runbook) return false;

    const currentStep = runbook.steps.find((s) => s.id === stepId);
    if (!currentStep) return false;

    // Check if step is retryable
    if (currentStep.retryable && (currentStep.maxRetries || 3) > 0) {
      execution.currentStepId = stepId; // retry same step
      return true;
    }

    // Move to failure handler
    if (currentStep.failureOptions && currentStep.failureOptions.length > 0) {
      execution.currentStepId = currentStep.failureOptions[0];
    } else if (currentStep.rollbackStep) {
      execution.currentStepId = currentStep.rollbackStep;
    } else {
      execution.status = 'failed';
      execution.endTime = Date.now();
    }

    return true;
  }

  /**
   * Record decision
   */
  recordDecision(executionId: string, stepId: string, decision: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;

    execution.decisions.set(stepId, decision);
    execution.completedSteps.push(stepId);

    // Move to next step based on decision
    const runbook = this.runbooks.get(execution.runbookId);
    if (!runbook) return false;

    const currentStep = runbook.steps.find((s) => s.id === stepId);
    if (!currentStep || !currentStep.successOptions) return false;

    // Find the option that matches the decision
    const index = currentStep.successOptions.indexOf(decision);
    if (index >= 0) {
      execution.currentStepId = decision;
    } else {
      execution.currentStepId = currentStep.successOptions[0];
    }

    return true;
  }

  /**
   * Pause execution
   */
  pauseExecution(executionId: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;
    if (execution.status === 'running') {
      execution.status = 'paused';
      return true;
    }
    return false;
  }

  /**
   * Resume execution
   */
  resumeExecution(executionId: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;
    if (execution.status === 'paused') {
      execution.status = 'running';
      return true;
    }
    return false;
  }

  /**
   * Cancel execution
   */
  cancelExecution(executionId: string): boolean {
    const execution = this.executions.get(executionId);
    if (!execution) return false;
    if (execution.status === 'running' || execution.status === 'paused') {
      execution.status = 'cancelled';
      execution.endTime = Date.now();
      return true;
    }
    return false;
  }

  /**
   * Get execution details
   */
  getExecution(executionId: string): ExecutionLog | undefined {
    return this.executions.get(executionId);
  }

  /**
   * Get execution history for a runbook
   */
  getExecutionHistory(runbookId: string, limit: number = 50): ExecutionLog[] {
    const history: ExecutionLog[] = [];
    this.executions.forEach((execution) => {
      if (execution.runbookId === runbookId) {
        history.push(execution);
      }
    });
    return history.sort((a, b) => b.startTime - a.startTime).slice(0, limit);
  }

  /**
   * Get stats
   */
  getStats(): {
    totalRunbooks: number;
    activeRunbooks: number;
    totalExecutions: number;
    successfulExecutions: number;
    failedExecutions: number;
    avgExecutionTime: number;
    mostUsedRunbooks: { runbookId: string; count: number }[];
  } {
    const activeRunbooks = Array.from(this.runbooks.values()).filter((r) => !r.deprecated).length;
    let successfulCount = 0;
    let failedCount = 0;
    let totalTime = 0;
    const runbookUsage: Map<string, number> = new Map();

    this.executions.forEach((execution) => {
      if (execution.status === 'completed') {
        successfulCount++;
        totalTime += (execution.endTime || Date.now()) - execution.startTime;
      } else if (execution.status === 'failed') {
        failedCount++;
        totalTime += (execution.endTime || Date.now()) - execution.startTime;
      }

      runbookUsage.set(execution.runbookId, (runbookUsage.get(execution.runbookId) || 0) + 1);
    });

    const sortedRunbookUsage = Array.from(runbookUsage.entries())
      .map(([runbookId, count]) => ({ runbookId, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);

    const successfulAndFailed = successfulCount + failedCount;

    return {
      totalRunbooks: this.runbooks.size,
      activeRunbooks,
      totalExecutions: this.executions.size,
      successfulExecutions: successfulCount,
      failedExecutions: failedCount,
      avgExecutionTime: successfulAndFailed > 0 ? totalTime / successfulAndFailed : 0,
      mostUsedRunbooks: sortedRunbookUsage,
    };
  }
}

export default RunbookManager;
