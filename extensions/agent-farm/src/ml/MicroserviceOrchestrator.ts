/**
 * Phase 8: Advanced Kubernetes & Microservices
 * Microservice Orchestrator - Service lifecycle and deployment management
 */

export interface MicroserviceSpec {
  name: string;
  image: string;
  replicas: number;
  port: number;
  resources: {
    requests: { cpu: string; memory: string };
    limits: { cpu: string; memory: string };
  };
  env?: Array<{ name: string; value: string }>;
  livenessProbe?: {
    httpGet: { path: string; port: number };
    initialDelaySeconds: number;
    periodSeconds: number;
  };
  readinessProbe?: {
    httpGet: { path: string; port: number };
    initialDelaySeconds: number;
    periodSeconds: number;
  };
  dependencies?: string[];
}

export interface ServiceDeployment {
  service: MicroserviceSpec;
  status: 'pending' | 'deploying' | 'ready' | 'failed';
  replicas: {
    desired: number;
    ready: number;
    available: number;
  };
  lastUpdate: number;
  rolloutHistory: Array<{
    revision: number;
    timestamp: number;
    image: string;
    status: 'success' | 'failed';
  }>;
}

export interface ServiceDependencyGraph {
  services: Map<string, MicroserviceSpec>;
  dependencies: Map<string, string[]>;
  dependents: Map<string, string[]>;
}

/**
 * Microservice Orchestrator
 */
export class MicroserviceOrchestrator {
  private deployments: Map<string, ServiceDeployment>;
  private dependencyGraph: ServiceDependencyGraph;

  constructor() {
    this.deployments = new Map();
    this.dependencyGraph = {
      services: new Map(),
      dependencies: new Map(),
      dependents: new Map(),
    };
  }

  /**
   * Deploy microservice
   */
  deployService(spec: MicroserviceSpec): ServiceDeployment {
    const deployment: ServiceDeployment = {
      service: spec,
      status: 'pending',
      replicas: {
        desired: spec.replicas,
        ready: 0,
        available: 0,
      },
      lastUpdate: Date.now(),
      rolloutHistory: [],
    };

    this.deployments.set(spec.name, deployment);
    this.dependencyGraph.services.set(spec.name, spec);

    // Register dependencies
    if (spec.dependencies) {
      this.dependencyGraph.dependencies.set(spec.name, spec.dependencies);
      spec.dependencies.forEach((dep) => {
        const dependents = this.dependencyGraph.dependents.get(dep) || [];
        dependents.push(spec.name);
        this.dependencyGraph.dependents.set(dep, dependents);
      });
    }

    return deployment;
  }

  /**
   * Update service replicas
   */
  scaleService(serviceName: string, replicas: number): boolean {
    const deployment = this.deployments.get(serviceName);
    if (!deployment) return false;

    deployment.service.replicas = replicas;
    deployment.replicas.desired = replicas;
    return true;
  }

  /**
   * Rollout new version
   */
  rolloutVersion(serviceName: string, newImage: string): boolean {
    const deployment = this.deployments.get(serviceName);
    if (!deployment) return false;

    const oldImage = deployment.service.image;
    deployment.service.image = newImage;
    deployment.status = 'deploying';

    // Record in rollout history
    const revision = deployment.rolloutHistory.length + 1;
    deployment.rolloutHistory.push({
      revision,
      timestamp: Date.now(),
      image: newImage,
      status: 'success',
    });

    return true;
  }

  /**
   * Rollback to previous version
   */
  rollbackVersion(serviceName: string, revision?: number): boolean {
    const deployment = this.deployments.get(serviceName);
    if (!deployment || deployment.rolloutHistory.length === 0) return false;

    const targetRevision = revision || deployment.rolloutHistory.length - 1;
    if (targetRevision < 0 || targetRevision >= deployment.rolloutHistory.length) return false;

    const historyEntry = deployment.rolloutHistory[targetRevision];
    deployment.service.image = historyEntry.image;
    deployment.status = 'deploying';

    return true;
  }

  /**
   * Update service status
   */
  updateServiceStatus(
    serviceName: string,
    status: 'pending' | 'deploying' | 'ready' | 'failed',
    readyReplicas: number
  ): void {
    const deployment = this.deployments.get(serviceName);
    if (deployment) {
      deployment.status = status;
      deployment.replicas.ready = readyReplicas;
      deployment.replicas.available = Math.min(readyReplicas, deployment.replicas.desired);
      deployment.lastUpdate = Date.now();
    }
  }

  /**
   * Get service dependency order (topological sort)
   */
  getDeploymentOrder(): string[] {
    const order: string[] = [];
    const visited = new Set<string>();
    const visiting = new Set<string>();

    const visit = (service: string) => {
      if (visited.has(service)) return;
      if (visiting.has(service)) throw new Error(`Circular dependency detected: ${service}`);

      visiting.add(service);

      const deps = this.dependencyGraph.dependencies.get(service) || [];
      deps.forEach((dep) => visit(dep));

      visiting.delete(service);
      visited.add(service);
      order.push(service);
    };

    this.dependencyGraph.services.forEach((_, service) => {
      visit(service);
    });

    return order;
  }

  /**
   * Get services dependent on a given service
   */
  getDependents(serviceName: string): string[] {
    return this.dependencyGraph.dependents.get(serviceName) || [];
  }

  /**
   * Get service dependencies
   */
  getDependencies(serviceName: string): string[] {
    return this.dependencyGraph.dependencies.get(serviceName) || [];
  }

  /**
   * Get deployment status
   */
  getDeploymentStatus(serviceName: string): ServiceDeployment | null {
    return this.deployments.get(serviceName) || null;
  }

  /**
   * Get all deployments
   */
  getAllDeployments(): Map<string, ServiceDeployment> {
    return this.deployments;
  }

  /**
   * Check if all services are ready
   */
  areAllServicesReady(): boolean {
    return Array.from(this.deployments.values()).every(
      (d) => d.status === 'ready' && d.replicas.ready === d.replicas.desired
    );
  }

  /**
   * Get orchestrator statistics
   */
  getStats(): {
    totalServices: number;
    readyServices: number;
    failedServices: number;
    totalReplicas: number;
    readyReplicas: number;
    deploymentHistory: number;
  } {
    let readyServices = 0;
    let failedServices = 0;
    let totalReplicas = 0;
    let readyReplicas = 0;
    let deploymentHistory = 0;

    this.deployments.forEach((deployment) => {
      if (deployment.status === 'ready') readyServices++;
      if (deployment.status === 'failed') failedServices++;
      totalReplicas += deployment.replicas.desired;
      readyReplicas += deployment.replicas.ready;
      deploymentHistory += deployment.rolloutHistory.length;
    });

    return {
      totalServices: this.deployments.size,
      readyServices,
      failedServices,
      totalReplicas,
      readyReplicas,
      deploymentHistory,
    };
  }

  /**
   * Export as Kubernetes manifests
   */
  exportKubernetesManifests(): Array<{ apiVersion: string; kind: string; metadata: any; spec: any }> {
    const manifests: Array<any> = [];

    this.deployments.forEach((deployment) => {
      const spec = deployment.service;
      manifests.push({
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: { name: spec.name },
        spec: {
          replicas: spec.replicas,
          selector: { matchLabels: { app: spec.name } },
          template: {
            metadata: { labels: { app: spec.name } },
            spec: {
              containers: [
                {
                  name: spec.name,
                  image: spec.image,
                  ports: [{ containerPort: spec.port }],
                  resources: spec.resources,
                  env: spec.env || [],
                  livenessProbe: spec.livenessProbe,
                  readinessProbe: spec.readinessProbe,
                },
              ],
            },
          },
        },
      });

      // Export service
      manifests.push({
        apiVersion: 'v1',
        kind: 'Service',
        metadata: { name: spec.name },
        spec: {
          selector: { app: spec.name },
          ports: [{ port: 80, targetPort: spec.port }],
          type: 'ClusterIP',
        },
      });
    });

    return manifests;
  }
}

export default MicroserviceOrchestrator;
