/**
 * Batching Service for Tier 2 Performance Enhancement
 * 
 * Allows up to 10 requests per batch to reduce overhead
 * Maintains order of responses to match request order
 * Handles per-request errors without failing entire batch
 * 
 * IaC Principles:
 * - Idempotent: Can safely handle duplicate instantiation
 * - Stateless between batches: No cross-batch state coupling
 * - Version-controlled: All configuration in code
 */

class BatchingService {
    constructor(options = {}) {
        this.maxRequests = options.maxRequests || 10;
        this.timeoutMs = options.timeoutMs || 30000;
        this.flushIntervalMs = options.flushIntervalMs || 100;
        
        this.queue = [];
        this.metrics = {
            totalBatches: 0,
            totalRequests: 0,
            successfulBatches: 0,
            failedBatches: 0,
            avgBatchSize: 0,
            avgLatency: 0,
            lastFlushTime: Date.now(),
            createdAt: new Date().toISOString()
        };
        
        // Auto-flush queue periodically
        this.flushInterval = setInterval(() => this._flushIfDue(), this.flushIntervalMs);
    }
    
    /**
     * Add request to batch
     * @param {Object} request - Request object
     * @param {Function} handler - Handler function to execute
     * @returns {Promise} Result promise
     */
    async addRequest(request, handler) {
        return new Promise((resolve, reject) => {
            this.queue.push({
                request,
                handler,
                resolve,
                reject,
                timestamp: Date.now()
            });
            
            // Auto-flush if batch is full
            if (this.queue.length >= this.maxRequests) {
                this._flush();
            }
        });
    }
    
    /**
     * Flush queue: execute all batched requests
     */
    async _flush() {
        if (this.queue.length === 0) return;
        
        const batch = this.queue.splice(0, this.maxRequests);
        const startTime = Date.now();
        
        this.metrics.totalBatches++;
        this.metrics.totalRequests += batch.length;
        
        try {
            // Execute all requests in parallel
            const results = await Promise.allSettled(
                batch.map(item => this._executeWithTimeout(item))
            );
            
            // Resolve/reject individual promises
            results.forEach((result, idx) => {
                if (result.status === 'fulfilled') {
                    batch[idx].resolve(result.value);
                    this.metrics.successfulBatches++;
                } else {
                    batch[idx].reject(result.reason);
                    this.metrics.failedBatches++;
                }
            });
            
            // Update metrics
            const latency = Date.now() - startTime;
            this.metrics.avgBatchSize = this.metrics.totalRequests / this.metrics.totalBatches;
            this.metrics.avgLatency = (this.metrics.avgLatency || 0) * 0.7 + latency * 0.3;
            this.metrics.lastFlushTime = Date.now();
            
        } catch (error) {
            batch.forEach(item => item.reject(error));
            this.metrics.failedBatches++;
        }
    }
    
    /**
     * Execute request with timeout
     */
    async _executeWithTimeout(item) {
        const timeoutPromise = new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Batch request timeout')), this.timeoutMs)
        );
        
        try {
            return await Promise.race([
                item.handler(item.request),
                timeoutPromise
            ]);
        } catch (error) {
            return {
                status: 500,
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }
    
    /**
     * Check if flush is due (time + queue size)
     */
    _flushIfDue() {
        const timeSinceLastFlush = Date.now() - this.metrics.lastFlushTime;
        if (this.queue.length > 0 && timeSinceLastFlush > this.flushIntervalMs) {
            this._flush();
        }
    }
    
    /**
     * Get metrics
     */
    getMetrics() {
        return {
            ...this.metrics,
            currentQueueSize: this.queue.length,
            timestamp: new Date().toISOString()
        };
    }
    
    /**
     * Graceful shutdown
     */
    async shutdown() {
        clearInterval(this.flushInterval);
        await this._flush(); // Final flush
        return this.metrics;
    }
}

module.exports = BatchingService;
