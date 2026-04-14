// Phase 26-A: GraphQL Rate Limiting Middleware
// Implements intelligent rate limiting with tier-based quotas and token-bucket algorithm

const ratelimit = require('bottleneck');
const prometheus = require('prom-client');

// ════════════════════════════════════════════════════════════════════════════
// Prometheus Metrics
// ════════════════════════════════════════════════════════════════════════════

const rateLimitMetrics = {
  requests: new prometheus.Counter({
    name: 'api_requests_total',
    help: 'Total API requests',
    labelNames: ['method', 'path', 'status', 'tier'],
  }),
  
  requestsCurrent: new prometheus.Gauge({
    name: 'api_requests_current',
    help: 'Current requests against rate limit',
    labelNames: ['user_id', 'tier'],
  }),
  
  requestsRejected: new prometheus.Counter({
    name: 'api_requests_rejected_total',
    help: 'Rejected requests due to rate limiting',
    labelNames: ['tier', 'reason'],
  }),
  
  rateLimitViolations: new prometheus.Counter({
    name: 'api_rate_limit_violations_total',
    help: 'Rate limit violations detected',
    labelNames: ['tier'],
  }),
  
  headerCalculationDuration: new prometheus.Histogram({
    name: 'api_rate_limit_calculation_duration_seconds',
    help: 'Duration of rate limit header calculation',
    buckets: [0.00001, 0.0001, 0.001, 0.01, 0.1],
  }),
};

// ════════════════════════════════════════════════════════════════════════════
// Rate Limit Configuration (SINGLE SOURCE OF TRUTH)
// ════════════════════════════════════════════════════════════════════════════

const RATE_LIMIT_CONFIG = {
  free: {
    requestsPerMinute: 60,
    requestsPerDay: 10000,
    concurrentQueries: 5,
    maxPayloadKb: 1024,
    ttlSeconds: 300,
  },
  pro: {
    requestsPerMinute: 1000,
    requestsPerDay: 500000,
    concurrentQueries: 50,
    maxPayloadKb: 10240,
    ttlSeconds: 3600,
  },
  enterprise: {
    requestsPerMinute: 10000,
    requestsPerDay: 100000000,
    concurrentQueries: 500,
    maxPayloadKb: 102400,
    ttlSeconds: 86400,
  },
};

const RATE_LIMIT_HEADERS = {
  limit: 'X-RateLimit-Limit',
  remaining: 'X-RateLimit-Remaining',
  reset: 'X-RateLimit-Reset',
  retryAfter: 'Retry-After',
};

// ════════════════════════════════════════════════════════════════════════════
// Rate Limiter Class
// ════════════════════════════════════════════════════════════════════════════

class GraphQLRateLimiter {
  constructor(redisClient) {
    this.redis = redisClient;
    this.limiters = new Map(); // Per-user limiters using token-bucket algorithm
    this.metrics = rateLimitMetrics;
  }

  /**
   * Get rate limit configuration for user tier
   * @param {string} tier - User tier (free, pro, enterprise)
   * @returns {object} Rate limit config
   */
  getConfig(tier) {
    return RATE_LIMIT_CONFIG[tier] || RATE_LIMIT_CONFIG.free;
  }

  /**
   * Check if request is within rate limits
   * @param {string} userId - User ID
   * @param {string} tier - User tier
   * @param {number} queryComplexity - GraphQL query complexity score
   * @returns {Promise<object>} { allowed: boolean, remaining: number, reset: number }
   */
  async checkLimit(userId, tier, queryComplexity = 1) {
    const config = this.getConfig(tier);
    const startTime = Date.now();

    try {
      // Check concurrent queries limit
      const concurrentKey = `concurrent:${userId}`;
      const concurrent = await this.redis.incr(concurrentKey);
      
      if (concurrent > config.concurrentQueries) {
        await this.redis.decr(concurrentKey);
        this.metrics.requestsRejected.inc({ tier, reason: 'concurrent' });
        return {
          allowed: false,
          remaining: 0,
          reset: Math.ceil(Date.now() / 1000),
          reason: 'Too many concurrent queries',
        };
      }

      // Check minute-level rate limit (token bucket)
      const minuteKey = `ratelimit:minute:${userId}:${Math.floor(Date.now() / 60000)}`;
      const minuteRequests = await this.redis.incr(minuteKey);
      
      // Set expiration (skip redundant SET if count > 1)
      if (minuteRequests === 1) {
        await this.redis.expire(minuteKey, 60);
      }

      if (minuteRequests > config.requestsPerMinute) {
        this.metrics.requestsRejected.inc({ tier, reason: 'rate_limit_minute' });
        this.metrics.rateLimitViolations.inc({ tier });
        
        // Calculate reset time
        const resetTime = Math.ceil(Date.now() / 60000) * 60;
        return {
          allowed: false,
          remaining: 0,
          reset: resetTime,
          reason: 'Rate limit exceeded (per minute)',
        };
      }

      // Check daily rate limit
      const dayKey = `ratelimit:day:${userId}:${Math.floor(Date.now() / 86400000)}`;
      const dayRequests = await this.redis.incr(dayKey);
      
      if (dayRequests === 1) {
        await this.redis.expire(dayKey, 86400);
      }

      if (dayRequests > config.requestsPerDay) {
        this.metrics.requestsRejected.inc({ tier, reason: 'rate_limit_day' });
        this.metrics.rateLimitViolations.inc({ tier });
        
        const resetTime = Math.ceil(Date.now() / 86400000) * 86400;
        return {
          allowed: false,
          remaining: 0,
          reset: resetTime,
          reason: 'Rate limit exceeded (per day)',
        };
      }

      // Calculate remaining requests
      const windowRemaining = Math.max(0, config.requestsPerMinute - minuteRequests);
      const resetTime = Math.ceil(Date.now() / 60000 + 1) * 60;

      // Track current usage
      this.metrics.requestsCurrent.set({ user_id: userId, tier }, minuteRequests);

      // Record metric
      const duration = (Date.now() - startTime) / 1000;
      this.metrics.headerCalculationDuration.observe(duration);

      return {
        allowed: true,
        remaining: windowRemaining,
        reset: resetTime,
        limited: minuteRequests > (config.requestsPerMinute * 0.9), // 90% threshold
      };
    } catch (error) {
      console.error(`Rate limit check failed for ${userId}:`, error);
      // Fail open on error (allow request)
      return {
        allowed: true,
        remaining: 1,
        reset: Math.ceil(Date.now() / 60000 + 1) * 60,
        error: 'Rate limit check error',
      };
    }
  }

  /**
   * Decrement concurrent query counter
   * @param {string} userId - User ID
   */
  async decrementConcurrent(userId) {
    const concurrentKey = `concurrent:${userId}`;
    await this.redis.decr(concurrentKey);
  }

  /**
   * Get rate limit headers for response
   * @param {object} limitResult - Result from checkLimit()
   * @param {string} tier - User tier
   * @returns {object} Headers map
   */
  getHeaders(limitResult, tier) {
    const config = this.getConfig(tier);
    
    return {
      [RATE_LIMIT_HEADERS.limit]: config.requestsPerMinute.toString(),
      [RATE_LIMIT_HEADERS.remaining]: limitResult.remaining.toString(),
      [RATE_LIMIT_HEADERS.reset]: limitResult.reset.toString(),
      ...(limitResult.allowed === false && {
        [RATE_LIMIT_HEADERS.retryAfter]: (limitResult.reset - Math.ceil(Date.now() / 1000)).toString(),
      }),
    };
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Express/Apollo Middleware
// ════════════════════════════════════════════════════════════════════════════

function createRateLimitMiddleware(redisClient) {
  const rateLimiter = new GraphQLRateLimiter(redisClient);

  return async (req, res, next) => {
    // Extract user info from JWT token
    const userId = req.user?.id || 'anonymous';
    const userTier = req.user?.tier || 'free';

    // For GraphQL requests, calculate query complexity
    const queryComplexity = req.body?.query 
      ? calculateQueryComplexity(req.body.query)
      : 1;

    // Check rate limit
    const limitResult = await rateLimiter.checkLimit(userId, userTier, queryComplexity);

    // Add headers to response
    const headers = rateLimiter.getHeaders(limitResult, userTier);
    Object.entries(headers).forEach(([key, value]) => {
      res.set(key, value);
    });

    // Record metrics
    rateLimiter.metrics.requests.inc({
      method: req.method,
      path: req.path,
      status: limitResult.allowed ? 200 : 429,
      tier: userTier,
    });

    if (!limitResult.allowed) {
      // Rate limited - reject with 429
      return res.status(429).json({
        errors: [{
          message: 'Too Many Requests',
          extensions: {
            code: 'RATE_LIMITED',
            details: limitResult.reason,
            retryAfter: headers[RATE_LIMIT_HEADERS.retryAfter],
          },
        }],
      });
    }

    // Add cleanup handler for concurrent query tracking
    const originalEnd = res.end;
    res.end = function(...args) {
      rateLimiter.decrementConcurrent(userId);
      return originalEnd.apply(res, args);
    };

    next();
  };
}

// ════════════════════════════════════════════════════════════════════════════
// Query Complexity Calculation
// ════════════════════════════════════════════════════════════════════════════

function calculateQueryComplexity(query) {
  // Simple complexity scoring: each field = 1, nested = exponential
  // This is a placeholder - integrate graphql-query-complexity for production
  const fieldCount = (query.match(/\{/g) || []).length;
  return Math.min(fieldCount, 100); // Cap at 100
}

module.exports = {
  GraphQLRateLimiter,
  createRateLimitMiddleware,
  RATE_LIMIT_CONFIG,
  RATE_LIMIT_HEADERS,
};
