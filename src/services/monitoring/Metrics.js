export class Metrics {
    constructor(namespace) {
        this.namespace = namespace;
        this.counters = new Map();
        this.gauges = new Map();
        this.timings = new Map();
    }
    increment(name, value = 1) {
        const key = this.key(name);
        this.counters.set(key, (this.counters.get(key) || 0) + value);
    }
    gauge(name, value) {
        this.gauges.set(this.key(name), value);
    }
    timing(name, value) {
        this.timings.set(this.key(name), value);
    }
    getMetrics() {
        return {
            counters: Object.fromEntries(this.counters.entries()),
            gauges: Object.fromEntries(this.gauges.entries()),
            timings: Object.fromEntries(this.timings.entries()),
        };
    }
    key(name) {
        return `${this.namespace}.${name}`;
    }
}
export default Metrics;
//# sourceMappingURL=Metrics.js.map