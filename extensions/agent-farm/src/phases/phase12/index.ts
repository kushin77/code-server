/**
 * Phase 12: Multi-Site Federation & Geographic Distribution
 * 
 * This module provides enterprise-grade multi-region deployment capabilities:
 * - Service discovery and registration across geographic regions
 * - Cross-region data replication with conflict resolution
 * - Intelligent request routing based on geography and performance
 * - Global load balancing with multiple routing strategies
 * - Automatic conflict detection and resolution
 */

export {
  GeographicRegistry,
  type RegionConfig,
  type ServiceReplica,
  type ServiceEntry,
} from './GeographicRegistry';

export {
  CrossRegionReplicator,
  type ReplicationState,
  type ReplicationConflict,
  type ReplicationEvent,
} from './CrossRegionReplicator';

export {
  GeoLoadBalancer,
  type GeoRoutingRequest,
  type RoutingDecision,
  type LoadBalancingStrategy,
} from './GeoLoadBalancer';

export {
  MultiSiteFederationOrchestrator,
  type FederationConfig,
  type FederationStatus,
} from './MultiSiteFederationOrchestrator';
