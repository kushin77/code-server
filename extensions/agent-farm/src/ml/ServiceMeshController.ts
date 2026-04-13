/**
 * Phase 8: Advanced Kubernetes & Microservices
 * Service Mesh Controller - Istio/Linkerd service mesh management
 */

export interface ServiceMeshConfig {
  type: 'istio' | 'linkerd';
  namespace: string;
  injectSidecar: boolean;
  mtlsMode: 'STRICT' | 'PERMISSIVE' | 'DISABLE';
  circuitBreakerDefaults?: {
    maxConnections: number;
    maxPendingRequests: number;
    maxRequests: number;
    maxRequestsPerConnection: number;
  };
}

export interface VirtualService {
  name: string;
  hosts: string[];
  http: Array<{
    match?: Array<{ uri?: { prefix: string } }>;
    route: Array<{
      destination: {
        host: string;
        port: { number: number };
        subset?: string;
      };
      weight: number;
    }>;
    timeout?: string;
    retries?: {
      attempts: number;
      perTryTimeout: string;
    };
  }>;
}

export interface DestinationRule {
  name: string;
  host: string;
  trafficPolicy?: {
    connectionPool?: {
      tcp?: { maxConnections: number };
      http?: {
        http1MaxPendingRequests: number;
        http2MaxRequests: number;
        maxRequestsPerConnection: number;
      };
    };
    outlierDetection?: {
      consecutiveErrors: number;
      interval: string;
      baseEjectionTime: string;
      maxEjectionPercent: number;
    };
  };
  subsets?: Array<{
    name: string;
    labels: Record<string, string>;
  }>;
}

export interface PeerAuthentication {
  name: string;
  namespace: string;
  mtls?: {
    mode: 'STRICT' | 'PERMISSIVE' | 'DISABLE';
  };
  portLevelMtls?: Record<number, { mode: 'STRICT' | 'PERMISSIVE' | 'DISABLE' }>;
}

/**
 * Service Mesh Controller for Istio/Linkerd
 */
export class ServiceMeshController {
  private config: ServiceMeshConfig;
  private virtualServices: Map<string, VirtualService>;
  private destinationRules: Map<string, DestinationRule>;
  private peerAuthentications: Map<string, PeerAuthentication>;

  constructor(config: ServiceMeshConfig) {
    this.config = config;
    this.virtualServices = new Map();
    this.destinationRules = new Map();
    this.peerAuthentications = new Map();
  }

  /**
   * Create virtual service for traffic management
   */
  createVirtualService(service: VirtualService): void {
    this.virtualServices.set(service.name, service);
  }

  /**
   * Create destination rule for load balancing and circuit breaking
   */
  createDestinationRule(rule: DestinationRule): void {
    this.destinationRules.set(rule.name, rule);
  }

  /**
   * Setup mTLS between services
   */
  setupMTLS(namespace: string, mode: 'STRICT' | 'PERMISSIVE' | 'DISABLE'): PeerAuthentication {
    const auth: PeerAuthentication = {
      name: `mtls-${namespace}`,
      namespace,
      mtls: { mode },
    };

    this.peerAuthentications.set(auth.name, auth);
    return auth;
  }

  /**
   * Configure traffic mirroring (canary deployments)
   */
  configureTrafficMirroring(
    serviceName: string,
    primaryHost: string,
    mirrorHost: string,
    mirrorPercent: number
  ): VirtualService {
    const vs: VirtualService = {
      name: `${serviceName}-mirror`,
      hosts: [serviceName],
      http: [
        {
          route: [
            {
              destination: { host: primaryHost, port: { number: 80 } },
              weight: 100,
            },
            {
              destination: { host: mirrorHost, port: { number: 80 } },
              weight: mirrorPercent,
            },
          ],
        },
      ],
    };

    this.createVirtualService(vs);
    return vs;
  }

  /**
   * Setup circuit breaker
   */
  setupCircuitBreaker(
    serviceName: string,
    maxConnections: number,
    maxRequests: number
  ): DestinationRule {
    const rule: DestinationRule = {
      name: `${serviceName}-circuit-breaker`,
      host: serviceName,
      trafficPolicy: {
        connectionPool: {
          tcp: { maxConnections },
          http: {
            http1MaxPendingRequests: maxRequests,
            http2MaxRequests: maxRequests,
            maxRequestsPerConnection: 2,
          },
        },
        outlierDetection: {
          consecutiveErrors: 5,
          interval: '30s',
          baseEjectionTime: '30s',
          maxEjectionPercent: 50,
        },
      },
    };

    this.createDestinationRule(rule);
    return rule;
  }

  /**
   * Configure weighted canary rollout
   */
  configureCanaryRollout(serviceName: string, canaryWeight: number): VirtualService {
    const vs: VirtualService = {
      name: `${serviceName}-canary`,
      hosts: [serviceName],
      http: [
        {
          route: [
            {
              destination: {
                host: serviceName,
                port: { number: 80 },
                subset: 'stable',
              },
              weight: 100 - canaryWeight,
            },
            {
              destination: {
                host: serviceName,
                port: { number: 80 },
                subset: 'canary',
              },
              weight: canaryWeight,
            },
          ],
        },
      ],
    };

    this.createVirtualService(vs);
    return vs;
  }

  /**
   * Get all virtual services
   */
  getVirtualServices(): Map<string, VirtualService> {
    return this.virtualServices;
  }

  /**
   * Get all destination rules
   */
  getDestinationRules(): Map<string, DestinationRule> {
    return this.destinationRules;
  }

  /**
   * Export Istio manifests
   */
  exportIstioManifests(): Array<{ apiVersion: string; kind: string; metadata: any; spec: any }> {
    const manifests: Array<any> = [];

    // Export virtual services
    this.virtualServices.forEach((vs) => {
      manifests.push({
        apiVersion: 'networking.istio.io/v1beta1',
        kind: 'VirtualService',
        metadata: { name: vs.name, namespace: this.config.namespace },
        spec: vs,
      });
    });

    // Export destination rules
    this.destinationRules.forEach((dr) => {
      manifests.push({
        apiVersion: 'networking.istio.io/v1beta1',
        kind: 'DestinationRule',
        metadata: { name: dr.name, namespace: this.config.namespace },
        spec: dr,
      });
    });

    // Export peer authentication
    this.peerAuthentications.forEach((pa) => {
      manifests.push({
        apiVersion: 'security.istio.io/v1beta1',
        kind: 'PeerAuthentication',
        metadata: { name: pa.name, namespace: pa.namespace },
        spec: { mtls: pa.mtls },
      });
    });

    return manifests;
  }

  /**
   * Get service mesh statistics
   */
  getStats(): {
    virtualServices: number;
    destinationRules: number;
    mtlsPolicies: number;
    type: string;
  } {
    return {
      virtualServices: this.virtualServices.size,
      destinationRules: this.destinationRules.size,
      mtlsPolicies: this.peerAuthentications.size,
      type: this.config.type,
    };
  }
}

export default ServiceMeshController;
