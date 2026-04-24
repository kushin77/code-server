/**
 * Session Recording Service Types
 * Full-fidelity session recording with multi-speed playback and video export
 */

/**
 * Event types that can be recorded
 */
export type RecordableEventType =
  | 'file-change'
  | 'file-create'
  | 'file-delete'
  | 'terminal-output'
  | 'terminal-input'
  | 'debug-breakpoint'
  | 'debug-step'
  | 'chat-message'
  | 'editor-selection'
  | 'cursor-move'
  | 'settings-change'
  | 'extension-install'
  | 'extension-uninstall';

/**
 * Individual recorded event
 */
export interface RecordedEvent {
  id: string;
  timestamp: number;
  eventType: RecordableEventType;
  userId: string;
  workspaceId: string;
  sessionId: string;
  data: Record<string, unknown>;
  metadata?: {
    filePath?: string;
    lineNumber?: number;
    terminalId?: string;
    debugSessionId?: string;
    messageId?: string;
  };
}

/**
 * Recording session
 */
export interface RecordingSession {
  id: string;
  userId: string;
  workspaceId: string;
  sessionId: string;
  startTime: number;
  endTime?: number;
  duration: number; // ms
  isActive: boolean;
  eventCount: number;
  fileChanges: number;
  terminalOutput: number;
  chatMessages: number;
  debugEvents: number;
  size: number; // bytes
  tags: string[];
  description: string;
  visibility: 'private' | 'internal' | 'public';
  expiresAt: number; // 90 days default
  shareableUrl?: string;
  shareableUrlToken?: string;
}

/**
 * Playback position
 */
export interface PlaybackPosition {
  eventIndex: number;
  timestamp: number;
  progress: number; // 0-100
}

/**
 * Playback state
 */
export interface PlaybackState {
  recordingId: string;
  isPlaying: boolean;
  speed: number; // 0.5-10
  position: PlaybackPosition;
  currentEvent?: RecordedEvent;
  totalEvents: number;
  totalDuration: number;
}

/**
 * Playback request
 */
export interface PlaybackRequest {
  recordingId: string;
  userId: string;
  startEventIndex?: number;
  speed?: number; // 0.5-10, default 1
  filters?: {
    eventTypes?: RecordableEventType[];
    filePath?: string;
    startTime?: number;
    endTime?: number;
  };
}

/**
 * Playback result
 */
export interface PlaybackResult {
  recordingId: string;
  eventIndex: number;
  timestamp: number;
  event: RecordedEvent;
  speed: number;
  progress: number;
  nextEventIndex?: number;
}

/**
 * Video export request
 */
export interface VideoExportRequest {
  recordingId: string;
  userId: string;
  format: 'mp4' | 'webm' | 'mov';
  quality: 'low' | 'medium' | 'high'; // 480p, 720p, 1080p
  speed?: number;
  startTime?: number;
  endTime?: number;
  includeTerminal: boolean;
  includeEditor: boolean;
  includeChat: boolean;
  watermark?: string;
}

/**
 * Video export result
 */
export interface VideoExportResult {
  recordingId: string;
  videoUrl: string;
  format: string;
  size: number; // bytes
  duration: number; // ms
  quality: string;
  created: number;
  expiresAt: number;
}

/**
 * Recording metadata
 */
export interface RecordingMetadata {
  recordingId: string;
  userId: string;
  workspaceId: string;
  startTime: number;
  endTime?: number;
  duration: number;
  eventCount: number;
  size: number;
  visibility: 'private' | 'internal' | 'public';
  tags: string[];
  shareableUrl?: string;
  expiresAt: number;
}

/**
 * Shareable link
 */
export interface ShareableLink {
  token: string;
  recordingId: string;
  createdBy: string;
  createdAt: number;
  expiresAt: number;
  accessCount: number;
  maxAccess?: number;
  visibility: 'public' | 'link-only' | 'password-protected';
  password?: string;
  allowDownload: boolean;
  allowPlayback: boolean;
}

/**
 * Recording statistics
 */
export interface RecordingStatistics {
  totalRecordings: number;
  recordingsByUser: Record<string, number>;
  recordingsByWorkspace: Record<string, number>;
  totalEvents: number;
  averageEventsPerRecording: number;
  totalStorage: number;
  averageStoragePerRecording: number;
  playbackSessions: number;
  videoExports: number;
  shareableLinksCreated: number;
}

/**
 * Recording query
 */
export interface RecordingQuery {
  userId?: string;
  workspaceId?: string;
  startTime?: number;
  endTime?: number;
  tags?: string[];
  visibility?: 'private' | 'internal' | 'public';
  limit?: number;
  offset?: number;
}

/**
 * Recording query result
 */
export interface RecordingQueryResult {
  recordings: RecordingMetadata[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * SOC2 audit entry for recordings
 */
export interface RecordingAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'started' | 'stopped' | 'played' | 'exported' | 'shared' | 'deleted' | 'accessed';
  status: 'success' | 'denied' | 'error';
  recordingId: string;
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  details?: Record<string, unknown>;
}

/**
 * Recording service configuration
 */
export interface RecordingServiceConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  maxRecordingsPerUser: number;
  maxEventCaptureRate: number; // events per second
  videoExportEnabled: boolean;
  shareableLinksEnabled: boolean;
  retentionDays: number; // 90 default
  compressionEnabled: boolean;
  encryptionEnabled: boolean;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'disk' | 's3';
  videoStorageBackend: 's3' | 'cdn';
}

/**
 * Recording filter options for advanced queries
 */
export interface RecordingFilter {
  includeFileChanges: boolean;
  includeTerminalOutput: boolean;
  includeChatMessages: boolean;
  includeDebugEvents: boolean;
  minDuration: number; // ms
  maxDuration: number; // ms
  hasVideo: boolean;
}
