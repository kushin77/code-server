export interface UsageSummaryRow {
  teamId: string;
  activeSessions: number;
  createdSessions: number;
  failedSessions: number;
  totalRuntimeSeconds: number;
  estimatedCpuHours: number;
  lastActivityAt: Date | null;
}

export interface SessionBrokerPolicySnapshot {
  maxConcurrentPerUser: number;
  maxConcurrentPerTeam: number;
  maxRuntimeSeconds: number;
  maxInactivitySeconds: number;
  usageWindowHours: number;
}

export interface SessionBrokerTelemetrySnapshot {
  queuedLaunchesTotal: number;
  launchDenialsTotal: number;
  launchDenialsByPolicy: Record<string, number>;
  reaperRunsTotal: number;
  reaperFailuresTotal: number;
  reapedSessionsTotal: number;
  purgeOperationsTotal: number;
  reaperLastRunAt: Date | null;
  reaperLastSuccessAt: Date | null;
}

export interface SessionBrokerMetricsSnapshot {
  generatedAt: string;
  policy: SessionBrokerPolicySnapshot;
  teams: UsageSummaryRow[];
  statusCounts: Record<string, number>;
  telemetry: SessionBrokerTelemetrySnapshot;
  redis?: {
    connected: boolean;
    sessionCount: number;
    memoryUsageBytes: number;
    latencyMs?: number;
  };
}

export interface SessionBrokerTelemetryState {
  queuedLaunchesTotal: number;
  launchDenialsTotal: number;
  launchDenialsByPolicy: Record<string, number>;
  reaperRunsTotal: number;
  reaperFailuresTotal: number;
  reapedSessionsTotal: number;
  purgeOperationsTotal: number;
  reaperLastRunAt: Date | null;
  reaperLastSuccessAt: Date | null;
}

export const createSessionBrokerTelemetryState = (): SessionBrokerTelemetryState => ({
  queuedLaunchesTotal: 0,
  launchDenialsTotal: 0,
  launchDenialsByPolicy: {},
  reaperRunsTotal: 0,
  reaperFailuresTotal: 0,
  reapedSessionsTotal: 0,
  purgeOperationsTotal: 0,
  reaperLastRunAt: null,
  reaperLastSuccessAt: null,
});

const escapeLabelValue = (value: string): string => value.replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/"/g, '\\"');

const formatLabels = (labels: Record<string, string>): string => {
  const entries = Object.entries(labels);
  if (entries.length === 0) {
    return '';
  }

  return `{${entries.map(([key, value]) => `${key}="${escapeLabelValue(value)}"`).join(',')}}`;
};

const formatMetricLine = (name: string, labels: Record<string, string>, value: number): string => {
  const formattedLabels = formatLabels(labels);
  return `${name}${formattedLabels} ${Number.isInteger(value) ? value : value.toFixed(6)}`;
};

export const renderSessionBrokerPrometheusMetrics = (snapshot: SessionBrokerMetricsSnapshot): string => {
  const lines: string[] = [];

  lines.push('# HELP session_broker_policy_max_concurrent_per_user Maximum concurrent sessions per user.');
  lines.push('# TYPE session_broker_policy_max_concurrent_per_user gauge');
  lines.push(`session_broker_policy_max_concurrent_per_user ${snapshot.policy.maxConcurrentPerUser}`);

  lines.push('# HELP session_broker_policy_max_concurrent_per_team Maximum concurrent sessions per team.');
  lines.push('# TYPE session_broker_policy_max_concurrent_per_team gauge');
  lines.push(`session_broker_policy_max_concurrent_per_team ${snapshot.policy.maxConcurrentPerTeam}`);

  lines.push('# HELP session_broker_policy_max_runtime_seconds Maximum runtime per session in seconds.');
  lines.push('# TYPE session_broker_policy_max_runtime_seconds gauge');
  lines.push(`session_broker_policy_max_runtime_seconds ${snapshot.policy.maxRuntimeSeconds}`);

  lines.push('# HELP session_broker_policy_max_inactivity_seconds Maximum inactivity before teardown in seconds.');
  lines.push('# TYPE session_broker_policy_max_inactivity_seconds gauge');
  lines.push(`session_broker_policy_max_inactivity_seconds ${snapshot.policy.maxInactivitySeconds}`);

  lines.push('# HELP session_broker_usage_window_hours Usage summary lookback window in hours.');
  lines.push('# TYPE session_broker_usage_window_hours gauge');
  lines.push(`session_broker_usage_window_hours ${snapshot.policy.usageWindowHours}`);

  lines.push('# HELP session_broker_team_active_sessions Active sessions per team in the usage window.');
  lines.push('# TYPE session_broker_team_active_sessions gauge');
  for (const team of snapshot.teams) {
    lines.push(formatMetricLine('session_broker_team_active_sessions', { team_id: team.teamId }, team.activeSessions));
  }

  lines.push('# HELP session_broker_team_created_sessions_total Sessions created per team in the usage window.');
  lines.push('# TYPE session_broker_team_created_sessions_total gauge');
  for (const team of snapshot.teams) {
    lines.push(formatMetricLine('session_broker_team_created_sessions_total', { team_id: team.teamId }, team.createdSessions));
  }

  lines.push('# HELP session_broker_team_failed_sessions_total Failed sessions per team in the usage window.');
  lines.push('# TYPE session_broker_team_failed_sessions_total gauge');
  for (const team of snapshot.teams) {
    lines.push(formatMetricLine('session_broker_team_failed_sessions_total', { team_id: team.teamId }, team.failedSessions));
  }

  lines.push('# HELP session_broker_team_estimated_cpu_hours Estimated CPU hours per team in the usage window.');
  lines.push('# TYPE session_broker_team_estimated_cpu_hours gauge');
  for (const team of snapshot.teams) {
    lines.push(formatMetricLine('session_broker_team_estimated_cpu_hours', { team_id: team.teamId }, team.estimatedCpuHours));
  }

  lines.push('# HELP session_broker_team_last_activity_timestamp_seconds Last activity timestamp per team.');
  lines.push('# TYPE session_broker_team_last_activity_timestamp_seconds gauge');
  for (const team of snapshot.teams) {
    if (!team.lastActivityAt) {
      continue;
    }

    lines.push(formatMetricLine('session_broker_team_last_activity_timestamp_seconds', { team_id: team.teamId }, team.lastActivityAt.getTime() / 1000));
  }

  lines.push('# HELP session_broker_session_status_total Current sessions by lifecycle status.');
  lines.push('# TYPE session_broker_session_status_total gauge');
  for (const [status, count] of Object.entries(snapshot.statusCounts)) {
    lines.push(formatMetricLine('session_broker_session_status_total', { status }, count));
  }

  lines.push('# HELP session_broker_launch_denials_total Launch denials by policy code.');
  lines.push('# TYPE session_broker_launch_denials_total counter');
  for (const [policyCode, count] of Object.entries(snapshot.telemetry.launchDenialsByPolicy)) {
    lines.push(formatMetricLine('session_broker_launch_denials_total', { policy_code: policyCode }, count));
  }

  lines.push('# HELP session_broker_launch_denials_total_all Total launch denials observed by the broker.');
  lines.push('# TYPE session_broker_launch_denials_total_all counter');
  lines.push(`session_broker_launch_denials_total_all ${snapshot.telemetry.launchDenialsTotal}`);

  lines.push('# HELP session_broker_launch_queued_total Total launch requests queued due to quota pressure.');
  lines.push('# TYPE session_broker_launch_queued_total counter');
  lines.push(`session_broker_launch_queued_total ${snapshot.telemetry.queuedLaunchesTotal}`);

  lines.push('# HELP session_broker_reaper_runs_total Total stale-session reaper runs.');
  lines.push('# TYPE session_broker_reaper_runs_total counter');
  lines.push(`session_broker_reaper_runs_total ${snapshot.telemetry.reaperRunsTotal}`);

  lines.push('# HELP session_broker_reaper_failures_total Total stale-session reaper failures.');
  lines.push('# TYPE session_broker_reaper_failures_total counter');
  lines.push(`session_broker_reaper_failures_total ${snapshot.telemetry.reaperFailuresTotal}`);

  lines.push('# HELP session_broker_reaped_sessions_total Total sessions reaped by the broker.');
  lines.push('# TYPE session_broker_reaped_sessions_total counter');
  lines.push(`session_broker_reaped_sessions_total ${snapshot.telemetry.reapedSessionsTotal}`);

  lines.push('# HELP session_broker_purge_operations_total Total hard-purge operations completed.');
  lines.push('# TYPE session_broker_purge_operations_total counter');
  lines.push(`session_broker_purge_operations_total ${snapshot.telemetry.purgeOperationsTotal}`);

  lines.push('# HELP session_broker_reaper_last_run_epoch_seconds Unix timestamp of the last reaper run.');
  lines.push('# TYPE session_broker_reaper_last_run_epoch_seconds gauge');
  lines.push(`session_broker_reaper_last_run_epoch_seconds ${snapshot.telemetry.reaperLastRunAt ? snapshot.telemetry.reaperLastRunAt.getTime() / 1000 : 0}`);

  lines.push('# HELP session_broker_reaper_last_success_epoch_seconds Unix timestamp of the last successful reaper run.');
  lines.push('# TYPE session_broker_reaper_last_success_epoch_seconds gauge');
  lines.push(`session_broker_reaper_last_success_epoch_seconds ${snapshot.telemetry.reaperLastSuccessAt ? snapshot.telemetry.reaperLastSuccessAt.getTime() / 1000 : 0}`);

  lines.push('# HELP session_broker_metrics_generated_at_epoch_seconds Unix timestamp when the metrics snapshot was generated.');
  lines.push('# TYPE session_broker_metrics_generated_at_epoch_seconds gauge');
  lines.push(`session_broker_metrics_generated_at_epoch_seconds ${Date.parse(snapshot.generatedAt) / 1000}`);

  // Redis metrics
  if (snapshot.redis) {
    lines.push('# HELP session_broker_redis_connected Redis connection status (1=connected, 0=disconnected).');
    lines.push('# TYPE session_broker_redis_connected gauge');
    lines.push(`session_broker_redis_connected ${snapshot.redis.connected ? 1 : 0}`);

    lines.push('# HELP session_broker_redis_session_count Number of sessions persisted in Redis.');
    lines.push('# TYPE session_broker_redis_session_count gauge');
    lines.push(`session_broker_redis_session_count ${snapshot.redis.sessionCount}`);

    lines.push('# HELP session_broker_redis_memory_usage_bytes Estimated memory usage of Redis session store in bytes.');
    lines.push('# TYPE session_broker_redis_memory_usage_bytes gauge');
    lines.push(`session_broker_redis_memory_usage_bytes ${snapshot.redis.memoryUsageBytes}`);

    if (snapshot.redis.latencyMs !== undefined) {
      lines.push('# HELP session_broker_redis_latency_ms Recent Redis command latency in milliseconds.');
      lines.push('# TYPE session_broker_redis_latency_ms gauge');
      lines.push(`session_broker_redis_latency_ms ${snapshot.redis.latencyMs}`);
    }
  }

  return `${lines.join('\n')}\n`;
};