/**
 * @file        apps/backend/src/services/crdt-operations/index.ts
 * @module      collaboration/crdt
 * @description CRDT (Conflict-free Replicated Data Type) operations service for real-time concurrent file editing
 *
 * This service provides operational transformation for multiple concurrent edits without blocking.
 * Uses position-based insert/delete operations with vector clocks for causality tracking.
 */

import { EventEmitter } from 'events';

/**
 * Represents a single CRDT operation (insert or delete)
 */
export interface CRDTOperation {
  id: string;
  type: 'insert' | 'delete';
  clientId: string;
  timestamp: number;
  position: number;
  content?: string; // for insert operations
  length?: number;  // for delete operations
  vectorClock: Record<string, number>; // causality tracking across clients
}

/**
 * Represents the state of a document with all applied operations
 */
export interface CRDTDocumentState {
  content: string;
  version: number;
  lastOperationId: string | null;
  vectorClock: Record<string, number>;
}

/**
 * CRDT Operations Service
 *
 * Manages concurrent document editing with automatic conflict resolution.
 * Uses Operational Transformation (OT) principles: all clients converge to same state
 * regardless of operation order.
 */
export class CRDTOperationsService extends EventEmitter {
  private documentStates: Map<string, CRDTDocumentState> = new Map();
  private operationHistory: Map<string, CRDTOperation[]> = new Map();
  private clientVectorClocks: Map<string, Record<string, number>> = new Map();

  constructor() {
    super();
  }

  /**
   * Initialize a new document for editing
   */
  initializeDocument(documentId: string, initialContent: string = ''): CRDTDocumentState {
    const state: CRDTDocumentState = {
      content: initialContent,
      version: 0,
      lastOperationId: null,
      vectorClock: {},
    };

    this.documentStates.set(documentId, state);
    this.operationHistory.set(documentId, []);

    this.emit('documentInitialized', { documentId, state });
    return state;
  }

  /**
   * Apply an insert operation to the document
   * Position is adjusted based on concurrent operations (OT transform)
   */
  applyInsertOperation(
    documentId: string,
    clientId: string,
    position: number,
    content: string,
  ): { operation: CRDTOperation; state: CRDTDocumentState } {
    const state = this.documentStates.get(documentId);
    if (!state) {
      throw new Error(`Document ${documentId} not found`);
    }

    // Initialize client vector clock if needed
    if (!this.clientVectorClocks.has(clientId)) {
      this.clientVectorClocks.set(clientId, {});
    }

    const clientClock = this.clientVectorClocks.get(clientId)!;
    clientClock[clientId] = (clientClock[clientId] || 0) + 1;

    // Get operation history for this document
    const history = this.operationHistory.get(documentId) || [];

    // Transform position based on concurrent operations (OT algorithm)
    let transformedPosition = position;
    for (const op of history) {
      if (op.vectorClock[clientId] === undefined || op.vectorClock[clientId] < clientClock[clientId] - 1) {
        // Operation happened concurrently or before this client's operation
        if (op.type === 'insert' && op.position < transformedPosition) {
          transformedPosition += op.content?.length || 0;
        } else if (op.type === 'delete' && op.position < transformedPosition) {
          transformedPosition = Math.max(op.position, transformedPosition - (op.length || 0));
        }
      }
    }

    // Create operation
    const operation: CRDTOperation = {
      id: `${documentId}-${clientId}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      type: 'insert',
      clientId,
      timestamp: Date.now(),
      position: transformedPosition,
      content,
      vectorClock: { ...clientClock },
    };

    // Apply operation to document content
    state.content = state.content.slice(0, transformedPosition) + content + state.content.slice(transformedPosition);
    state.version++;
    state.lastOperationId = operation.id;
    state.vectorClock = { ...clientClock };

    // Store operation in history
    history.push(operation);
    this.operationHistory.set(documentId, history);

    this.emit('insertOperation', { documentId, operation, state });

    return { operation, state };
  }

  /**
   * Apply a delete operation to the document
   */
  applyDeleteOperation(
    documentId: string,
    clientId: string,
    position: number,
    length: number,
  ): { operation: CRDTOperation; state: CRDTDocumentState } {
    const state = this.documentStates.get(documentId);
    if (!state) {
      throw new Error(`Document ${documentId} not found`);
    }

    // Initialize client vector clock if needed
    if (!this.clientVectorClocks.has(clientId)) {
      this.clientVectorClocks.set(clientId, {});
    }

    const clientClock = this.clientVectorClocks.get(clientId)!;
    clientClock[clientId] = (clientClock[clientId] || 0) + 1;

    // Get operation history
    const history = this.operationHistory.get(documentId) || [];

    // Transform position based on concurrent operations
    let transformedPosition = position;
    let transformedLength = length;
    for (const op of history) {
      if (op.vectorClock[clientId] === undefined || op.vectorClock[clientId] < clientClock[clientId] - 1) {
        if (op.type === 'insert' && op.position < transformedPosition) {
          transformedPosition += op.content?.length || 0;
        } else if (op.type === 'delete' && op.position < transformedPosition) {
          transformedPosition = Math.max(op.position, transformedPosition - (op.length || 0));
          transformedLength = Math.max(0, transformedLength - (op.length || 0));
        }
      }
    }

    // Create operation
    const operation: CRDTOperation = {
      id: `${documentId}-${clientId}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      type: 'delete',
      clientId,
      timestamp: Date.now(),
      position: transformedPosition,
      length: transformedLength,
      vectorClock: { ...clientClock },
    };

    // Apply operation to document content
    state.content = state.content.slice(0, transformedPosition) + state.content.slice(transformedPosition + transformedLength);
    state.version++;
    state.lastOperationId = operation.id;
    state.vectorClock = { ...clientClock };

    // Store operation in history
    history.push(operation);
    this.operationHistory.set(documentId, history);

    this.emit('deleteOperation', { documentId, operation, state });

    return { operation, state };
  }

  /**
   * Get current document state
   */
  getDocumentState(documentId: string): CRDTDocumentState | undefined {
    return this.documentStates.get(documentId);
  }

  /**
   * Get operation history for a document
   */
  getOperationHistory(documentId: string): CRDTOperation[] {
    return this.operationHistory.get(documentId) || [];
  }

  /**
   * Get operations after a specific version (for sync/replication)
   */
  getOperationsSince(documentId: string, version: number): CRDTOperation[] {
    const history = this.operationHistory.get(documentId) || [];
    // Simple version-based approach: return all operations after the given version
    const state = this.documentStates.get(documentId);
    if (!state) return [];

    // Return operations that happened after the specified version
    return history.slice(Math.max(0, version));
  }

  /**
   * List all active documents
   */
  listDocuments(): string[] {
    return Array.from(this.documentStates.keys());
  }
}

export default CRDTOperationsService;
