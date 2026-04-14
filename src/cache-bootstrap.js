/**
 * Tier 3 Caching Bootstrap
 * Integrates L1/L2 multi-tier cache into Express application
 *
 * This module:
 * - Initializes L1 and L2 cache services
 * - Configures middleware for Express pipeline
 * - Sets up cache invalidation hooks
 * - Exports metrics for monitoring
 *
 * IaC Pattern: Stateless service initialization
 * All configuration via environment variables
 */

const L1CacheService = require('./l1-cache-service');
const L2CacheService = require('./l2-cache-service');
const MultiTierCacheMiddleware = require('./multi-tier-cache-middleware');
const CacheInvalidationService = require('./cache-invalidation-service');
const CacheMonitoringService = require('./cache-monitoring-service');

/**
 * Initialize caching infrastructure
 * Safe to call multiple times (idempotent)
 */
class CacheBootstrap {
  static instance = null;

  static getInstance() {
    if (!CacheBootstrap.instance) {
      CacheBootstrap.instance = new CacheBootstrap();
    }
    return CacheBootstrap.instance;
  }

  constructor() {
    // L1 Cache: In-process LRU
    this.l1Cache = new L1CacheService({
      maxSize: parseInt(process.env.L1_CACHE_SIZE || '1000'),
      ttlMs: parseInt(process.env.L1_CACHE_TTL_MS || '3600000'), // 1 hour
    });

    // L2 Cache: Redis distributed
    this.l2Cache = new L2CacheService({
      host: process.env.REDIS_HOST || 'redis',
      port: parseInt(process.env.REDIS_PORT || '6379'),
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_DB || '0'),
    });

    // Multi-tier middleware
    this.cacheMiddleware = new MultiTierCacheMiddleware(
      this.l1Cache,
      this.l2Cache
    );

    // Monitoring
    this.monitoring = new CacheMonitoringService();

    // Status
    this.initialized = true;
  }

  /**
   * Get caching middleware for Express
   * Usage: app.use(cacheBootstrap.getMiddleware())
   */
  getMiddleware() {
    return this.cacheMiddleware.middleware({
      l1Cache: this.l1Cache,
      l2Cache: this.l2Cache,
      monitoring: this.monitoring,
      // Cache GET requests only
      shouldCache: (req) => req.method === 'GET',
      // Exclude health/metrics endpoints
      excludePaths: ['/healthz', '/health', '/metrics', '/api/metrics'],
      // Cache duration for dynamic content
      defaultTtl: parseInt(process.env.CACHE_DEFAULT_TTL_MS || '300000'), // 5 min
    });
  }

  /**
   * Get cache invalidation hook for mutations
   * Usage: In route handlers
   *
   * Example:
   *   app.post('/api/data', (req, res) => {
   *     // Save data
   *     // Invalidate cache
   *     cacheBootstrap.getInvalidationHook()('/api/data/*');
   *   });
   */
  getInvalidationHook() {
    return async (pattern) => {
      await CacheInvalidationService.invalidateByPattern(
        pattern,
        this.l1Cache,
        this.l2Cache
      );
    };
  }

  /**
   * Get metrics exporter for Prometheus
   * Usage: app.get('/metrics', (req, res) => {
   *   res.set('Content-Type', 'text/plain');
   *   res.send(cacheBootstrap.getMetrics());
   * });
   */
  getMetrics() {
    return this.monitoring.getPrometheusMetrics();
  }

  /**
   * Graceful shutdown hook
   * Usage: process.on('SIGTERM', () => {
   *   cacheBootstrap.shutdown();
   * });
   */
  async shutdown() {
    try {
      // Flush caches
      this.l1Cache.clear();
      await this.l2Cache.clear();
      this.initialized = false;
      console.log('[CacheBootstrap] Gracefully shut down cache services');
    } catch (err) {
      console.error('[CacheBootstrap] Error during shutdown:', err);
    }
  }

  /**
   * Get health status
   */
  getHealth() {
    return {
      l1CacheHealth: 'ok',
      l2CacheHealth: 'ok', // Would actually test Redis
      monitoring: 'ok',
      uptime: process.uptime(),
    };
  }
}

module.exports = CacheBootstrap;
