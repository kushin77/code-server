/**
 * @file        packages/shared-events/src/index.ts
 * @module      shared-events
 * @description Canonical Event Schema and standardized interfaces for cross-service communication
 * @owner       architecture-team
 * @status      active
 */

/**
 * Standard severity levels for all platform events
 */
export type EventSeverity = 'low' | 'medium' | 'high' | 'critical';

/**
 * Standard categories of platform events
 */
export type EventCategory = 'collaboration' | 'ai' | 'infrastructure' | 'security' | 'presence' | 'system';

/**
 * Base Event Schema (Canonical)
 * Every event in the system MUST implement this interface
 */
export interface BaseEvent {
  /** Unique identifier for the specific event instance */
  id: string;
  /** Namespace or service that produced this event (e.g., 'crdt-service', 'conflict-prediction') */
  source: string;
  /** Type of event (e.g., 'document-edit', 'conflict-predicted') */
  type: string;
  /** Category for generalized routing/grouping */
  category: EventCategory;
  /** Severity level for alerting and persistence */
  severity: EventSeverity;
  /** ISO-8601 timestamp or milliseconds since epoch */
  timestamp: number | string;
  /** User responsible for the action (if applicable) */
  userId?: string;
  /** Workspace ID context */
  workspaceId?: string;
  /** Extensible payload for specific event details */
  payload: Record<string, any>;
  /** Trace ID for distributed observability */
  traceId?: string;
}

/**
 * Standardized Conflict Prediction Event
 * Derived from canonical BaseEvent
 */
export interface ConflictPredictionEvent extends BaseEvent {
  category: 'ai';
  type: 'conflict-predicted';
  payload: {
    filePath: string;
    functionName: string | null;
    riskScore: number;
    conflictingUserIds: string[];
    affectedRange?: {
      start: number;
      end: number;
    };
  };
}

/**
 * Standardized CRDT Edit Event
 * Derived from canonical BaseEvent
 */
export interface CRDTEditEvent extends BaseEvent {
  category: 'collaboration';
  type: 'document-edit';
  payload: {
    documentId: string;
    operation: {
      type: 'insert' | 'delete';
      position: number;
      content?: string;
      length?: number;
    };
    version: number;
    vectorClock: Record<string, number>;
  };
}

/**
 * Standardized Presence Event
 */
export interface PresenceEvent extends BaseEvent {
  category: 'presence';
  type: 'user-status-change' | 'cursor-move';
  payload: {
    status?: 'online' | 'away' | 'dnd' | 'offline';
    lastActive?: number;
    currentFile?: string;
    cursorPosition?: {
      line: number;
      column: number;
    };
  };
}

/**
 * Utility: Event Validation Helper
 */
export function isValidEvent(event: any): event is BaseEvent {
  return (
    typeof event === 'object' &&
    typeof event.id === 'string' &&
    typeof event.source === 'string' &&
    typeof event.type === 'string' &&
    ['collaboration', 'ai', 'infrastructure', 'security', 'presence', 'system'].includes(event.category) &&
    ['low', 'medium', 'high', 'critical'].includes(event.severity) &&
    (typeof event.timestamp === 'number' || typeof event.timestamp === 'string') &&
    typeof event.payload === 'object'
  );
}
