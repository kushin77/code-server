/**
 * Prometheus Metrics Exporter for Tier 2 Performance Monitoring
 * 
 * Exports metrics in Prometheus text format
 * Integrates with batching service, circuit breaker, and batch endpoint
 * 
 * Metrics:
 * - tier2_batch_requests_total (counter)
 * - tier2_batch_latency_ms (histogram)
 * - tier2_circuit_breaker_state (gauge)
 * - tier2_circuit_breaker_failures (counter)
 * - tier2_redis_hit_rate (gauge)
 * 
 * Endpoint: GET /metrics
 */

class MetricsExporter {
    constructor(options = {}) {
        this.namespace = options.namespace || 'tier2';
        this.prefix = `${this.namespace}_`;
        
        this.counters = {};
        this.gauges = {};
        this.histograms = {};
        
        this.startTime = Date.now();
        this.createdAt = new Date().toISOString();
        
        this._initializeMetrics();
    }
    
    /**
     * Initialize default metrics
     */
    _initializeMetrics() {
        // Counters
        this.counters = {
            [`${this.prefix}batch_requests_total`]: 0,
            [`${this.prefix}batch_requests_success`]: 0,
            [`${this.prefix}batch_requests_failed`]: 0,
            [`${this.prefix}circuit_breaker_open`]: 0,
            [`${this.prefix}circuit_breaker_closed`]: 0,
            [`${this.prefix}circuit_breaker_half_open`]: 0,
            [`${this.prefix}redis_hits`]: 0,
            [`${this.prefix}redis_misses`]: 0
        };
        
        // Gauges
        this.gauges = {
            [`${this.prefix}batch_queue_size`]: 0,
            [`${this.prefix}circuit_breaker_failure_rate`]: 0,
            [`${this.prefix}active_connections`]: 0,
            [`${this.prefix}redis_memory_bytes`]: 0,
            [`${this.prefix}uptime_seconds`]: 0
        };
        
        // Histograms (bucketed)
        this.histograms = {
            [`${this.prefix}batch_latency_ms`]: {
                buckets: [10, 25, 50, 100, 250, 500, 1000],
                observations: []
            },
            [`${this.prefix}request_latency_ms`]: {
                buckets: [5, 10, 25, 50, 100, 250],
                observations: []
            }
        };
    }
    
    /**
     * Increment counter
     */
    incrementCounter(name, value = 1, labels = {}) {
        const fullName = this._formatMetricName(name);
        if (!this.counters.hasOwnProperty(fullName)) {
            this.counters[fullName] = 0;
        }
        this.counters[fullName] += value;
    }
    
    /**
     * Set gauge value
     */
    setGauge(name, value, labels = {}) {
        const fullName = this._formatMetricName(name);
        this.gauges[fullName] = value;
    }
    
    /**
     * Record histogram observation
     */
    recordHistogram(name, value, labels = {}) {
        const fullName = this._formatMetricName(name);
        if (this.histograms.hasOwnProperty(fullName)) {
            this.histograms[fullName].observations.push(value);
            // Keep only last 1000 observations
            if (this.histograms[fullName].observations.length > 1000) {
                this.histograms[fullName].observations.shift();
            }
        }
    }
    
    /**
     * Format metric name with prefix
     */
    _formatMetricName(name) {
        if (name.startsWith(this.prefix)) {
            return name;
        }
        return `${this.prefix}${name}`;
    }
    
    /**
     * Export metrics in Prometheus text format
     */
    export() {
        const lines = [];
        
        // HELP sections
        lines.push('# HELP tier2_batch_requests_total Total batch requests processed');
        lines.push('# TYPE tier2_batch_requests_total counter');
        
        // Counters
        Object.entries(this.counters).forEach(([name, value]) => {
            lines.push(`${name} ${value}`);
        });
        
        lines.push('');
        lines.push('# HELP tier2_batch_queue_size Current size of batch queue');
        lines.push('# TYPE tier2_batch_queue_size gauge');
        
        // Gauges
        Object.entries(this.gauges).forEach(([name, value]) => {
            lines.push(`${name} ${value}`);
        });
        
        lines.push('');
        lines.push('# HELP tier2_batch_latency_ms Batch processing latency');
        lines.push('# TYPE tier2_batch_latency_ms histogram');
        
        // Histograms
        Object.entries(this.histograms).forEach(([name, hist]) => {
            const buckets = hist.buckets || [];
            const observations = hist.observations || [];
            
            // Calculate bucket counts
            buckets.forEach(bucket => {
                const count = observations.filter(o => o <= bucket).length;
                lines.push(`${name}_bucket{le="${bucket}"} ${count}`);
            });
            
            lines.push(`${name}_bucket{le="+Inf"} ${observations.length}`);
            lines.push(`${name}_sum ${observations.reduce((a, b) => a + b, 0)}`);
            lines.push(`${name}_count ${observations.length}`);
        });
        
        // System metrics
        lines.push('');
        lines.push('# HELP tier2_uptime_seconds Uptime in seconds');
        lines.push('# TYPE tier2_uptime_seconds gauge');
        const uptime = Math.floor((Date.now() - this.startTime) / 1000);
        lines.push(`${this.prefix}uptime_seconds ${uptime}`);
        
        return lines.join('\n') + '\n';
    }
    
    /**
     * Export as JSON (for debugging)
     */
    exportJSON() {
        return {
            timestamp: new Date().toISOString(),
            uptime: Math.floor((Date.now() - this.startTime) / 1000),
            counters: this.counters,
            gauges: this.gauges,
            histograms: Object.entries(this.histograms).reduce((acc, [name, hist]) => {
                acc[name] = {
                    buckets: hist.buckets,
                    count: hist.observations.length,
                    sum: hist.observations.reduce((a, b) => a + b, 0),
                    min: hist.observations.length > 0 ? Math.min(...hist.observations) : 0,
                    max: hist.observations.length > 0 ? Math.max(...hist.observations) : 0,
                    avg: hist.observations.length > 0 
                        ? Math.round(hist.observations.reduce((a, b) => a + b, 0) / hist.observations.length)
                        : 0
                };
                return acc;
            }, {})
        };
    }
}

module.exports = MetricsExporter;
