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
 * Creates a unique ID for CRDT operations
 */
export class UniqueIdGenerator {
    constructor(nodeId = uuid.v4()) {
        this.counter = 0;
        this.nodeId = nodeId;
    }
    generate(timestamp = Date.now()) {
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
    constructor(nodeId) {
        this.clock = {};
        this.clock[nodeId] = 0;
    }
    increment(nodeId) {
        if (!(nodeId in this.clock)) {
            this.clock[nodeId] = 0;
        }
        this.clock[nodeId]++;
    }
    merge(other) {
        for (const [nodeId, timestamp] of Object.entries(other)) {
            if (!(nodeId in this.clock)) {
                this.clock[nodeId] = 0;
            }
            this.clock[nodeId] = Math.max(this.clock[nodeId], timestamp);
        }
    }
    getClock() {
        return { ...this.clock };
    }
    /**
     * Check if clock A happens before clock B
     */
    happensBefore(a, b) {
        let atLeastOnce = false;
        for (const [nodeId, timeA] of Object.entries(a)) {
            const timeB = b[nodeId] ?? 0;
            if (timeA > timeB)
                return false;
            if (timeA < timeB)
                atLeastOnce = true;
        }
        return atLeastOnce;
    }
    /**
     * Check if clocks are concurrent
     */
    concurrent(a, b) {
        return !this.happensBefore(a, b) && !this.happensBefore(b, a);
    }
}
/**
 * OR-Set (Observed-Remove Set) implementation
 * Add-wins semantics on concurrent operations
 */
export class ORSetImpl {
    constructor(nodeId, vectorClock = {}) {
        this.type = 'OR-Set';
        this.lastUpdate = 0;
        this.elements = new Map();
        this.nodeId = nodeId;
        this.vectorClock = vectorClock;
    }
    add(element, uniqueId) {
        if (!this.elements.has(element)) {
            this.elements.set(element, new Set());
        }
        this.elements.get(element).add(uniqueId);
        this.lastUpdate = uniqueId.timestamp;
    }
    remove(element, uniqueIds) {
        if (this.elements.has(element)) {
            const current = this.elements.get(element);
            uniqueIds.forEach(id => current.delete(id));
            if (current.size === 0) {
                this.elements.delete(element);
            }
        }
        this.lastUpdate = Date.now();
    }
    contains(element) {
        return this.elements.has(element) && this.elements.get(element).size > 0;
    }
    merge(other) {
        for (const [element, otherIds] of other.elements) {
            if (!this.elements.has(element)) {
                this.elements.set(element, new Set(otherIds));
            }
            else {
                otherIds.forEach(id => this.elements.get(element).add(id));
            }
        }
        this.vectorClock = mergeVectorClocks(this.vectorClock, other.vectorClock);
    }
    toArray() {
        const result = [];
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
export class CounterImpl {
    constructor(nodeId, vectorClock = {}) {
        this.type = 'Counter';
        this.lastUpdate = 0;
        this.increments = new Map();
        this.decrements = new Map();
        this.nodeId = nodeId;
        this.vectorClock = vectorClock;
    }
    increment(amount = 1) {
        const current = this.increments.get(this.nodeId) ?? 0;
        this.increments.set(this.nodeId, current + amount);
        this.lastUpdate = Date.now();
    }
    decrement(amount = 1) {
        const current = this.decrements.get(this.nodeId) ?? 0;
        this.decrements.set(this.nodeId, current + amount);
        this.lastUpdate = Date.now();
    }
    value() {
        let result = 0;
        for (const [_, v] of this.increments)
            result += v;
        for (const [_, v] of this.decrements)
            result -= v;
        return result;
    }
    merge(other) {
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
export class RegisterImpl {
    constructor(nodeId, value, timestamp = Date.now(), vectorClock = {}) {
        this.type = 'Register';
        this.nodeId = nodeId;
        this.value = value;
        this.timestamp = timestamp;
        this.vectorClock = vectorClock;
    }
    set(newValue) {
        this.value = newValue;
        this.timestamp = Date.now();
    }
    merge(other) {
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
export function mergeVectorClocks(a, b) {
    const result = { ...a };
    for (const [nodeId, timestamp] of Object.entries(b)) {
        result[nodeId] = Math.max(result[nodeId] ?? 0, timestamp);
    }
    return result;
}
/**
 * Serialize CRDT for replication
 */
export function serializeCRDT(crdt) {
    if (crdt === null)
        return JSON.stringify(null);
    switch (crdt.type) {
        case 'OR-Set': {
            const orset = crdt;
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
            const counter = crdt;
            const data = {
                type: 'Counter',
                increments: Array.from(counter.increments),
                decrements: Array.from(counter.decrements),
                vectorClock: counter.vectorClock,
            };
            return JSON.stringify(data);
        }
        case 'Register': {
            const register = crdt;
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
export function deserializeCRDT(data, nodeId) {
    const parsed = JSON.parse(data);
    if (parsed === null)
        return null;
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
            return parsed;
    }
}
//# sourceMappingURL=crdt-sync-protocol.js.map