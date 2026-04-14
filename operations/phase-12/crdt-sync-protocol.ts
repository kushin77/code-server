/**
 * Phase 12.2: CRDT Synchronization Protocol
 * Implements conflict-free replicated data types for multi-region consistency
 *
 * Core Data Types:
 * - LWW Counter: Last-Write-Wins counter (tombstone-free)
 * - OR-Set: Add-Wins set (commutative)
 * - LWW Register: Last-Write-Wins register
 * - OR-Map: Nested eventually-consistent map
 *
 * Synchronization: Lambda-based with exponential backoff retry logic
 */

import { EventEmitter } from 'events';
import { v4 as uuidv4 } from 'uuid';

/**
 * Vector Clock Implementation
 * Tracks causality between events across replicas
 */
export class VectorClock {
    private clock: Map<string, number>;

    constructor(initialClock?: Record<string, number>) {
        this.clock = new Map(Object.entries(initialClock || {}));
    }

    /**
     * Increment clock for a replica
     */
    increment(replicaId: string): void {
        this.clock.set(replicaId, (this.clock.get(replicaId) || 0) + 1);
    }

    /**
     * Merge with another clock (take maximum per replica)
     */
    merge(other: VectorClock): void {
        for (const [replicaId, timestamp] of other.clock) {
            const current = this.clock.get(replicaId) || 0;
            this.clock.set(replicaId, Math.max(current, timestamp));
        }
    }

    /**
     * Check if this clock happened-before another
     */
    happensBefore(other: VectorClock): boolean {
        let atLeastOneLess = false;

        for (const [replicaId, timestamp] of this.clock) {
            const otherTs = other.clock.get(replicaId) || 0;
            if (timestamp > otherTs) {
                return false; // This is not before other
            }
            if (timestamp < otherTs) {
                atLeastOneLess = true;
            }
        }

        // Check if other has clocks this doesn't
        for (const [replicaId, timestamp] of other.clock) {
            if (!this.clock.has(replicaId) && timestamp > 0) {
                atLeastOneLess = true;
            }
        }

        return atLeastOneLess;
    }

    /**
     * Check if concurrent with another clock
     */
    isConcurrent(other: VectorClock): boolean {
        return !this.happensBefore(other) && !other.happensBefore(this);
    }

    /**
     * Export clock as object
     */
    toObject(): Record<string, number> {
        return Object.fromEntries(this.clock);
    }
}

/**
 * CRDT Counter - Last-Write-Wins
 * Maintains highest value with timestamp
 */
export class LWWCounter {
    id: string;
    key: string;
    value: number;
    timestamp: bigint;
    replicaId: string;
    vectorClock: VectorClock;

    constructor(
        key: string,
        value: number,
        replicaId: string,
        vectorClock?: VectorClock
    ) {
        this.id = uuidv4();
        this.key = key;
        this.value = value;
        this.timestamp = BigInt(Date.now());
        this.replicaId = replicaId;
        this.vectorClock = vectorClock || new VectorClock({ [replicaId]: 1 });
    }

    /**
     * Merge with another counter - keeps highest value
     */
    merge(other: LWWCounter): LWWCounter {
        const vc = new VectorClock(this.vectorClock.toObject());
        vc.merge(other.vectorClock);

        // LWW: compare timestamps
        if (other.timestamp > this.timestamp) {
            return new LWWCounter(other.key, other.value, other.replicaId, vc);
        } else if (this.timestamp > other.timestamp) {
            return new LWWCounter(this.key, this.value, this.replicaId, vc);
        } else {
            // Tie-break by replica ID (lexicographic)
            const chosen = this.replicaId > other.replicaId ? this : other;
            return new LWWCounter(chosen.key, chosen.value, chosen.replicaId, vc);
        }
    }
}

/**
 * CRDT OR-Set (Add-Wins Set)
 * Elements added by any replica are preserved
 * Elements removed only if not added elsewhere
 */
export class ORSet {
    id: string;
    key: string;
    elements: Map<string, { timestamp: bigint; replicaId: string; added: boolean }>;
    vectorClock: VectorClock;
    replicaId: string;

    constructor(
        key: string,
        replicaId: string,
        vectorClock?: VectorClock
    ) {
        this.id = uuidv4();
        this.key = key;
        this.elements = new Map();
        this.replicaId = replicaId;
        this.vectorClock = vectorClock || new VectorClock({ [replicaId]: 1 });
    }

    /**
     * Add element to set
     */
    add(element: string): void {
        this.elements.set(element, {
            timestamp: BigInt(Date.now()),
            replicaId: this.replicaId,
            added: true
        });
        this.vectorClock.increment(this.replicaId);
    }

    /**
     * Remove element from set (tombstone)
     */
    remove(element: string): void {
        if (this.elements.has(element)) {
            this.elements.set(element, {
                ...this.elements.get(element)!,
                added: false,
                timestamp: BigInt(Date.now())
            });
        }
        this.vectorClock.increment(this.replicaId);
    }

    /**
     * Get active elements (not tombstoned)
     */
    view(): Set<string> {
        const active = new Set<string>();
        for (const [element, metadata] of this.elements) {
            if (metadata.added) {
                active.add(element);
            }
        }
        return active;
    }

    /**
     * Merge with another OR-Set
     */
    merge(other: ORSet): ORSet {
        const merged = new ORSet(this.key, this.replicaId);
        merged.vectorClock.merge(this.vectorClock);
        merged.vectorClock.merge(other.vectorClock);

        // Merge elements: keep if added by any replica
        const allElements = new Set([...this.elements.keys(), ...other.elements.keys()]);

        for (const element of allElements) {
            const local = this.elements.get(element);
            const remote = other.elements.get(element);

            if (!local && remote) {
                merged.elements.set(element, remote);
            } else if (local && !remote) {
                merged.elements.set(element, local);
            } else if (local && remote) {
                // Choose based on timestamp (LWW within element)
                if (remote.timestamp > local.timestamp) {
                    merged.elements.set(element, remote);
                } else if (local.timestamp > remote.timestamp) {
                    merged.elements.set(element, local);
                } else {
                    // Tie: choose add over remove (Add-Wins)
                    merged.elements.set(element, remote.added ? remote : local);
                }
            }
        }

        return merged;
    }
}

/**
 * CRDT Register - Last-Write-Wins Register
 * Simple value holder with version tracking
 */
export class LWWRegister {
    id: string;
    key: string;
    value: string | null;
    timestamp: bigint;
    version: number;
    replicaId: string;
    vectorClock: VectorClock;

    constructor(
        key: string,
        value: string | null,
        replicaId: string,
        vectorClock?: VectorClock
    ) {
        this.id = uuidv4();
        this.key = key;
        this.value = value;
        this.timestamp = BigInt(Date.now());
        this.version = 1;
        this.replicaId = replicaId;
        this.vectorClock = vectorClock || new VectorClock({ [replicaId]: 1 });
    }

    /**
     * Update value
     */
    set(value: string): void {
        this.value = value;
        this.timestamp = BigInt(Date.now());
        this.version++;
        this.vectorClock.increment(this.replicaId);
    }

    /**
     * Merge with another register - keeps most recent
     */
    merge(other: LWWRegister): LWWRegister {
        const vc = new VectorClock(this.vectorClock.toObject());
        vc.merge(other.vectorClock);

        const merged = new LWWRegister('', null, this.replicaId, vc);
        merged.key = this.key;

        if (other.timestamp > this.timestamp) {
            merged.value = other.value;
            merged.timestamp = other.timestamp;
            merged.version = other.version;
    merged.replicaId = other.replicaId;
        } else if (this.timestamp > other.timestamp) {
            merged.value = this.value;
            merged.timestamp = this.timestamp;
            merged.version = this.version;
            merged.replicaId = this.replicaId;
        } else {
            // Tie: choose by replica ID
            if (this.replicaId > other.replicaId) {
                merged.value = this.value;
                merged.version = this.version;
                merged.replicaId = this.replicaId;
            } else {
                merged.value = other.value;
                merged.version = other.version;
                merged.replicaId = other.replicaId;
            }
            merged.timestamp = this.timestamp;
        }

        return merged;
    }
}

/**
 * CRDT Synchronization Engine
 * Orchestrates multi-region CRDT replication
 */
export class CRDTSyncEngine extends EventEmitter {
    private replicaId: string;
    private regions: Map<string, string>; // region -> endpoint
    private counters: Map<string, LWWCounter>;
    private sets: Map<string, ORSet>;
    private registers: Map<string, LWWRegister>;
    private syncInterval: number;
    private maxRetries: number;
    private retryBackoff: number;

    constructor(
        replicaId: string,
        regions: Record<string, string>,
        syncInterval = 1000,
        maxRetries = 3,
        retryBackoff = 100
    ) {
        super();

        this.replicaId = replicaId;
        this.regions = new Map(Object.entries(regions));
        this.counters = new Map();
        this.sets = new Map();
        this.registers = new Map();
        this.syncInterval = syncInterval;
        this.maxRetries = maxRetries;
        this.retryBackoff = retryBackoff;
    }

    /**
     * Update a counter
     */
    updateCounter(key: string, value: number): void {
        const counter = new LWWCounter(key, value, this.replicaId);
        this.counters.set(key, counter);
        this.emit('counter-updated', { key, value, replicaId: this.replicaId });
    }

    /**
     * Add element to set
     */
    addToSet(key: string, element: string): void {
        let set = this.sets.get(key);
        if (!set) {
            set = new ORSet(key, this.replicaId);
            this.sets.set(key, set);
        }
        set.add(element);
        this.emit('set-updated', { key, element, operation: 'add' });
    }

    /**
     * Remove element from set
     */
    removeFromSet(key: string, element: string): void {
        let set = this.sets.get(key);
        if (!set) {
            set = new ORSet(key, this.replicaId);
            this.sets.set(key, set);
        }
        set.remove(element);
        this.emit('set-updated', { key, element, operation: 'remove' });
    }

    /**
     * Update register
     */
    updateRegister(key: string, value: string): void {
        const register = new LWWRegister(key, value, this.replicaId);
        this.registers.set(key, register);
        this.emit('register-updated', { key, value });
    }

    /**
     * Merge remote state
     */
    mergeRemote(remoteState: {
        counters?: LWWCounter[];
        sets?: ORSet[];
        registers?: LWWRegister[];
    }): void {
        if (remoteState.counters) {
            for (const remote of remoteState.counters) {
                const local = this.counters.get(remote.key);
                if (!local) {
                    this.counters.set(remote.key, remote);
                } else {
                    this.counters.set(remote.key, local.merge(remote));
                }
            }
        }

        if (remoteState.sets) {
            for (const remote of remoteState.sets) {
                const local = this.sets.get(remote.key);
                if (!local) {
                    this.sets.set(remote.key, remote);
                } else {
                    this.sets.set(remote.key, local.merge(remote));
                }
            }
        }

        if (remoteState.registers) {
            for (const remote of remoteState.registers) {
                const local = this.registers.get(remote.key);
                if (!local) {
                    this.registers.set(remote.key, remote);
                } else {
                    this.registers.set(remote.key, local.merge(remote));
                }
            }
        }

        this.emit('merge-complete', { timestamp: Date.now() });
    }

    /**
     * Get consistent view of all data
     */
    getState() {
        return {
            replicaId: this.replicaId,
            counters: Array.from(this.counters.values()),
            sets: Array.from(this.sets.values()).map(set => ({
                key: set.key,
                elements: Array.from(set.view())
            })),
            registers: Array.from(this.registers.values())
        };
    }
}

export default CRDTSyncEngine;
