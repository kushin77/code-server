type MetricValue = number;

export class Metrics {
  private counters = new Map<string, MetricValue>();
  private gauges = new Map<string, MetricValue>();
  private timings = new Map<string, MetricValue>();

  constructor(private readonly namespace: string) {}

  increment(name: string, value: number = 1): void {
    const key = this.key(name);
    this.counters.set(key, (this.counters.get(key) || 0) + value);
  }

  gauge(name: string, value: number): void {
    this.gauges.set(this.key(name), value);
  }

  timing(name: string, value: number): void {
    this.timings.set(this.key(name), value);
  }

  getMetrics(): Record<string, Record<string, number>> {
    return {
      counters: Object.fromEntries(this.counters.entries()),
      gauges: Object.fromEntries(this.gauges.entries()),
      timings: Object.fromEntries(this.timings.entries()),
    };
  }

  private key(name: string): string {
    return `${this.namespace}.${name}`;
  }
}

export default Metrics;