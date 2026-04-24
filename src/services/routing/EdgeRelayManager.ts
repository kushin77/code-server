/**
 * Edge Relay Manager - Session-preserving low-latency relay selection.
 * Phase 12.4: Edge Relay Nodes
 *
 * Responsibilities:
 * - Register and monitor edge relay nodes across regions
 * - Route collaboration sessions to the nearest healthy relay
 * - Preserve session affinity across network switches
 * - Migrate sessions when a relay degrades or fails
 * - Track latency, migrations, and relay health metrics
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

export interface EdgeRelayNode {
  relayId: string;
  regionId: string;
  endpoint: string;
  healthy: boolean;
  latencyMs: number;
  capacity: number;
  activeSessions: number;
  lastHeartbeat: Date;
  draining: boolean;
}

export interface EdgeRelayRequest {
  sessionId: string;
  preferredRegions?: string[];
  clientRegion?: string;
  requireLocalData?: boolean;
}

export interface EdgeRelayDecision {
  relayId: string;
  regionId: string;
  endpoint: string;
  estimatedLatency: number;
  reason: string;
  migrated: boolean;
  alternateRelays: string[];
  timestamp: Date;
}

export interface EdgeRelayConfig {
  regions: string[];
  targetLatencyMs?: number;
  affinityTimeoutMs?: number;
  healthStalenessMs?: number;
  maxSessionsPerRelay?: number;
}

interface RelayAffinity {
  relayId: string;
  assignedAt: number;
}

/**
 * EdgeRelayManager
 *
 * Session-aware routing and migration for globally distributed edge relays.
 * The manager prefers relays that can keep collaboration under the latency
 * target while preserving sticky sessions during transient network changes.
 */
export class EdgeRelayManager extends EventEmitter {
  private readonly logger: Logger;
  private readonly metrics: Metrics;
  private readonly relays: Map<string, EdgeRelayNode> = new Map();
  private readonly affinity: Map<string, RelayAffinity> = new Map();
  private readonly latencySamples: Map<string, number[]> = new Map();
  private readonly config: Required<EdgeRelayConfig>;
  private totalMigrations = 0;
  private totalSelections = 0;
  private readonly maxLatencySamples = 100;

  constructor(config: EdgeRelayConfig) {
    super();

    this.config = {
      regions: config.regions,
      targetLatencyMs: config.targetLatencyMs ?? 50,
      affinityTimeoutMs: config.affinityTimeoutMs ?? 5 * 60 * 1000,
      healthStalenessMs: config.healthStalenessMs ?? 30 * 1000,
      maxSessionsPerRelay: config.maxSessionsPerRelay ?? 500,
    };

    this.logger = new Logger('EdgeRelayManager');
    this.metrics = new Metrics('edge_relay_manager');
  }

  /**
   * Register or update a relay node.
   */
  registerRelay(relay: Omit<EdgeRelayNode, 'activeSessions' | 'lastHeartbeat' | 'draining'> & Partial<Pick<EdgeRelayNode, 'activeSessions' | 'lastHeartbeat' | 'draining'>>): void {
    this.relays.set(relay.relayId, {
      ...relay,
      activeSessions: relay.activeSessions ?? 0,
      lastHeartbeat: relay.lastHeartbeat ?? new Date(),
      draining: relay.draining ?? false,
    });

    this.latencySamples.set(relay.relayId, this.latencySamples.get(relay.relayId) || []);
    this.emit('relay_registered', relay);
  }

  /**
   * Mark a relay as healthy/unhealthy and optionally refresh latency.
   */
  updateRelayHealth(relayId: string, healthy: boolean, latencyMs?: number): boolean {
    const relay = this.relays.get(relayId);
    if (!relay) return false;

    relay.healthy = healthy;
    relay.lastHeartbeat = new Date();

    if (latencyMs !== undefined) {
      relay.latencyMs = latencyMs;
      this.recordLatency(relayId, latencyMs);
    }

    this.metrics.gauge(`relay_health_${relayId}`, healthy ? 1 : 0);
    this.metrics.gauge(`relay_latency_${relayId}`, relay.latencyMs);
    return true;
  }

  /**
   * Select the best relay for a collaboration session.
   */
  selectRelay(request: EdgeRelayRequest): EdgeRelayDecision {
    const now = Date.now();
    const affinity = this.affinity.get(request.sessionId);

    if (affinity && now - affinity.assignedAt <= this.config.affinityTimeoutMs) {
      const currentRelay = this.relays.get(affinity.relayId);
      if (currentRelay && this.canUseRelay(currentRelay, request)) {
        this.totalSelections++;
        this.metrics.increment('relay_affinity_hit');
        return this.buildDecision(currentRelay, 'session affinity', false, request);
      }
    }

    const candidateRelays = this.getCandidateRelays(request);

    if (candidateRelays.length === 0) {
      throw new Error('No healthy edge relay is available');
    }

    const selectedRelay = candidateRelays[0];
    this.bindSession(request.sessionId, selectedRelay.relayId);

    this.totalSelections++;
    this.metrics.increment('relay_selected');
    this.metrics.gauge('relay_target_latency_hit', selectedRelay.latencyMs <= this.config.targetLatencyMs ? 1 : 0);

    return this.buildDecision(
      selectedRelay,
      selectedRelay.latencyMs <= this.config.targetLatencyMs
        ? 'target latency'
        : 'best available relay',
      false,
      request,
      candidateRelays.slice(1).map((relay) => relay.relayId)
    );
  }

  /**
   * Migrate a session from one relay to another.
   */
  migrateSession(sessionId: string, toRelayId: string, reason: string = 'relay migration'): EdgeRelayDecision {
    const destination = this.relays.get(toRelayId);
    if (!destination || !this.canUseRelay(destination)) {
      throw new Error(`Relay ${toRelayId} is not available for migration`);
    }

    const previous = this.affinity.get(sessionId);
    const migrated = previous?.relayId !== toRelayId;

    if (previous?.relayId) {
      const sourceRelay = this.relays.get(previous.relayId);
      if (sourceRelay) {
        sourceRelay.activeSessions = Math.max(0, sourceRelay.activeSessions - 1);
      }
    }

    this.bindSession(sessionId, toRelayId);

    if (migrated) {
      this.totalMigrations++;
      this.metrics.increment('relay_session_migrations');
    }

    this.emit('session_migrated', {
      sessionId,
      fromRelayId: previous?.relayId ?? null,
      toRelayId,
      reason,
      timestamp: new Date(),
    });

    return this.buildDecision(destination, reason, migrated, { sessionId });
  }

  /**
   * Drain a relay and migrate all attached sessions away.
   */
  drainRelay(relayId: string): string[] {
    const relay = this.relays.get(relayId);
    if (!relay) {
      return [];
    }

    relay.draining = true;
    this.emit('relay_draining', { relayId });

    const migratedSessions: string[] = [];
    for (const [sessionId, affinity] of this.affinity.entries()) {
      if (affinity.relayId !== relayId) {
        continue;
      }

      const fallback = this.getCandidateRelays({ sessionId, preferredRegions: [relay.regionId] })
        .find((candidate) => candidate.relayId !== relayId);

      if (fallback) {
        this.migrateSession(sessionId, fallback.relayId, 'relay drain');
        migratedSessions.push(sessionId);
      }
    }

    return migratedSessions;
  }

  /**
   * Record a session activity heartbeat.
   */
  recordSessionActivity(sessionId: string, relayId: string, latencyMs?: number): void {
    const relay = this.relays.get(relayId);
    if (!relay) return;

    this.bindSession(sessionId, relayId);
    if (latencyMs !== undefined) {
      this.recordLatency(relayId, latencyMs);
      relay.latencyMs = latencyMs;
    }

    this.metrics.increment('relay_session_activity');
  }

  /**
   * Get relay metrics for dashboards and alerting.
   */
  getMetrics(): Record<string, unknown> {
    const relays = Array.from(this.relays.values());
    const healthyRelays = relays.filter((relay) => relay.healthy && !relay.draining);
    const latencyValues = relays.map((relay) => relay.latencyMs).filter((latency) => latency > 0);
    const averageLatency = latencyValues.length
      ? latencyValues.reduce((sum, value) => sum + value, 0) / latencyValues.length
      : 0;

    return {
      totalRelays: relays.length,
      healthyRelays: healthyRelays.length,
      targetLatencyMs: this.config.targetLatencyMs,
      averageLatency: Math.round(averageLatency),
      affinitySize: this.affinity.size,
      totalSelections: this.totalSelections,
      totalMigrations: this.totalMigrations,
      relays: relays.map((relay) => ({
        relayId: relay.relayId,
        regionId: relay.regionId,
        healthy: relay.healthy,
        draining: relay.draining,
        activeSessions: relay.activeSessions,
        latencyMs: relay.latencyMs,
        capacity: relay.capacity,
      })),
    };
  }

  /**
   * Get a relay by ID.
   */
  getRelay(relayId: string): EdgeRelayNode | undefined {
    return this.relays.get(relayId);
  }

  /**
   * Clear session affinity and sample history.
   */
  reset(): void {
    this.affinity.clear();
    this.latencySamples.clear();
    this.totalMigrations = 0;
    this.totalSelections = 0;
  }

  private getCandidateRelays(request?: EdgeRelayRequest): EdgeRelayNode[] {
    const preferredRegions = request?.preferredRegions || [];

    const candidates = Array.from(this.relays.values())
      .filter((relay) => this.canUseRelay(relay, request))
      .sort((left, right) => {
        const leftPreferred = preferredRegions.includes(left.regionId) ? 0 : 1;
        const rightPreferred = preferredRegions.includes(right.regionId) ? 0 : 1;

        if (leftPreferred !== rightPreferred) {
          return leftPreferred - rightPreferred;
        }

        const leftLatency = this.getRelayLatency(left.relayId);
        const rightLatency = this.getRelayLatency(right.relayId);

        if (leftLatency !== rightLatency) {
          return leftLatency - rightLatency;
        }

        return left.activeSessions - right.activeSessions;
      });

    return candidates;
  }

  private canUseRelay(relay: EdgeRelayNode, request?: EdgeRelayRequest): boolean {
    if (!relay.healthy || relay.draining) {
      return false;
    }

    if (Date.now() - relay.lastHeartbeat.getTime() > this.config.healthStalenessMs) {
      return false;
    }

    if (relay.activeSessions >= relay.capacity) {
      return false;
    }

    if (request?.requireLocalData && request.preferredRegions && request.preferredRegions.length > 0) {
      return request.preferredRegions.includes(relay.regionId);
    }

    return true;
  }

  private bindSession(sessionId: string, relayId: string): void {
    const current = this.affinity.get(sessionId);
    if (current?.relayId && current.relayId !== relayId) {
      const previousRelay = this.relays.get(current.relayId);
      if (previousRelay) {
        previousRelay.activeSessions = Math.max(0, previousRelay.activeSessions - 1);
      }
    }

    const nextRelay = this.relays.get(relayId);
    if (!nextRelay) {
      throw new Error(`Relay ${relayId} does not exist`);
    }

    nextRelay.activeSessions = Math.min(nextRelay.capacity, nextRelay.activeSessions + 1);
    this.affinity.set(sessionId, { relayId, assignedAt: Date.now() });
  }

  private getRelayLatency(relayId: string): number {
    const relay = this.relays.get(relayId);
    if (!relay) {
      return Number.POSITIVE_INFINITY;
    }

    const samples = this.latencySamples.get(relayId) || [];
    if (samples.length === 0) {
      return relay.latencyMs || Number.POSITIVE_INFINITY;
    }

    const sorted = [...samples].sort((a, b) => a - b);
    const p95Index = Math.max(0, Math.ceil(sorted.length * 0.95) - 1);
    return sorted[p95Index];
  }

  private recordLatency(relayId: string, latencyMs: number): void {
    const samples = this.latencySamples.get(relayId) || [];
    samples.push(latencyMs);

    if (samples.length > this.maxLatencySamples) {
      samples.shift();
    }

    this.latencySamples.set(relayId, samples);
    this.metrics.gauge(`relay_latency_p95_${relayId}`, this.getRelayLatency(relayId));
  }

  private buildDecision(
    relay: EdgeRelayNode,
    reason: string,
    migrated: boolean,
    request: Pick<EdgeRelayRequest, 'sessionId'>,
    alternateRelays: string[] = []
  ): EdgeRelayDecision {
    return {
      relayId: relay.relayId,
      regionId: relay.regionId,
      endpoint: relay.endpoint,
      estimatedLatency: this.getRelayLatency(relay.relayId),
      reason,
      migrated,
      alternateRelays,
      timestamp: new Date(),
    };
  }
}

export default EdgeRelayManager;