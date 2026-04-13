/**
 * Phase 8: Kubernetes & Microservices Infrastructure
 * Exports for service mesh control, microservice orchestration, and health monitoring
 */

export { ServiceMeshController } from '../../ml/ServiceMeshController';
export type {
  ServiceMeshConfig,
  VirtualService,
  DestinationRule,
  PeerAuthentication,
} from '../../ml/ServiceMeshController';

export { MicroserviceOrchestrator } from '../../ml/MicroserviceOrchestrator';
export type { MicroserviceSpec, ServiceDeployment } from '../../ml/MicroserviceOrchestrator';

export { HealthCheckEngine } from '../../ml/HealthCheckEngine';
export type { HealthCheckConfig, HealthStatus, ServiceHealth, HealthCheckType } from '../../ml/HealthCheckEngine';

export { KubernetesPhase8Agent } from '../../agents/KubernetesPhase8Agent';
export type {
  KubernetesCluster,
  DeploymentPlan,
  ClusterStatus,
} from '../../agents/KubernetesPhase8Agent';

/**
 * Phase 8 Configuration Examples
 */
export const Phase8Examples = {
  deploymentPlan: {
    serviceName: 'api-gateway',
    image: 'api-gateway:1.0.0',
    replicas: 3,
    resources: {
      requests: { cpu: '100m', memory: '128Mi' },
      limits: { cpu: '500m', memory: '512Mi' },
    },
    healthChecks: [
      {
        type: 'http' as const,
        path: '/health',
        timeout: 5,
        interval: 10,
      },
    ],
    dependencies: ['auth-service', 'config-service'],
  },

  meshOptions: {
    trafficMirroring: {
      percent: 10,
      mirrorHost: 'api-gateway-canary:8080',
    },
    circuitBreaker: {
      maxConnections: 100,
      maxRequests: 1000,
    },
    canaryRollout: {
      weight: 10,
    },
  },
};

/**
 * Phase 8 Feature Summary
 *
 * ServiceMeshController:
 * - Istio/Linkerd integration
 * - VirtualService and DestinationRule management
 * - mTLS configuration
 * - Traffic mirroring, circuit breakers, canary rollouts
 * - Manifest export
 *
 * MicroserviceOrchestrator:
 * - Service deployment and scaling
 * - Rolling updates with rollback support
 * - Dependency-aware deployment ordering
 * - Kubernetes manifest generation
 *
 * HealthCheckEngine:
 * - HTTP, TCP, gRPC, and exec health checks
 * - Uptime tracking and history
 * - Consecutive failure/success counting
 * - Overall health aggregation
 * - Performance metrics
 *
 * KubernetesPhase8Agent:
 * - Unified orchestration interface
 * - Service deployment and lifecycle management
 * - Health monitoring and reporting
 * - Service mesh configuration
 * - Dependency graph analysis
 */
