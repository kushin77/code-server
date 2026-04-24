/**
 * @file        apps/backend/src/services/screenshare/types.ts
 * @module      services/screenshare
 * @description Types for screen share service with CRDT-based drawing/pointer annotations
 *
 */

/**
 * Annotation type
 */
export type AnnotationType = 'pen' | 'arrow' | 'rectangle' | 'circle' | 'text' | 'pointer' | 'highlight';

/**
 * Share quality settings
 */
export type ShareQuality = 'low' | 'medium' | 'high';

/**
 * Share state
 */
export type ShareState = 'idle' | 'capturing' | 'streaming' | 'paused' | 'stopped';

/**
 * Participant role in screen share
 */
export type ParticipantRole = 'presenter' | 'viewer' | 'annotator';

/**
 * Drawing color type
 */
export type DrawingColor = 'black' | 'red' | 'blue' | 'green' | 'yellow' | 'purple' | 'orange' | 'white';

/**
 * Drawing style
 */
export type DrawingStyle = 'solid' | 'dashed' | 'dotted';

/**
 * Annotation point on screen
 */
export interface Point {
  x: number;
  y: number;
  timestamp: number;
}

/**
 * Drawing stroke annotation
 */
export interface DrawingStroke {
  id: string;
  annotationType: AnnotationType;
  userId: string;
  userName: string;
  points: Point[];
  color: DrawingColor;
  lineWidth: number;
  style: DrawingStyle;
  opacity: number;
  createdAt: number;
  updatedAt: number;
  crdt: {
    clientId: string;
    clock: number;
    version: number;
  };
}

/**
 * Pointer cursor
 */
export interface Cursor {
  id: string;
  userId: string;
  userName: string;
  position: Point;
  isVisible: boolean;
  color: DrawingColor;
  label: string;
  lastSeenAt: number;
}

/**
 * Screen share session
 */
export interface ScreenShareSession {
  id: string;
  workspaceId: string;
  presenterId: string;
  presenterName: string;
  presenterEmail: string;
  startedAt: number;
  state: ShareState;
  quality: ShareQuality;
  screenTitle: string;
  screenResolution: { width: number; height: number };
  participants: Map<string, ParticipantRole>;
  viewers: number;
  annotators: number;
  annotations: Map<string, DrawingStroke>;
  cursors: Map<string, Cursor>;
  recordingId: string | null;
  isRecording: boolean;
}

/**
 * Start screen share request
 */
export interface StartScreenShareRequest {
  userId: string;
  userEmail: string;
  userName: string;
  workspaceId: string;
  screenTitle?: string;
  screenResolution?: { width: number; height: number };
  quality?: ShareQuality;
}

/**
 * Start screen share result
 */
export interface StartScreenShareResult {
  success: boolean;
  sessionId: string;
  session: ScreenShareSession | null;
  streamUrl: string;
  error?: string;
}

/**
 * Join screen share request
 */
export interface JoinScreenShareRequest {
  userId: string;
  userEmail: string;
  userName: string;
  sessionId: string;
  role: ParticipantRole;
}

/**
 * Join screen share result
 */
export interface JoinScreenShareResult {
  success: boolean;
  sessionId: string;
  session: ScreenShareSession | null;
  streamUrl: string;
  error?: string;
}

/**
 * Add drawing annotation request
 */
export interface AddDrawingRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
  annotationType: AnnotationType;
  points: Point[];
  color: DrawingColor;
  lineWidth: number;
  style: DrawingStyle;
  opacity: number;
}

/**
 * Add drawing annotation result
 */
export interface AddDrawingResult {
  success: boolean;
  annotationId: string;
  annotation: DrawingStroke | null;
  error?: string;
}

/**
 * Clear annotation request
 */
export interface ClearAnnotationRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
  annotationId: string;
}

/**
 * Clear annotation result
 */
export interface ClearAnnotationResult {
  success: boolean;
  error?: string;
}

/**
 * Update cursor request
 */
export interface UpdateCursorRequest {
  userId: string;
  userName: string;
  sessionId: string;
  position: Point;
  isVisible: boolean;
  color: DrawingColor;
  label?: string;
}

/**
 * Update cursor result
 */
export interface UpdateCursorResult {
  success: boolean;
  cursor: Cursor | null;
  error?: string;
}

/**
 * Get annotations request
 */
export interface GetAnnotationsRequest {
  sessionId: string;
}

/**
 * Get annotations result
 */
export interface GetAnnotationsResult {
  success: boolean;
  annotations: DrawingStroke[];
  count: number;
  error?: string;
}

/**
 * Get cursors request
 */
export interface GetCursorsRequest {
  sessionId: string;
}

/**
 * Get cursors result
 */
export interface GetCursorsResult {
  success: boolean;
  cursors: Cursor[];
  count: number;
  error?: string;
}

/**
 * Leave screen share request
 */
export interface LeaveScreenShareRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
}

/**
 * Leave screen share result
 */
export interface LeaveScreenShareResult {
  success: boolean;
  error?: string;
}

/**
 * Start recording request
 */
export interface StartRecordingRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
}

/**
 * Start recording result
 */
export interface StartRecordingResult {
  success: boolean;
  recordingId: string;
  startedAt: number;
  error?: string;
}

/**
 * Stop recording request
 */
export interface StopRecordingRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
}

/**
 * Stop recording result
 */
export interface StopRecordingResult {
  success: boolean;
  recordingId: string;
  duration: number;
  error?: string;
}

/**
 * Pause share request
 */
export interface PauseShareRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
}

/**
 * Pause share result
 */
export interface PauseShareResult {
  success: boolean;
  error?: string;
}

/**
 * Resume share request
 */
export interface ResumeShareRequest {
  userId: string;
  userEmail: string;
  sessionId: string;
}

/**
 * Resume share result
 */
export interface ResumeShareResult {
  success: boolean;
  error?: string;
}

/**
 * Screen share audit entry
 */
export interface ScreenShareAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: string;
  sessionId: string;
  status: 'success' | 'failure';
  details?: Record<string, any>;
}

/**
 * Screen share statistics
 */
export interface ScreenShareStatistics {
  totalSessions: number;
  activeSessions: number;
  totalParticipants: number;
  totalAnnotations: number;
  totalRecordings: number;
  activeRecordings: number;
  averageSessionDuration: number;
  totalViewerHours: number;
  averageAnnotationsPerSession: number;
}

/**
 * Screen share service configuration
 */
export interface ScreenShareServiceConfig {
  maxConcurrentSessions: number;
  maxParticipantsPerSession: number;
  maxAnnotationsPerSession: number;
  maxAuditLogSize: number;
  defaultQuality: ShareQuality;
  enableRecording: boolean;
  enableAnnotations: boolean;
  crdtSyncInterval: number;
  cursorUpdateInterval: number;
  annotationTimeout: number;
  cursorTimeout: number;
}

/**
 * CRDT operation for annotation sync
 */
export interface CRDTOperation {
  clientId: string;
  clock: number;
  timestamp: number;
  operation: 'add' | 'update' | 'delete';
  annotationId: string;
  data: DrawingStroke | null;
}

/**
 * Screen share event data
 */
export interface ScreenShareEventData {
  eventType: string;
  sessionId?: string;
  userId?: string;
  annotation?: DrawingStroke;
  cursor?: Cursor;
  annotations?: DrawingStroke[];
  cursors?: Cursor[];
  timestamp: number;
}
