/**
 * Distributed Operation Orchestrator
 * Coordinates distributed operations across multiple edge nodes
 */

export type DistributedOperation = 'map' | 'reduce' | 'aggregate' | 'broadcast' | 'scatter-gather';

export interface MapTask {
  id: string;
  operation: string;
  input: any[];
  nodeIds: string[];
  partition: number;
}

export interface ReduceTask {
  id: string;
  operation: string;
  inputs: any[];
  targetNodeId: string;
}

export interface TaskResult {
  taskId: string;
  nodeId: string;
  status: 'success' | 'failed' | 'timeout';
  output?: any;
  error?: string;
  duration: number;
  timestamp: number;
}

export interface DistributedWorkflow {
  id: string;
  name: string;
  stages: { name: string; operationType: DistributedOperation; tasks: string[] }[];
  startedAt?: number;
  completedAt?: number;
  status: 'pending' | 'running' | 'completed' | 'failed';
  results: Map<string, TaskResult[]>;
}

export class DistributedOperationOrchestrator {
  private workflows: Map<string, DistributedWorkflow> = new Map();
  private taskResults: Map<string, TaskResult> = new Map();
  private taskExecutionLog: TaskResult[] = [];
  private nodeTopology: Map<string, string[]> = new Map(); // node -> neighbors
  private readonly maxLogSize = 5000;

  constructor() {}

  /**
   * Register node topology (for locality optimization)
   */
  registerNodeTopology(nodeId: string, neighbors: string[]): void {
    this.nodeTopology.set(nodeId, neighbors);
  }

  /**
   * Create distributed workflow
   */
  createWorkflow(name: string, stages: { name: string; operationType: DistributedOperation; tasks: string[] }[]): DistributedWorkflow {
    const workflow: DistributedWorkflow = {
      id: `wf-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      name,
      stages,
      status: 'pending',
      results: new Map(),
    };

    this.workflows.set(workflow.id, workflow);
    return workflow;
  }

  /**
   * Start workflow
   */
  startWorkflow(workflowId: string): boolean {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) return false;

    workflow.status = 'running';
    workflow.startedAt = Date.now();
    return true;
  }

  /**
   * Execute map operation
   */
  executeMap(workflowId: string, stageIndex: number, input: any[], nodeIds: string[]): string {
    const workflow = this.workflows.get(workflowId);
    if (!workflow || stageIndex >= workflow.stages.length) return '';

    const stage = workflow.stages[stageIndex];
    const mapTaskId = `map-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    // Partition input across nodes
    const partitionSize = Math.ceil(input.length / nodeIds.length);
    const tasks: MapTask[] = [];

    nodeIds.forEach((nodeId, index) => {
      const start = index * partitionSize;
      const end = Math.min(start + partitionSize, input.length);
      const partition = input.slice(start, end);

      tasks.push({
        id: `${mapTaskId}-${index}`,
        operation: stage.name,
        input: partition,
        nodeIds: [nodeId],
        partition: index,
      });
    });

    // Store tasks
    if (!workflow.results.has(`stage-${stageIndex}`)) {
      workflow.results.set(`stage-${stageIndex}`, []);
    }

    return mapTaskId;
  }

  /**
   * Execute reduce operation
   */
  executeReduce(workflowId: string, stageIndex: number, inputs: any[], targetNodeId: string): TaskResult {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) {
      return {
        taskId: '',
        nodeId: '',
        status: 'failed',
        error: 'Workflow not found',
        duration: 0,
        timestamp: Date.now(),
      };
    }

    const stage = workflow.stages[stageIndex];
    const reduceTaskId = `reduce-${Date.now()}`;
    const startTime = Date.now();

    // Simulate reduce operation
    const result: TaskResult = {
      taskId: reduceTaskId,
      nodeId: targetNodeId,
      status: 'success',
      output: inputs.length > 0 ? inputs[0] : null,
      duration: Date.now() - startTime,
      timestamp: Date.now(),
    };

    this.taskResults.set(reduceTaskId, result);
    this.taskExecutionLog.push(result);

    if (this.taskExecutionLog.length > this.maxLogSize) {
      this.taskExecutionLog.shift();
    }

    const stageResults = workflow.results.get(`stage-${stageIndex}`) || [];
    stageResults.push(result);
    workflow.results.set(`stage-${stageIndex}`, stageResults);

    return result;
  }

  /**
   * Execute broadcast operation
   */
  executeBroadcast(workflowId: string, stageIndex: number, data: any, sourceNodeId: string, targetNodeIds: string[]): TaskResult[] {
    const results: TaskResult[] = [];
    const startTime = Date.now();

    targetNodeIds.forEach((nodeId) => {
      const result: TaskResult = {
        taskId: `broadcast-${Date.now()}-${nodeId}`,
        nodeId,
        status: 'success',
        output: data,
        duration: 0,
        timestamp: Date.now(),
      };

      results.push(result);
      this.taskResults.set(result.taskId, result);
      this.taskExecutionLog.push(result);
    });

    const workflow = this.workflows.get(workflowId);
    if (workflow) {
      const stageResults = workflow.results.get(`stage-${stageIndex}`) || [];
      stageResults.push(...results);
      workflow.results.set(`stage-${stageIndex}`, stageResults);
    }

    if (this.taskExecutionLog.length > this.maxLogSize) {
      this.taskExecutionLog.shift();
    }

    return results;
  }

  /**
   * Execute scatter-gather operation
   */
  executeScatterGather(
    workflowId: string,
    stageIndex: number,
    tasks: { nodeId: string; data: any }[]
  ): { scattered: TaskResult[]; gathered: TaskResult } {
    const scatterResults: TaskResult[] = [];
    const scatterStartTime = Date.now();

    // Scatter phase
    tasks.forEach((task) => {
      const result: TaskResult = {
        taskId: `scatter-${Date.now()}-${task.nodeId}`,
        nodeId: task.nodeId,
        status: 'success',
        output: task.data,
        duration: 0,
        timestamp: Date.now(),
      };

      scatterResults.push(result);
      this.taskResults.set(result.taskId, result);
      this.taskExecutionLog.push(result);
    });

    // Gather phase (simulate aggregation on central node)
    const gatherResult: TaskResult = {
      taskId: `gather-${Date.now()}`,
      nodeId: 'coordinator',
      status: 'success',
      output: scatterResults.map((r) => r.output),
      duration: Date.now() - scatterStartTime,
      timestamp: Date.now(),
    };

    this.taskResults.set(gatherResult.taskId, gatherResult);
    this.taskExecutionLog.push(gatherResult);

    const workflow = this.workflows.get(workflowId);
    if (workflow) {
      const stageResults = workflow.results.get(`stage-${stageIndex}`) || [];
      stageResults.push(...scatterResults, gatherResult);
      workflow.results.set(`stage-${stageIndex}`, stageResults);
    }

    if (this.taskExecutionLog.length > this.maxLogSize) {
      this.taskExecutionLog.shift();
    }

    return { scattered: scatterResults, gathered: gatherResult };
  }

  /**
   * Complete workflow
   */
  completeWorkflow(workflowId: string, success: boolean): DistributedWorkflow | undefined {
    const workflow = this.workflows.get(workflowId);
    if (!workflow) return undefined;

    workflow.status = success ? 'completed' : 'failed';
    workflow.completedAt = Date.now();
    return workflow;
  }

  /**
   * Get workflow status
   */
  getWorkflowStatus(workflowId: string): DistributedWorkflow | undefined {
    return this.workflows.get(workflowId);
  }

  /**
   * Get task result
   */
  getTaskResult(taskId: string): TaskResult | undefined {
    return this.taskResults.get(taskId);
  }

  /**
   * Get execution statistics
   */
  getExecutionStats(): {
    totalWorkflows: number;
    completedWorkflows: number;
    failedWorkflows: number;
    runningWorkflows: number;
    totalTasks: number;
    successfulTasks: number;
    failedTasks: number;
    avgTaskDuration: number;
    avgWorkflowDuration: number;
  } {
    const workflows = Array.from(this.workflows.values());
    const completedWorkflows = workflows.filter((w) => w.status === 'completed').length;
    const failedWorkflows = workflows.filter((w) => w.status === 'failed').length;
    const runningWorkflows = workflows.filter((w) => w.status === 'running').length;

    const successfulTasks = Array.from(this.taskResults.values()).filter((r) => r.status === 'success').length;
    const failedTasks = Array.from(this.taskResults.values()).filter((r) => r.status === 'failed').length;

    const taskDurations = Array.from(this.taskResults.values()).map((r) => r.duration);
    const avgTaskDuration = taskDurations.length > 0 ? taskDurations.reduce((a, b) => a + b) / taskDurations.length : 0;

    const completedWorkflowsList = workflows.filter((w) => w.completedAt && w.startedAt);
    const workflowDurations = completedWorkflowsList.map((w) => (w.completedAt! - w.startedAt!) * 1);
    const avgWorkflowDuration = workflowDurations.length > 0 ? workflowDurations.reduce((a, b) => a + b) / workflowDurations.length : 0;

    return {
      totalWorkflows: workflows.length,
      completedWorkflows,
      failedWorkflows,
      runningWorkflows,
      totalTasks: this.taskResults.size,
      successfulTasks,
      failedTasks,
      avgTaskDuration,
      avgWorkflowDuration,
    };
  }

  /**
   * Get locality-optimized node ordering
   */
  getLocalityOptimizedNodes(sourceNodeId: string, allNodeIds: string[]): string[] {
    const neighbors = this.nodeTopology.get(sourceNodeId) || [];
    const local = allNodeIds.filter((id) => neighbors.includes(id));
    const remote = allNodeIds.filter((id) => !neighbors.includes(id) && id !== sourceNodeId);

    // Return local nodes first, then remote
    return [sourceNodeId, ...local, ...remote];
  }

  /**
   * Get execution log
   */
  getExecutionLog(limit?: number): TaskResult[] {
    if (limit) {
      return this.taskExecutionLog.slice(-limit);
    }
    return this.taskExecutionLog;
  }
}

export default DistributedOperationOrchestrator;
