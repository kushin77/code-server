/**
 * Phase 6: Deployment Agent
 * Orchestrates GitOps deployments with multi-region support
 */

import { Agent } from '../phases';
import { GitOpsOrchestrator, GitOpsConfig, RepositorySource, DeploymentTarget } from './GitOpsOrchestrator';
import { ManifestValidator } from './ManifestValidator';
import { FluxConfigBuilder } from './FluxConfigBuilder';
import { MultiRegionOrchestrator, DeploymentStrategy } from './MultiRegionOrchestrator';
import { PullRequestValidator, PullRequestContext } from './PullRequestValidator';

export interface DeploymentRequest {
  type: 'gitops' | 'canary' | 'blue-green' | 'rolling' | 'validate';
  repositoryUrl: string;
  branch: string;
  revision?: string;
  targets?: Array<{
    name: string;
    cluster: string;
    namespace: string;
    path: string;
  }>;
  strategy?: DeploymentStrategy;
  manifests?: string; // YAML manifest content
  prContext?: PullRequestContext;
}

export interface DeploymentStatus {
  id: string;
  status: 'Pending' | 'InProgress' | 'Completed' | 'Failed' | 'RolledBack';
  phase: string;
  progress: number; // 0-100
  message: string;
  startTime: Date;
  completedTime?: Date;
  regions?: Record<string, { status: string; health: number }>;
  errors: string[];
  warnings: string[];
}

export interface DeploymentResult {
  success: boolean;
  requestId: string;
  status: DeploymentStatus;
  validationResults?: any;
  deploymentDetails?: any;
  durationMs: number;
}

/**
 * Deployment Phase 6 Agent
 */
export class DeploymentPhase6Agent extends Agent {
  private gitopsOrchestrator?: GitOpsOrchestrator;
  private manifestValidator: ManifestValidator;
  private fluxConfigBuilder: FluxConfigBuilder;
  private multiRegionOrchestrator?: MultiRegionOrchestrator;
  private prValidator: PullRequestValidator;
  private deploymentHistory: Map<string, DeploymentResult> = new Map();

  constructor(context: any) {
    super('DeploymentPhase6Agent', context);
    this.manifestValidator = new ManifestValidator();
    this.fluxConfigBuilder = FluxConfigBuilder.create();
    this.prValidator = new PullRequestValidator();
  }

  /**
   * Execute deployment request
   */
  async execute(request: DeploymentRequest): Promise<DeploymentResult> {
    const requestId = `deploy-${Date.now()}`;
    const startTime = Date.now();

    const status: DeploymentStatus = {
      id: requestId,
      status: 'Pending',
      phase: 'Initialization',
      progress: 0,
      message: 'Initializing deployment',
      startTime: new Date(),
      errors: [],
      warnings: [],
    };

    try {
      switch (request.type) {
        case 'validate':
          return await this.validateDeployment(request, requestId, status);
        case 'gitops':
          return await this.executeGitOpsDeployment(request, requestId, status);
        case 'canary':
        case 'blue-green':
        case 'rolling':
          return await this.executeMultiRegionDeployment(request, requestId, status);
        default:
          throw new Error(`Unknown deployment type: ${request.type}`);
      }
    } catch (error) {
      status.status = 'Failed';
      status.errors.push(error instanceof Error ? error.message : String(error));
      status.completedTime = new Date();

      return {
        success: false,
        requestId,
        status,
        durationMs: Date.now() - startTime,
      };
    }
  }

  /**
   * Validate pull request for deployment
   */
  private async validateDeployment(
    request: DeploymentRequest,
    requestId: string,
    status: DeploymentStatus
  ): Promise<DeploymentResult> {
    status.phase = 'Validation';
    status.progress = 10;

    if (!request.prContext) {
      throw new Error('PR context required for validation');
    }

    // Validate PR
    const prValidation = await this.prValidator.validatePullRequest(request.prContext);
    status.progress = 40;

    // Validate manifests if provided
    let manifestValidation;
    if (request.manifests) {
      status.phase = 'Manifest Validation';
      manifestValidation = await this.manifestValidator.validateManifest(request.manifests);
      status.progress = 80;
    }

    status.status = 'Completed';
    status.progress = 100;
    status.message = prValidation.canDeploy
      ? '✅ PR approved for deployment'
      : '❌ PR blocked from deployment';
    status.completedTime = new Date();

    const result: DeploymentResult = {
      success: prValidation.canDeploy,
      requestId,
      status,
      validationResults: {
        prValidation,
        manifestValidation,
      },
      durationMs: Date.now() - status.startTime.getTime(),
    };

    this.deploymentHistory.set(requestId, result);
    return result;
  }

  /**
   * Execute GitOps deployment
   */
  private async executeGitOpsDeployment(
    request: DeploymentRequest,
    requestId: string,
    status: DeploymentStatus
  ): Promise<DeploymentResult> {
    if (!request.targets || request.targets.length === 0) {
      throw new Error('Deployment targets required for GitOps deployment');
    }

    status.phase = 'GitOps Setup';
    status.progress = 10;

    // Initialize GitOps orchestrator
    const gitopsConfig: GitOpsConfig = {
      repositoryUrl: request.repositoryUrl,
      branch: request.branch,
      interval: 300, // 5 minutes
      retryAttempts: 3,
      timeout: 600000, // 10 minutes
      enableAutoSync: true,
      enablePruning: true,
      targets: request.targets.map(
        (t) =>
          ({
            name: t.name,
            namespace: t.namespace || 'default',
            cluster: t.cluster,
            region: t.name.split('-')[0], // Extract region from target name
            path: t.path,
            prune: true,
          } as DeploymentTarget)
      ),
    };

    const source: RepositorySource = {
      url: request.repositoryUrl,
      ref: request.branch,
    };

    this.gitopsOrchestrator = new GitOpsOrchestrator(gitopsConfig, source);
    status.progress = 20;

    // Validate manifests
    status.phase = 'Manifest Validation';
    if (request.manifests) {
      const validation = await this.manifestValidator.validateManifest(request.manifests);
      if (!validation.valid) {
        status.warnings.push(`Manifest validation found ${validation.errors} errors`);
      }
    }
    status.progress = 40;

    // Generate Flux configuration
    status.phase = 'Flux Configuration';
    const fluxConfig = this.fluxConfigBuilder.generateCompleteConfig();
    status.progress = 60;

    // Start reconciliation
    status.phase = 'Synchronization';
    this.gitopsOrchestrator.startReconciliation();
    const syncOp = await this.gitopsOrchestrator.forceSync();
    status.progress = 85;

    // Get final metrics
    const metrics = this.gitopsOrchestrator.getMetrics();
    status.regions = {};
    for (const target of gitopsConfig.targets) {
      status.regions[target.name] = {
        status: metrics.health.status,
        health: metrics.health.resources.healthy,
      };
    }

    status.status = syncOp.phase === 'Succeeded' ? 'Completed' : 'Failed';
    status.progress = 100;
    status.message = syncOp.message;
    status.completedTime = new Date();

    const result: DeploymentResult = {
      success: syncOp.phase === 'Succeeded',
      requestId,
      status,
      deploymentDetails: {
        syncOperation: syncOp,
        metrics,
        fluxConfig,
      },
      durationMs: Date.now() - status.startTime.getTime(),
    };

    this.deploymentHistory.set(requestId, result);
    return result;
  }

  /**
   * Execute multi-region deployment
   */
  private async executeMultiRegionDeployment(
    request: DeploymentRequest,
    requestId: string,
    status: DeploymentStatus
  ): Promise<DeploymentResult> {
    if (!request.targets || request.targets.length === 0) {
      throw new Error('Deployment targets required for multi-region deployment');
    }

    const strategy = (request.strategy || DeploymentStrategy.CANARY) as DeploymentStrategy;
    this.multiRegionOrchestrator = new MultiRegionOrchestrator(strategy);

    status.phase = 'Region Registration';
    status.progress = 10;

    // Register regions
    for (const target of request.targets) {
      const region = {
        name: target.name,
        cluster: target.cluster,
        kubeconfig: `/etc/kubernetes/${target.cluster}.conf`,
        weight: Math.round(100 / request.targets.length),
        priority: request.targets.indexOf(target),
        healthCheckInterval: 30,
        failoverThreshold: 60,
        capacity: {
          nodes: 3,
          cpuMillis: 4000,
          memoryMb: 8192,
        },
      };

      this.multiRegionOrchestrator.registerRegion(region);
    }

    status.progress = 30;

    // Validate manifests
    status.phase = 'Validation';
    if (request.manifests) {
      const validation = await this.manifestValidator.validateManifest(request.manifests);
      status.progress = 50;

      if (validation.errors > 0) {
        status.warnings.push(`Found ${validation.errors} validation errors`);
      }
    }

    // Execute deployment
    status.phase = 'Deployment';
    const revision = request.revision || `v${Date.now()}`;
    const deploymentStatus = await this.multiRegionOrchestrator.deployToAllRegions(revision);
    status.progress = 90;

    // Collect results
    const summary = this.multiRegionOrchestrator.getDeploymentSummary();
    status.regions = {};
    for (const [regionName, regionStatus] of deploymentStatus.entries()) {
      status.regions[regionName] = {
        status: regionStatus.phase,
        health: regionStatus.healthScore,
      };
    }

    status.status = summary.failedRegions === 0 ? 'Completed' : 'Failed';
    status.progress = 100;
    status.message = `Deployment completed: ${summary.completedRegions}/${summary.totalRegions} regions successful`;
    status.completedTime = new Date();

    const result: DeploymentResult = {
      success: summary.failedRegions === 0,
      requestId,
      status,
      deploymentDetails: {
        strategy: strategy,
        summary,
        deploymentStatus: Object.fromEntries(deploymentStatus),
      },
      durationMs: Date.now() - status.startTime.getTime(),
    };

    this.deploymentHistory.set(requestId, result);
    return result;
  }

  /**
   * Get deployment history
   */
  getDeploymentHistory(requestId?: string): DeploymentResult | Map<string, DeploymentResult> {
    if (requestId) {
      return this.deploymentHistory.get(requestId) || { success: false, requestId, status: {} as any, durationMs: 0 };
    }
    return this.deploymentHistory;
  }

  /**
   * Rollback deployment
   */
  async rollbackDeployment(requestId: string, previousRevision: string): Promise<DeploymentResult> {
    const originalDeployment = this.deploymentHistory.get(requestId);
    if (!originalDeployment) {
      throw new Error(`Deployment ${requestId} not found`);
    }

    const status: DeploymentStatus = {
      id: `rollback-${requestId}`,
      status: 'InProgress',
      phase: 'Rollback',
      progress: 50,
      message: `Rolling back to ${previousRevision}`,
      startTime: new Date(),
      errors: [],
      warnings: [],
    };

    if (this.multiRegionOrchestrator) {
      await this.multiRegionOrchestrator.triggerRollback('Manual rollback requested', previousRevision);
    }

    status.status = 'Completed';
    status.progress = 100;
    status.message = `Rolled back to ${previousRevision}`;
    status.completedTime = new Date();

    return {
      success: true,
      requestId: `rollback-${requestId}`,
      status,
      durationMs: Date.now() - status.startTime.getTime(),
    };
  }

  async dispose(): Promise<void> {
    if (this.gitopsOrchestrator) {
      this.gitopsOrchestrator.stopReconciliation();
    }
  }
}

export default DeploymentPhase6Agent;
