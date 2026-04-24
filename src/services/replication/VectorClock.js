/**
 * Phase 12.2: Vector Clock Implementation
 * Provides logical, causality-tracking timestamps for distributed systems
 * Ensures proper ordering of events across multiple replicas
 */
export class VectorClock {
    constructor(replicaId, initialClock) {
        this.replicaId = replicaId;
        this.clock = initialClock || { [replicaId]: 0 };
    }
    /**
     * Increment the local clock for the current replica
     */
    tick() {
        this.clock[this.replicaId] = (this.clock[this.replicaId] || 0) + 1;
    }
    /**
     * Get the current clock value
     */
    get() {
        return { ...this.clock };
    }
    /**
     * Update the clock with received event clock
     * Used when receiving messages to maintain causality
     */
    update(receivedClock) {
        // For each dimension in received clock
        for (const [replicaId, timestamp] of Object.entries(receivedClock)) {
            this.clock[replicaId] = Math.max(this.clock[replicaId] || 0, timestamp);
        }
        // Then increment our own clock
        this.tick();
    }
    /**
     * Determine if clock1 happened before clock2
     */
    static happensBefore(clock1, clock2) {
        let hasStrictlyLess = false;
        const allKeys = new Set([
            ...Object.keys(clock1),
            ...Object.keys(clock2),
        ]);
        for (const key of allKeys) {
            const val1 = clock1[key] || 0;
            const val2 = clock2[key] || 0;
            if (val1 > val2)
                return false; // clock1 is not less than clock2
            if (val1 < val2)
                hasStrictlyLess = true;
        }
        return hasStrictlyLess;
    }
    /**
     * Determine if clocks are concurrent (neither happened before the other)
     */
    static isConcurrent(clock1, clock2) {
        const hb1Before2 = VectorClock.happensBefore(clock1, clock2);
        const hb2Before1 = VectorClock.happensBefore(clock2, clock1);
        return !hb1Before2 && !hb2Before1;
    }
    /**
     * Determine if clocks are equal
     */
    static areEqual(clock1, clock2) {
        const allKeys = new Set([
            ...Object.keys(clock1),
            ...Object.keys(clock2),
        ]);
        for (const key of allKeys) {
            if ((clock1[key] || 0) !== (clock2[key] || 0)) {
                return false;
            }
        }
        return true;
    }
    /**
     * Clone a vector clock
     */
    static clone(clock) {
        return { ...clock };
    }
    /**
     * Convert to JSON string
     */
    toString() {
        return JSON.stringify(this.clock);
    }
}
//# sourceMappingURL=VectorClock.js.map