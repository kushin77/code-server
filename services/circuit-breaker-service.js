/**
 * Circuit Breaker Service for Tier 2 Resilience
 * 
 * 3-state pattern: CLOSED → OPEN → HALF_OPEN → CLOSED
 * Prevents cascading failures under high load
 * Gracefully degrades when system is overwhelmed
 * 
 * IaC Principles:
 * - Idempotent: State machine design, can safely reinitialize
 * - Immutable: Configuration passed at construction
 * - Version-controlled: All fail conditions and thresholds defined
 */

class CircuitBreaker {
    /**
     * Circuit breaker states
     */
    static STATE = {
        CLOSED: 'CLOSED',      // Normal: requests pass through
        OPEN: 'OPEN',          // Failing: requests rejected immediately
        HALF_OPEN: 'HALF_OPEN' // Testing: selective requests allowed
    };
    
    constructor(options = {}) {
        // Configuration
        this.name = options.name || 'circuit-breaker';
        this.failureThreshold = options.failureThreshold || 0.5;     // 50% failure rate
        this.resetTimeout = options.resetTimeout || 60000;           // 60 seconds to retry
        this.windowSize = options.windowSize || 30000;               // 30 second window
        this.maxHalfOpenRequests = options.maxHalfOpenRequests || 3; // Allow 3 test requests
        
        // State
        this.state = CircuitBreaker.STATE.CLOSED;
        this.failures = 0;
        this.successes = 0;
        this.consecutiveHalfOpenSuccesses = 0;
        this.lastFailureTime = null;
        this.nextAttemptTime = null;
        
        // Metrics
        this.metrics = {
            name: this.name,
            totalAttempts: 0,
            totalFailures: 0,
            totalSuccesses: 0,
            stateTransitions: [],
            failureRate: 0,
            avgResponseTime: 0,
            createdAt: new Date().toISOString()
        };
        
        // Request window tracking (for failure rate calculation)
        this.requestWindow = [];
    }
    
    /**
     * Execute function through circuit breaker
     * @param {Function} fn - Async function to execute
     * @param {Object} context - Context/metadata for the request
     * @returns {Promise} Result or circuit breaker error
     */
    async execute(fn, context = {}) {
        const startTime = Date.now();
        this.metrics.totalAttempts++;
        
        // Check circuit state
        if (this.state === CircuitBreaker.STATE.OPEN) {
            const timeSinceOpen = Date.now() - this.lastFailureTime;
            
            if (timeSinceOpen < this.resetTimeout) {
                // Still in timeout, reject immediately
                this.metrics.totalFailures++;
                throw new Error(
                    `Circuit breaker is OPEN for "${this.name}". ` +
                    `Retry after ${this.resetTimeout - timeSinceOpen}ms`
                );
            }
            
            // Time to transition to HALF_OPEN
            this._transitionTo(CircuitBreaker.STATE.HALF_OPEN);
        }
        
        // In HALF_OPEN state, limit concurrent requests
        if (this.state === CircuitBreaker.STATE.HALF_OPEN &&
            this.consecutiveHalfOpenSuccesses >= this.maxHalfOpenRequests) {
            throw new Error(
                `Circuit breaker "${this.name}" testing limit reached. ` +
                `Maximum ${this.maxHalfOpenRequests} test requests allowed in HALF_OPEN`
            );
        }
        
        // Execute the function
        try {
            const result = await fn();
            this._recordSuccess(Date.now() - startTime);
            return result;
        } catch (error) {
            this._recordFailure(Date.now() - startTime);
            throw error;
        }
    }
    
    /**
     * Record successful request
     */
    _recordSuccess(responseTime) {
        this.successes++;
        this.metrics.totalSuccesses++;
        this.metrics.avgResponseTime = (this.metrics.avgResponseTime || 0) * 0.9 + responseTime * 0.1;
        this.requestWindow.push({ timestamp: Date.now(), success: true });
        
        if (this.state === CircuitBreaker.STATE.HALF_OPEN) {
            this.consecutiveHalfOpenSuccesses++;
            
            // If enough successes, transition back to CLOSED
            if (this.consecutiveHalfOpenSuccesses >= this.maxHalfOpenRequests) {
                this._transitionTo(CircuitBreaker.STATE.CLOSED);
                this.failures = 0;
                this.successes = 0;
                this.consecutiveHalfOpenSuccesses = 0;
            }
        }
        
        this._updateFailureRate();
    }
    
    /**
     * Record failed request
     */
    _recordFailure(responseTime) {
        this.failures++;
        this.lastFailureTime = Date.now();
        this.metrics.totalFailures++;
        this.requestWindow.push({ timestamp: Date.now(), success: false });
        
        this._updateFailureRate();
        
        // Check if threshold exceeded
        if (this._getFailureRate() > this.failureThreshold) {
            if (this.state !== CircuitBreaker.STATE.OPEN) {
                this._transitionTo(CircuitBreaker.STATE.OPEN);
                this.nextAttemptTime = Date.now() + this.resetTimeout;
            }
        }
    }
    
    /**
     * Update failure rate based on request window
     */
    _updateFailureRate() {
        // Clean up old requests outside window
        const cutoff = Date.now() - this.windowSize;
        this.requestWindow = this.requestWindow.filter(r => r.timestamp > cutoff);
        
        // Calculate rate
        const failureCount = this.requestWindow.filter(r => !r.success).length;
        this.metrics.failureRate = 
            this.requestWindow.length > 0 ? failureCount / this.requestWindow.length : 0;
    }
    
    /**
     * Get current failure rate
     */
    _getFailureRate() {
        const cutoff = Date.now() - this.windowSize;
        const windowRequests = this.requestWindow.filter(r => r.timestamp > cutoff);
        
        if (windowRequests.length === 0) return 0;
        
        const failureCount = windowRequests.filter(r => !r.success).length;
        return failureCount / windowRequests.length;
    }
    
    /**
     * Transition to new state
     */
    _transitionTo(newState) {
        if (this.state !== newState) {
            this.metrics.stateTransitions.push({
                from: this.state,
                to: newState,
                timestamp: new Date().toISOString()
            });
            this.state = newState;
        }
    }
    
    /**
     * Get current state and metrics
     */
    getStatus() {
        return {
            name: this.name,
            state: this.state,
            metrics: this.metrics,
            failureRate: this.metrics.failureRate,
            windowSize: this.windowSize,
            threshold: this.failureThreshold,
            timestamp: new Date().toISOString()
        };
    }
    
    /**
     * Reset circuit breaker
     */
    reset() {
        this.state = CircuitBreaker.STATE.CLOSED;
        this.failures = 0;
        this.successes = 0;
        this.consecutiveHalfOpenSuccesses = 0;
        this.lastFailureTime = null;
        this.nextAttemptTime = null;
        this.requestWindow = [];
    }
}

module.exports = CircuitBreaker;
