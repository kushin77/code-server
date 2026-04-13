/**
 * CRDT Sync Protocol
 * 
 * Implements Conflict-free Replicated Data Type (CRDT) protocol for
 * multi-primary PostgreSQL replication across geographically distributed regions.
 * 
 * Supports:
 * - OR-Set (Observed-Remove Set) for add/remove semantics
 * - Counter with causal ordering
 * - Register with Last-Write-Wins conflict resolution
 * - Map with concurrent field updates
 */

import * as uuid from 'uuid';

/**
 * Vector Clock for causal ordering
 * Tracks logical time per node to detect causality
 */
export interface VectorClock {
  [nodeId: string]: number;
}

/**
 * Unique identifier for CRDT operation
 * Combines node ID + timestamp + operation counter
 */
export interface UniqueId {
  nodeId: string;
  timestamp: number;
  counter: number;
}

/**
 * Base CRDT type with metadata
 */
export interface CRDTBase {
  type: 'OR-Set' | 'Counter' | 'Register' | 'Map';
  nodeId: string;
  vectorClock: VectorClock;
  lastUpdate: number;
}

/**
 * OR-Set (Observed-Remove Set)
 * Semantics: Add-wins on concurrent add/remove
 * Use case: Tags, categories, multi-select fields
 */
export interface ORSet extends CRDTBase {
  type: 'OR-Set';
  elements: Map<string, Set<UniqueId>>;
}

/**
 * Counter CRDT
 * Semantics: Increment/decrement with causal ordering
 * Use case: Counters, metrics
 */
export interface Counter extends CRDTBase {
  type: 'Counter';
  increments: Map<string, number>; // Per-node increments
  decrements: Map<string, number>; // Per-node decrements
}

/**
 * Register CRDT (Last-Write-Wins)
 * Semantics: Later timestamp wins
 * Use case: Simple scalar values
 */
export interface Register<T> extends CRDTBase {
  type: 'Register';
  value: T;
  timestamp: number;
}

/**
 * Map CRDT
 * Semantics: Composite type allowing concurrent field updates
 * Use case: Objects, structured data
 */
export interface MapCRDT extends CRDTBase {
  type: 'Map';
  fields: Map<string, CRDTValue>;
}

export type CRDTValue = ORSet | Counter | Register<any> | MapCRDT | null;

/**
 * Operation log entry for replication
 */
export interface Operation {
  id: UniqueId;
  type: 'add' | 'remove' | 'set' | 'update';
  crdt: string; // CRDT identifier
  field?: string;
  value: any;
  timestamp: number;
  nodeId: string;
  vectorClock: VectorClock;
}

/**
 * CRDT Sync Message
 */
export interface SyncMessage {
  sourceNodeId: string;
  targetNodeId: string;
  operations: Operation[];
  vectorClock: VectorClock;
  messageId: string;
  timestamp: number;
  sequence: number;
}

/**
 * Creates a unique ID for CRDT operations
 */
export class UniqueIdGenerator {
  private counter = 0;
  private nodeId: string;

  constructor(nodeId: string = uuid.v4()) {
    this.nodeId = nodeId;
  }

  generate(timestamp: number = Date.now()): UniqueId {
    return {
      nodeId: this.nodeId,
      timestamp,
      counter: this.counter++,
    };
  }

  reset() {
    this.counter = 0;
  }
}

/**
 * Vector Clock implementation
 * Used for causal ordering and conflict detection
 */
export class VectorClockManager {
  private clock: VectorClock = {};

  constructor(nodeId: string) {
    this.clock[nodeId] = 0;
  }

  increment(nodeId: string): void {
    if (!(nodeId in this.clock)) {
      this.clock[nodeId] = 0;
    }
    this.clock[nodeId]++;
  }

  merge(other: VectorClock): void {
    for (const [nodeId, timestamp] of Object.entries(other)) {
      if (!(nodeId in this.clock)) {
        this.clock[nodeId] = 0;
      }
      this.clock[nodeId] = Math.max(this.clock[nodeId], timestamp);
    }
  }

  getClock(): VectorClock {
    return { ...this.clock };
  }

  /**
   * Check if clock A happens before clock B
   */
  happensBefore(a: VectorClock, b: VectorClock): boolean {
    let atLeastOnce = false;
    for (const [nodeId, timeA] of Object.entries(a)) {
      const timeB = b[nodeId] ?? 0;
      if (timeA > timeB) return false;
      if (timeA < timeB) atLeastOnce = true;
    }
    return atLeastOnce;
  }

  /**
   * Check if clocks are concurrent
   */
  concurrent(a: VectorClock, b: VectorClock): boolean {
    return !this.happensBefore(a, b) && !this.happensBefore(b, a);
  }
}

/**
 * OR-Set (Observed-Remove Set) implementation
 * Add-wins semantics on concurrent operations
 */
export class ORSetImpl implements ORSet {
  type: 'OR-Set' = 'OR-Set';
  nodeId: string;
  vectorClock: VectorClock;
  lastUpdate: number = 0;
  elements: Map<string, Set<UniqueId>> = new Map();

  constructor(nodeId: string, vectorClock: VectorClock = {}) {
    this.nodeId = nodeId;
    this.vectorClock = vectorClock;
  }

  add(element: string, uniqueId: UniqueId): void {
    if (!this.elements.has(element)) {
      this.elements.set(element, new Set());
    }
    this.elements.get(element)!.add(uniqueId);
    this.lastUpdate = uniqueId.timestamp;
  }

  remove(element: string, uniqueIds: Set<UniqueId>): void {
    if (this.elements.has(element)) {
      const current = this.elements.get(element)!;
      uniqueIds.forEach(id => current.delete(id));
      if (current.size === 0) {
        this.elements.delete(element);
      }
    }
    this.lastUpdate = Date.now();
  }

  contains(element: string): boolean {
    return this.elements.has(element) && this.elements.get(element)!.size > 0;
  }

  merge(other: ORSet): void {
    for (const [element, otherIds] of other.elements) {
      if (!this.elements.has(element)) {
        this.elements.set(element, new Set(otherIds));
      } else {
        otherIds.forEach(id => this.elements.get(element)!.add(id));
      }
    }
    this.vectorClock = mergeVectorClocks(this.vectorClock, other.vectorClock);
  }

  toArray(): string[] {
    const result: string[] = [];
    for (const [element, ids] of this.elements) {
      if (ids.size > 0) {
        result.push(element);
      }
    }
    return result;
  }
}

/**
 * Counter CRDT implementation
 */
export class CounterImpl implements Counter {
  type: 'Counter' = 'Counter';
  nodeId: string;
  vectorClock: VectorClock;
  lastUpdate: number = 0;
  increments: Map<string, number> = new Map();
  decrements: Map<string, number> = new Map();

  constructor(nodeId: string, vectorClock: VectorClock = {}) {
    this.nodeId = nodeId;
    this.vectorClock = vectorClock;
  }

  increment(amount: number = 1): void {
    const current = this.increments.get(this.nodeId) ?? 0;
    this.increments.set(this.nodeId, current + amount);
    this.lastUpdate = Date.now();
  }

  decrement(amount: number = 1): void {
    const current = this.decrements.get(this.nodeId) ?? 0;
    this.decrements.set(this.nodeId, current + amount);
    this.lastUpdate = Date.now();
  }

  value(): number {
    let result = 0;
    for (const [_, v] of this.increments) result += v;
    for (const [_, v] of this.decrements) result -= v;
    return result;
  }

  merge(other: Counter): void {
    for (const [nodeId, val] of other.increments) {
      const current = this.increments.get(nodeId) ?? 0;
      this.increments.set(nodeId, Math.max(current, val));
    }
    for (const [nodeId, val] of other.decrements) {
      const current = this.decrements.get(nodeId) ?? 0;
      this.decrements.set(nodeId, Math.max(current, val));
    }
    this.vectorClock = mergeVectorClocks(this.vectorClock, other.vectorClock);
  }
}

/**
 * Register CRDT (Last-Write-Wins)
 */
export class RegisterImpl<T> implements Register<T> {
  type: 'Register' = 'Register';
  nodeId: string;
  vectorClock: VectorClock;
  value: T;
  timestamp: number;

  constructor(nodeId: string, value: T, timestamp: number = Date.now(), vectorClock: VectorClock = {}) {
    this.nodeId = nodeId;
    this.value = value;
    this.timestamp = timestamp;
    this.vectorClock = vectorClock;
  }

  set(newValue: T): void {
    this.value = newValue;
    this.timestamp = Date.now();
  }

  merge(other: Register<T>): void {
    if (other.timestamp > this.timestamp) {
      this.value = other.value;
      this.timestamp = other.timestamp;
    }
    this.vectorClock = mergeVectorClocks(this.vectorClock, other.vectorClock);
  }
}

/**
 * Merge two vector clocks (take maximum for each node)
 */
export function mergeVectorClocks(a: VectorClock, b: VectorClock): VectorClock {
  const result: VectorClock = { ...a };
  for (const [nodeId, timestamp] of Object.entries(b)) {
    result[nodeId] = Math.max(result[nodeId] ?? 0, timestamp);
  }
  return result;
}

/**
 * Serialize CRDT for replication
 */
export function serializeCRDT(crdt: CRDTValue): string {
  if (crdt === null) return JSON.stringify(null);

  switch (crdt.type) {
    case 'OR-Set': {
      const orset = crdt as ORSet;
      const data = {
        type: 'OR-Set',
        elements: Array.from(orset.elements).map(([elem, ids]) => [
          elem,
          Array.from(ids),
        ]),
        vectorClock: orset.vectorClock,
      };
      return JSON.stringify(data);
    }
    case 'Counter': {
      const counter = crdt as Counter;
      const data = {
        type: 'Counter',
        increments: Array.from(counter.increments),
        decrements: Array.from(counter.decrements),
        vectorClock: counter.vectorClock,
      };
      return JSON.stringify(data);
    }
    case 'Register': {
      const register = crdt as Register<any>;
      return JSON.stringify({
        type: 'Register',
        value: register.value,
        timestamp: register.timestamp,
        vectorClock: register.vectorClock,
      });
    }
    default:
      return JSON.stringify(crdt);
  }
}

/**
 * Deserialize CRDT from replication
 */
export function deserializeCRDT(data: string, nodeId: string): CRDTValue {
  const parsed = JSON.parse(data);

  if (parsed === null) return null;

  switch (parsed.type) {
    case 'OR-Set': {
      const orset = new ORSetImpl(nodeId, parsed.vectorClock);
      for (const [elem, ids] of parsed.elements) {
        orset.elements.set(elem, new Set(ids));
      }
      return orset;
    }
    case 'Counter': {
      const counter = new CounterImpl(nodeId, parsed.vectorClock);
      counter.increments = new Map(parsed.increments);
      counter.decrements = new Map(parsed.decrements);
      return counter;
    }
    case 'Register': {
      return new RegisterImpl(nodeId, parsed.value, parsed.timestamp, parsed.vectorClock);
    }
    default:
      return parsed as CRDTValue;
  }
}
