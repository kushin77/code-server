/**
 * Anomaly detection types for session access patterns.
 * Supports behavioral profiling, statistical anomaly scoring, and alerting.
 */

/**
 * User behavioral profile derived from historical session data.
 * Used as baseline for anomaly detection.
 */
export interface UserBehavioralProfile {
  userId: string;
  profileId: string;
  createdAt: number; // Unix timestamp
  updatedAt: number; // Unix timestamp
  sampleCount: number; // Number of sessions used to build profile
  
  // Behavioral features (per-dimension statistics)
  loginTimes: {
    hours: number[]; // Histogram of login hours (0-23)
    mean?: number;
    stdDev?: number;
  };
  
  fileAccessPatterns: {
    extensions: Record<string, number>; // File extension frequency
    directories: Record<string, number>; // Directory access frequency
    mean_files_accessed?: number;
    stdDev_files_accessed?: number;
  };
  
  sessionDuration: {
    mean: number; // Mean session duration in seconds
    stdDev: number; // Standard deviation
    p95: number; // 95th percentile
  };
  
  dataTransfer: {
    mean_bytes?: number; // Mean bytes transferred
    stdDev_bytes?: number;
    p95_bytes?: number;
  };
  
  // Training metadata
  trainingData: {
    startDate: number;
    endDate: number;
    sessionCount: number;
  };
}

/**
 * A single session event with access pattern metrics.
 */
export interface SessionAccessEvent {
  sessionId: string;
  userId: string;
  timestamp: number;
  
  // Access pattern metrics
  loginHour: number; // 0-23
  filesAccessed: number;
  fileExtensions: string[]; // Unique extensions accessed
  directoriesAccessed: string[]; // Unique directories
  sessionDurationSeconds: number;
  bytesTransferred: number;
  
  // Metadata for context
  ipAddress?: string;
  userAgent?: string;
  isVpn?: boolean;
  geolocation?: string;
}

/**
 * Anomaly score for a session event relative to user's baseline.
 */
export interface AnomalyScore {
  sessionId: string;
  userId: string;
  timestamp: number;
  
  // Composite anomaly score (0-1, where 1 = most anomalous)
  overallScore: number;
  
  // Per-dimension scores
  dimensionScores: {
    loginTime: number;
    fileAccess: number;
    sessionDuration: number;
    dataTransfer: number;
  };
  
  // Most anomalous dimensions
  topAnomalies: Array<{
    dimension: string;
    score: number;
    description: string;
  }>;
  
  // Statistical method used
  method: 'z-score' | 'isolation-forest' | 'ensemble';
  
  // Confidence level
  confidence: number; // 0-1
}

/**
 * Alert triggered when anomaly exceeds threshold.
 */
export interface AnomalyAlert {
  alertId: string;
  userId: string;
  sessionId: string;
  timestamp: number;
  severity: 'low' | 'medium' | 'high' | 'critical';
  
  // Alert details
  title: string;
  description: string;
  anomalyType: 'login-timing' | 'file-access' | 'data-transfer' | 'session-duration' | 'composite';
  anomalyScore: AnomalyScore;
  
  // Action taken
  action?: 'notify' | 'block' | 'mfa-challenge' | 'review';
  actionTaken?: boolean;
  actionTimestamp?: number;
}

/**
 * Configuration for anomaly detection engine.
 */
export interface AnomalyDetectionConfig {
  // Thresholds
  anomalyScoreThreshold: number; // 0-1, typically 0.7
  
  // Z-score thresholds per dimension
  zScoreThreshold: number; // Typically 2.0-3.0 std devs
  
  // Model retraining
  retrainingIntervalMs: number; // Weekly = 7 * 24 * 60 * 60 * 1000
  minSamplesForProfile: number; // Minimum sessions before building profile
  
  // False positive mitigation
  maxAlertsPerUserPerDay: number;
  gracePeriodMs: number; // Grace period after profile build
  
  // Feature extraction
  enableLoginTimeAnalysis: boolean;
  enableFileAccessAnalysis: boolean;
  enableSessionDurationAnalysis: boolean;
  enableDataTransferAnalysis: boolean;
  
  // Alerting
  enablePrometheusAlerts: boolean;
  enableMatrixNotifications: boolean;
  matrixChannel?: string;
}

/**
 * Statistics used in anomaly scoring.
 */
export interface DimensionStatistics {
  dimension: string;
  mean: number;
  stdDev: number;
  min: number;
  max: number;
  p25: number;
  p50: number;
  p75: number;
  p95: number;
  sampleCount: number;
}

/**
 * Result of anomaly detection run.
 */
export interface AnomalyDetectionResult {
  sessionId: string;
  userId: string;
  timestamp: number;
  isAnomaly: boolean;
  anomalyScore?: AnomalyScore;
  alerts: AnomalyAlert[];
  processingTimeMs: number;
}
