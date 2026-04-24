#!/usr/bin/env node
// @file        apps/backend/src/services/voice-channel/types.ts
// @module      collaboration/voice-channel
// @description Type definitions for voice channel service

/**
 * Voice channel session metadata
 */
export interface VoiceSession {
  sessionId: string;
  workspaceId: string;
  userId: string;
  liveKitToken: string;
  liveKitRoomName: string;
  startedAt: number;
  participantCount: number;
  status: 'active' | 'idle' | 'ended';
}

/**
 * Participant in a voice session
 */
export interface VoiceParticipant {
  userId: string;
  username: string;
  displayName: string;
  status: 'connected' | 'disconnected' | 'muted' | 'deafened';
  joinedAt: number;
  audioLatencyMs?: number;
  audioQualityScore?: number; // 0-100
}

/**
 * Voice channel statistics for monitoring
 */
export interface VoiceStats {
  activeSessionsCount: number;
  totalParticipants: number;
  averageLatencyMs: number;
  audioQualityP50: number;
  audioQualityP95: number;
  noiseReductionEnabled: boolean;
  timestamp: number;
}

/**
 * Voice channel configuration
 */
export interface VoiceChannelConfig {
  liveKitUrl: string;
  liveKitApiKey: string;
  liveKitApiSecret: string;
  noiseCancellationEnabled: boolean;
  targetLatencyMs: number; // Target < 60ms per SLA
  maxParticipantsPerRoom: number;
  audioCodec: 'opus' | 'aac'; // Opus preferred for low latency
  enableRecording: boolean;
  recordingStoragePath?: string;
}

/**
 * Voice channel events
 */
export interface VoiceChannelEvent {
  type:
    | 'session_created'
    | 'participant_joined'
    | 'participant_left'
    | 'participant_muted'
    | 'participant_deafened'
    | 'latency_high'
    | 'audio_quality_degraded'
    | 'session_ended';
  sessionId: string;
  timestamp: number;
  data?: Record<string, any>;
}

/**
 * LiveKit webhook payload for participant events
 */
export interface LiveKitWebhookPayload {
  event: 'participant_joined' | 'participant_left' | 'room_finished' | string;
  createdAt: number;
  room?: {
    sid: string;
    name: string;
    emptyTimeout: number;
    maxParticipants: number;
    creationTime: number;
  };
  participant?: {
    sid: string;
    identity: string;
    state: string;
    tracks: Array<{
      sid: string;
      type: string;
      codec: string;
      muted: boolean;
    }>;
  };
}
