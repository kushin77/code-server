/**
 * @file        apps/backend/src/services/voice/types.ts
 * @module      services/voice
 * @description Types for voice channel service with WebRTC + LiveKit SFU backend
 *
 */

/**
 * WebRTC codec configuration
 */
export type AudioCodec = 'opus' | 'aac' | 'pcm';

/**
 * Voice quality settings
 */
export type VoiceQuality = 'low' | 'medium' | 'high';

/**
 * Voice participant status
 */
export type ParticipantStatus = 'connecting' | 'connected' | 'muted' | 'deafened' | 'disconnecting' | 'disconnected';

/**
 * Audio track status
 */
export type AudioTrackStatus = 'enabled' | 'disabled' | 'muted';

/**
 * Voice connection state
 */
export type VoiceConnectionState = 'new' | 'connecting' | 'connected' | 'reconnecting' | 'disconnecting' | 'disconnected' | 'failed';

/**
 * Voice event types
 */
export type VoiceEventType =
  | 'participant-joined'
  | 'participant-left'
  | 'participant-muted'
  | 'participant-unmuted'
  | 'participant-deafened'
  | 'participant-undeafened'
  | 'connection-state-changed'
  | 'audio-level-changed'
  | 'connection-latency-updated'
  | 'connection-stats-updated'
  | 'local-audio-enabled'
  | 'local-audio-disabled'
  | 'remote-audio-enabled'
  | 'remote-audio-disabled'
  | 'channel-error';

/**
 * Audio level data
 */
export interface AudioLevel {
  participantId: string;
  participantName: string;
  level: number; // 0-100
  timestamp: number;
  isSpeaking: boolean;
}

/**
 * Voice participant
 */
export interface VoiceParticipant {
  id: string;
  userId: string;
  userEmail: string;
  displayName: string;
  status: ParticipantStatus;
  isMuted: boolean;
  isDeafened: boolean;
  joinedAt: number;
  audioLevel: number; // 0-100
  lastAudioLevelUpdate: number;
  latency: number; // ms
  bitrate: number; // kbps
  packetLoss: number; // 0-100
}

/**
 * Voice channel room
 */
export interface VoiceChannel {
  id: string;
  workspaceId: string;
  name: string;
  description: string;
  createdAt: number;
  createdBy: string;
  participants: VoiceParticipant[];
  livekitRoomName: string;
  connectionState: VoiceConnectionState;
  activeParticipantCount: number;
  maxParticipants: number;
  isRecording: boolean;
  recordingStartedAt: number | null;
  transcriptionEnabled: boolean;
}

/**
 * Voice connection stats
 */
export interface VoiceConnectionStats {
  connectionDuration: number; // ms
  roundTripTime: number; // ms
  averageLatency: number; // ms
  maxLatency: number; // ms
  minLatency: number; // ms
  packetLoss: number; // 0-100
  bitrate: number; // kbps
  audioCodec: AudioCodec;
  noiseSuppressionEnabled: boolean;
  echoCancellationEnabled: boolean;
  autoGainControlEnabled: boolean;
}

/**
 * Create voice channel request
 */
export interface CreateVoiceChannelRequest {
  userId: string;
  userEmail: string;
  workspaceId: string;
  channelName: string;
  description?: string;
  maxParticipants?: number;
}

/**
 * Create voice channel result
 */
export interface CreateVoiceChannelResult {
  success: boolean;
  channelId: string;
  livekitToken: string;
  livekitUrl: string;
  channel: VoiceChannel;
  error?: string;
}

/**
 * Join voice channel request
 */
export interface JoinVoiceChannelRequest {
  userId: string;
  userEmail: string;
  displayName: string;
  channelId: string;
}

/**
 * Join voice channel result
 */
export interface JoinVoiceChannelResult {
  success: boolean;
  participantId: string;
  livekitToken: string;
  livekitUrl: string;
  livekitRoomName: string;
  channel: VoiceChannel;
  error?: string;
}

/**
 * Leave voice channel request
 */
export interface LeaveVoiceChannelRequest {
  userId: string;
  userEmail: string;
  channelId: string;
  participantId: string;
}

/**
 * Leave voice channel result
 */
export interface LeaveVoiceChannelResult {
  success: boolean;
  error?: string;
}

/**
 * Mute participant request
 */
export interface MuteParticipantRequest {
  userId: string;
  userEmail: string;
  channelId: string;
  participantId: string;
  isMuted: boolean;
}

/**
 * Mute participant result
 */
export interface MuteParticipantResult {
  success: boolean;
  participant: VoiceParticipant;
  error?: string;
}

/**
 * Deafen participant request
 */
export interface DeafenParticipantRequest {
  userId: string;
  userEmail: string;
  channelId: string;
  participantId: string;
  isDeafened: boolean;
}

/**
 * Deafen participant result
 */
export interface DeafenParticipantResult {
  success: boolean;
  participant: VoiceParticipant;
  error?: string;
}

/**
 * Get voice channel request
 */
export interface GetVoiceChannelRequest {
  channelId: string;
}

/**
 * Get voice channel result
 */
export interface GetVoiceChannelResult {
  success: boolean;
  channel: VoiceChannel | null;
  error?: string;
}

/**
 * Get participants request
 */
export interface GetParticipantsRequest {
  channelId: string;
}

/**
 * Get participants result
 */
export interface GetParticipantsResult {
  success: boolean;
  participants: VoiceParticipant[];
  count: number;
  error?: string;
}

/**
 * Update audio level request
 */
export interface UpdateAudioLevelRequest {
  participantId: string;
  level: number; // 0-100
  isSpeaking: boolean;
}

/**
 * Update connection stats request
 */
export interface UpdateConnectionStatsRequest {
  participantId: string;
  roundTripTime: number;
  packetLoss: number;
  bitrate: number;
}

/**
 * Toggle local audio request
 */
export interface ToggleLocalAudioRequest {
  userId: string;
  userEmail: string;
  channelId: string;
  participantId: string;
  enabled: boolean;
}

/**
 * Toggle local audio result
 */
export interface ToggleLocalAudioResult {
  success: boolean;
  enabled: boolean;
  error?: string;
}

/**
 * Start recording request
 */
export interface StartRecordingRequest {
  userId: string;
  userEmail: string;
  channelId: string;
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
  channelId: string;
}

/**
 * Stop recording result
 */
export interface StopRecordingResult {
  success: boolean;
  recordingId: string;
  duration: number; // ms
  error?: string;
}

/**
 * Voice audit entry
 */
export interface VoiceAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: string;
  channelId: string;
  participantId?: string;
  status: 'success' | 'failure';
  details?: Record<string, any>;
}

/**
 * Voice channel statistics
 */
export interface VoiceStatistics {
  totalChannels: number;
  activeChannels: number;
  totalParticipants: number;
  currentParticipants: number;
  totalConnections: number;
  failedConnections: number;
  averageLatency: number;
  totalRecordings: number;
  activeRecordings: number;
  noiseSuppressionUsage: number; // %
  echoCancellationUsage: number; // %
}

/**
 * Voice service configuration
 */
export interface VoiceServiceConfig {
  maxChannelsPerWorkspace: number;
  maxParticipantsPerChannel: number;
  maxAuditLogSize: number;
  enableNoiseSuppression: boolean;
  enableEchoCancellation: boolean;
  enableAutoGainControl: boolean;
  enableTranscription: boolean;
  enableRecording: boolean;
  defaultAudioCodec: AudioCodec;
  defaultVoiceQuality: VoiceQuality;
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  speakingThreshold: number; // 0-100
  silenceTimeout: number; // ms
  reconnectTimeout: number; // ms
  maxReconnectAttempts: number;
}

/**
 * Voice event data
 */
export interface VoiceEventData {
  eventType: VoiceEventType;
  channelId?: string;
  participantId?: string;
  participant?: VoiceParticipant;
  channel?: VoiceChannel;
  audioLevel?: AudioLevel;
  stats?: VoiceConnectionStats;
  error?: string;
  timestamp: number;
}

/**
 * Noise suppression settings
 */
export interface NoiseSuppressionSettings {
  enabled: boolean;
  aggressiveness: 'low' | 'medium' | 'high';
}

/**
 * Echo cancellation settings
 */
export interface EchoCancellationSettings {
  enabled: boolean;
  echoReturnLoss: number; // dB
}

/**
 * Auto gain control settings
 */
export interface AutoGainControlSettings {
  enabled: boolean;
  targetLevel: number; // dB
}

/**
 * Audio processing settings
 */
export interface AudioProcessingSettings {
  noiseSuppression: NoiseSuppressionSettings;
  echoCancellation: EchoCancellationSettings;
  autoGainControl: AutoGainControlSettings;
}

/**
 * Connection quality indicator
 */
export type ConnectionQuality = 'excellent' | 'good' | 'fair' | 'poor' | 'very-poor';

/**
 * Get connection quality helper
 */
export function getConnectionQuality(latency: number, packetLoss: number): ConnectionQuality {
  if (latency < 30 && packetLoss < 1) return 'excellent';
  if (latency < 60 && packetLoss < 2) return 'good';
  if (latency < 100 && packetLoss < 5) return 'fair';
  if (latency < 200 && packetLoss < 10) return 'poor';
  return 'very-poor';
}
