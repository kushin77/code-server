import { describe, expect, it } from 'vitest';
import { renderSessionBrokerPrometheusMetrics, type SessionBrokerMetricsSnapshot } from './session-metrics.js';

describe('session broker metrics exposition', () => {
  it('renders team usage, policy, and telemetry metrics', () => {
    const snapshot: SessionBrokerMetricsSnapshot = {
      generatedAt: '2026-04-20T00:00:00.000Z',
      policy: {
        maxConcurrentPerUser: 1,
        maxConcurrentPerTeam: 3,
        maxRuntimeSeconds: 28800,
        maxInactivitySeconds: 7200,
        usageWindowHours: 24,
      },
      teams: [
        {
          teamId: 'bioenergystrategies.com',
          activeSessions: 2,
          createdSessions: 5,
          failedSessions: 1,
          totalRuntimeSeconds: 7200,
          estimatedCpuHours: 4,
          lastActivityAt: new Date('2026-04-19T23:30:00.000Z'),
        },
      ],
      statusCounts: {
        ready: 2,
        queued: 1,
      },
      telemetry: {
        queuedLaunchesTotal: 3,
        launchDenialsTotal: 2,
        launchDenialsByPolicy: {
          runtime_ttl_exceeded: 1,
          data_profile_not_approved: 1,
        },
        reaperRunsTotal: 4,
        reaperFailuresTotal: 1,
        reapedSessionsTotal: 2,
        purgeOperationsTotal: 1,
        reaperLastRunAt: new Date('2026-04-19T23:55:00.000Z'),
        reaperLastSuccessAt: new Date('2026-04-19T23:55:00.000Z'),
      },
    };

    const exposition = renderSessionBrokerPrometheusMetrics(snapshot);

    expect(exposition).toContain('session_broker_policy_max_concurrent_per_team 3');
    expect(exposition).toContain('session_broker_team_active_sessions{team_id="bioenergystrategies.com"} 2');
    expect(exposition).toContain('session_broker_launch_denials_total{policy_code="runtime_ttl_exceeded"} 1');
    expect(exposition).toContain('session_broker_reaper_last_success_epoch_seconds');
    expect(exposition).toContain('session_broker_metrics_generated_at_epoch_seconds');
  });
});