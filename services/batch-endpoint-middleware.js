/**
 * Batch Endpoint Middleware for Express/Fastify
 *
 * POST /api/batch - Accept up to 10 requests per batch
 * Responses maintain order and include per-request status
 *
 * Request format:
 * {
 *   "requests": [
 *     { "method": "GET", "path": "/api/users/1", "headers": { ... }, "body": ... },
 *     { "method": "POST", "path": "/api/posts", "headers": { ... }, "body": { ... } }
 *   ]
 * }
 *
 * Response format:
 * {
 *   "status": 207,  // Multi-status
 *   "responses": [
 *     { "status": 200, "body": { ... } },
 *     { "status": 201, "body": { ... } }
 *   ],
 *   "metrics": { "batchSize": 2, "latency": 125 }
 * }
 */

const BatchingService = require('./batching-service');
const CircuitBreaker = require('./circuit-breaker-service');

class BatchEndpointMiddleware {
    constructor(app, options = {}) {
        this.app = app;
        this.batchingService = new BatchingService(options.batching);
        this.circuitBreaker = new CircuitBreaker(options.circuitBreaker);
        this.maxBatchSize = options.maxBatchSize || 10;
        this.requestTimeout = options.requestTimeout || 30000;

        this.metrics = {
            totalBatches: 0,
            totalRequests: 0,
            successfulBatches: 0,
            failedBatches: 0,
            avgLatency: 0,
            createdAt: new Date().toISOString()
        };
    }

    /**
     * Register batch endpoint (Express example)
     */
    registerEndpoint() {
        this.app.post('/api/batch', async (req, res) => {
            await this.handleBatch(req, res);
        });
    }

    /**
     * Handle batch request
     */
    async handleBatch(req, res) {
        const startTime = Date.now();

        try {
            // Validate request
            const { requests } = req.body;

            if (!Array.isArray(requests)) {
                return res.status(400).json({
                    error: 'Invalid request: requests must be an array',
                    received: typeof requests
                });
            }

            if (requests.length === 0) {
                return res.status(400).json({
                    error: 'Invalid request: requests array cannot be empty'
                });
            }

            if (requests.length > this.maxBatchSize) {
                return res.status(400).json({
                    error: `Batch size exceeds maximum of ${this.maxBatchSize}`,
                    requested: requests.length
                });
            }

            this.metrics.totalBatches++;
            this.metrics.totalRequests += requests.length;

            // Execute through circuit breaker
            const responses = await this.circuitBreaker.execute(async () => {
                return await Promise.allSettled(
                    requests.map(req => this._executeRequest(req))
                );
            });

            // Process results
            const results = responses.map((result, idx) => {
                if (result.status === 'fulfilled') {
                    this.metrics.successfulBatches++;
                    return {
                        index: idx,
                        status: result.value.status || 200,
                        body: result.value.body || result.value,
                        headers: result.value.headers || {}
                    };
                } else {
                    this.metrics.failedBatches++;
                    return {
                        index: idx,
                        status: 500,
                        error: result.reason.message,
                        body: null
                    };
                }
            });

            // Update metrics
            const latency = Date.now() - startTime;
            this.metrics.avgLatency = (this.metrics.avgLatency || 0) * 0.8 + latency * 0.2;

            // Return 207 Multi-Status response
            res.status(207).json({
                status: 207,
                responses: results,
                metrics: {
                    batchSize: requests.length,
                    latency,
                    circuitBreakerStatus: this.circuitBreaker.state
                }
            });

        } catch (error) {
            res.status(500).json({
                error: 'Batch processing failed',
                message: error.message,
                timestamp: new Date().toISOString()
            });
        }
    }

    /**
     * Execute individual request in batch
     * @private
     */
    async _executeRequest(reqSpec) {
        return new Promise((resolve, reject) => {
            // Simulate HTTP request execution
            // In production, this would route through actual HTTP handlers
            setTimeout(() => {
                resolve({
                    status: 200,
                    body: {
                        requestPath: reqSpec.path,
                        method: reqSpec.method,
                        processed: true,
                        timestamp: new Date().toISOString()
                    },
                    headers: {
                        'content-type': 'application/json',
                        'x-processed-by': 'batch-endpoint'
                    }
                });
            }, Math.random() * 50);
        });
    }

    /**
     * Get batch processing metrics
     */
    getMetrics() {
        return {
            ...this.metrics,
            batchingService: this.batchingService.getMetrics(),
            circuitBreaker: this.circuitBreaker.getStatus(),
            timestamp: new Date().toISOString()
        };
    }
}

module.exports = BatchEndpointMiddleware;
