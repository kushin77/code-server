// @file        apps/backend/src/services/screen-share/types.ts
// @module      collaboration/screen-share
// @description Type definitions for screen share service

export interface ScreenShareSession {
  id: string;
  workspaceId: string;
  presenterId: string;
  participantIds: string[];
  startedAt: Date;
  endedAt?: Date;
  isActive: boolean;
}

export interface ScreenShareAnnotation {
  id: string;
  sessionId: string;
  userId: string;
  type: 'pointer' | 'drawing' | 'highlight';
  x: number;
  y: number;
  color?: string;
  timestamp: Date;
}

export interface CursorPosition {
  userId: string;
  x: number;
  y: number;
  timestamp: Date;
}

export interface ScreenShareConfig {
  workspaceId: string;
  maxParticipants?: number;
  crdtBackend?: 'yjs' | 'automerge';
}

export interface ScreenShareEvent {
  type: 'session_started' | 'session_ended' | 'participant_joined' | 'participant_left' | 'annotation_added' | 'cursor_moved';
  sessionId: string;
  userId: string;
  timestamp: Date;
  data?: unknown;
}
