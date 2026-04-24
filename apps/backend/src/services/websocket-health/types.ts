/**
 * WebSocket connection health monitoring types.
 * Tracks real-time connection state, latency, and reliability metrics.
 */

export type ConnectionState =
  | 'connecting'
  | 'connected'
  | 'disconnecting'
  | 'disconnected'
  | 'reconnecting'
  | 'stale';

export interface WebSocketConnectionMetrics {
  /** Unique connection ID */
  connectionId: string;

  /** Session ID this connection belongs to */
  sessionId: string;

  /** User ID or client identifier */
  userId: string;

  /** Current connection state */
  state: ConnectionState;

  /** Timestamp when connection was established */
  connectedAt: number;

  /** Timestamp of last successful message round-trip */
  lastHeartbeatAt: number;

  /** Current message latency in milliseconds */
  latencyMs: number;

  /** Average latency over the last minute */
  averageLatencyMs: number;

  /** 95th percentile latency in milliseconds */
  p95LatencyMs: number;

  /** Maximum latency observed */
  maxLatencyMs: number;

  /** Minimum latency observed */
  minLatencyMs: number;

  /** Total messages sent */
  messagesSent: number;

  /** Total messages received */
  messagesReceived: number;

  /** Total messages lost/unacknowledged */
  messagesLost: number;

  /** Message delivery success rate (0-100%) */
  deliverySuccessRate: number;

  /** Number of reconnection attempts */
  reconnectionAttempts: number;

  /** Total reconnection failures */
  reconnectionFailures: number;

  /** Uptime percentage since connection established */
  uptimePercent: number;

  /** Is connection currently healthy? */
  isHealthy: boolean;

  /** Health score (0-100) */
  healthScore: number;

  /** Optional error message if disconnected */
  error?: string;
}

export interface WebSocketHealthStatus {
  /** Connection metrics */
  connection: WebSocketConnectionMetrics;

  /** Timestamp of this status report */
  timestamp: number;

  /** Is this a critical issue? */
  isCritical: boolean;

  /** Health issues detected (if any) */
  issues: HealthIssue[];
}

export interface HealthIssue {
  /** Issue type */
  type:
    | 'high_latency'
    | 'connection_unstable'
    | 'message_loss'
    | 'frequent_reconnects'
    | 'stale_connection';

  /** Issue severity: 'warning' or 'critical' */
  severity: 'warning' | 'critical';

  /** Description of the issue */
  message: string;

  /** Timestamp when issue was detected */
  detectedAt: number;

  /** When the issue should be resolved by (if known) */
  resolveByAt?: number;
}

export interface AggregatedHealthMetrics {
  /** Timestamp of aggregation */
  timestamp: number;

  /** Number of active connections */
  activeConnections: number;

  /** Number of healthy connections */
  healthyConnections: number;

  /** Percentage of healthy connections */
  healthyPercent: number;

  /** Average latency across all connections */
  avgLatencyMs: number;

  /** 95th percentile latency across all connections */
  p95LatencyMs: number;

  /** Overall message delivery success rate */
  avgDeliverySuccessRate: number;

  /** Total reconnection attempts (all connections) */
  totalReconnectionAttempts: number;

  /** Average uptime across all connections */
  avgUptimePercent: number;

  /** Critical issues detected */
  criticalIssueCount: number;

  /** Warning issues detected */
  warningIssueCount: number;
}

export interface LatencyMeasurement {
  /** Unique measurement ID */
  id: string;

  /** Connection ID being measured */
  connectionId: string;

  /** When measurement started */
  startTime: number;

  /** When measurement completed */
  endTime: number;

  /** Round-trip latency in milliseconds */
  latencyMs: number;

  /** Sequence number for ordering */
  sequenceNumber: number;

  /** Was this measurement successful? */
  successful: boolean;

  /** Optional error if measurement failed */
  error?: string;
}

export interface ConnectionEvent {
  /** Event type */
  type:
    | 'connected'
    | 'disconnected'
    | 'reconnecting'
    | 'message_sent'
    | 'message_received'
    | 'health_check'
    | 'latency_spike'
    | 'connection_unstable'
    | 'recovery';

  /** Connection ID */
  connectionId: string;

  /** Session ID */
  sessionId: string;

  /** User ID */
  userId: string;

  /** Timestamp of event */
  timestamp: number;

  /** Event data (type-specific) */
  data?: Record<string, unknown>;
}

export interface WebSocketHealthConfig {
  /** Enable health monitoring */
  enabled: boolean;

  /** Health check interval in milliseconds */
  healthCheckIntervalMs: number;

  /** Latency measurement interval in milliseconds */
  latencyCheckIntervalMs: number;

  /** Aggregation window size in milliseconds */
  aggregationWindowMs: number;

  /** Data retention period in milliseconds */
  retentionMs: number;

  /** Latency threshold for "warning" in milliseconds */
  latencyWarningMs: number;

  /** Latency threshold for "critical" in milliseconds */
  latencyCriticalMs: number;

  /** Stale connection threshold in milliseconds (no messages) */
  staleConnectionThresholdMs: number;

  /** Message loss threshold (percentage) for critical */
  messageLossThresholdPercent: number;

  /** Max reconnection attempts before marking unhealthy */
  maxReconnectionAttempts: number;

  /** Target delivery success rate (percentage) */
  targetDeliverySuccessRate: number;
}

export interface PerSessionHealthStats {
  /** Session ID */
  sessionId: string;

  /** Total number of WebSocket connections in session */
  totalConnections: number;

  /** Healthy connections */
  healthyConnections: number;

  /** Session-level health percentage */
  healthPercent: number;

  /** Average latency in session */
  avgLatencyMs: number;

  /** Overall message delivery rate */
  deliverySuccessRate: number;

  /** Session uptime percentage */
  uptimePercent: number;
}
