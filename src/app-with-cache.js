/**
 * Express Application with Tier 3 Multi-Tier Caching
 * 
 * Example showing complete integration of L1/L2 cache into Express app
 * All configuration via environment variables (IaC pattern)
 * Middleware stacking order is critical for cache effectiveness
 */

const express = require('express');
const compression = require('compression');
const CacheBootstrap = require('./cache-bootstrap');
const { createDeduplicationMiddleware } = require('../services/request-deduplication-layer');
const { createNPlusOneOptimizerMiddleware } = require('../services/n-plus-one-query-optimizer');

/**
 * Create Express app with caching enabled
 */
function createApp() {
  const app = express();

  // Initialize caching infrastructure (singleton)
  const cacheBootstrap = CacheBootstrap.getInstance();
  
  // Initialize request deduplication (prevents concurrent duplicate requests)
  const deduplicationMiddleware = createDeduplicationMiddleware({
    windowMs: parseInt(process.env.DEDUP_WINDOW_MS || '500'),
    maxCacheSize: parseInt(process.env.DEDUP_MAX_SIZE || '10000'),
  });

  // ─────────────────────────────────────────────────────────────────────
  // Middleware Order (CRITICAL):
  // 1. Compression (reduce payload)
  // 2. Request logging
  // 3. Cache middleware (MUST be before routes)
  // 4. Body parsers
  // 5. Route handlers
  // ─────────────────────────────────────────────────────────────────────

  // Compression: Reduce response size
  app.use(compression({
    level: 9,
    threshold: 1024, // Only compress >1KB
  }));

  // Request logging
  app.use((req, res, next) => {
    const start = Date.now();
    
    res.on('finish', () => {
      const duration = Date.now() - start;
      const cacheStatus = res.get('X-Cache-Status') || 'MISS';
      
      console.log(
        `[${new Date().toISOString()}] ${req.method} ${req.path}` +
        ` ${res.statusCode} ${duration}ms [${cacheStatus}]`
      );
    });
    
    next();
  });

  // ╔═══════════════════════════════════════════════════════════════╗
  // ║  REQUEST DEDUPLICATION - MUST BE FIRST                        ║
  // ║  Prevents duplicate concurrent requests to backend            ║
  // ║  Returns cached response within dedup window (500ms default)  ║
  // ╚═══════════════════════════════════════════════════════════════╝
  app.use(deduplicationMiddleware);

  // ╔═══════════════════════════════════════════════════════════════╗
  // ║  CACHING MIDDLEWARE - MUST BE BEFORE ROUTES                  ║
  // ║  Checks L1 cache → L2 cache → backend                        ║
  // ║  Automatically caches GET responses                          ║
  // ╚═══════════════════════════════════════════════════════════════╝
  app.use(cacheBootstrap.getMiddleware());

  // Body parsing
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ limit: '10mb', extended: true }));

  // ╔═══════════════════════════════════════════════════════════════╗
  // ║  N+1 QUERY OPTIMIZER - Batch loading for database queries    ║
  // ║  Eliminates N+1 query problem with DataLoader pattern        ║
  // ║  Reduces database queries by ~90% on typical workloads       ║
  // ╚═══════════════════════════════════════════════════════════════╝
  const dbPool = require('../db/connection-pool'); // Placeholder - would be actual DB
  app.use(createNPlusOneOptimizerMiddleware(dbPool, {
    batchSize: parseInt(process.env.N_PLUS_ONE_BATCH_SIZE || '100'),
    ttl: parseInt(process.env.N_PLUS_ONE_TTL || '60000'),
  }));

  // ─────────────────────────────────────────────────────────────────────
  // ROUTES
  // ─────────────────────────────────────────────────────────────────────

  /**
   * Health Check Endpoint
   * Used by monitoring and load balancers
   * NOT cached (excluded in middleware)
   */
  app.get('/healthz', (req, res) => {
    const health = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      cache: cacheBootstrap.getHealth(),
      memory: {
        heapUsed: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + 'MB',
        heapTotal: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + 'MB',
      },
    };
    
    res.status(200).json(health);
  });

  /**
   * Metrics Endpoint
   * Prometheus-compatible metrics export
   * NOT cached (excluded in middleware)
   */
  app.get('/metrics', (req, res) => {
    res.set('Content-Type', 'text/plain; version=0.0.4');
    res.send(cacheBootstrap.getMetrics());
  });

  /**
   * Example API: Get User Data
   * WILL BE CACHED:
   * - L1 hit: <1ms response
   * - L2 hit: 5-10ms response
   * - Miss: 50-200ms response (from backend)
   * - Automatic 5-minute cache (configurable)
   */
  app.get('/api/users/:id', async (req, res) => {
    const userId = req.params.id;
    
    // Simulate backend lookup (would be database query in production)
    const userData = await simulateBackendFetch(`user:${userId}`, 100);
    
    // Mark response as cacheable
    res.set('Cache-Control', 'public, max-age=300');
    res.set('X-Cache-TTL', '300');
    
    res.json({
      id: userId,
      data: userData,
      status: 'ok',
    });
  });

  /**
   * Example API: Get List Data
   * WILL BE CACHED
   * Large responses benefit most from caching
   */
  app.get('/api/items', async (req, res) => {
    const items = await simulateBackendFetch('items:all', 150);
    
    res.set('Cache-Control', 'public, max-age=600'); // 10 minutes
    res.set('X-Cache-TTL', '600');
    
    res.json({
      items: items,
      count: items.length,
      timestamp: new Date().toISOString(),
    });
  });

  /**
   * Example API: Create Data (Mutation)
   * NOT CACHED (POST request)
   * Demonstrates cache invalidation
   */
  app.post('/api/items', async (req, res) => {
    const { name, description } = req.body;
    
    // Validate input
    if (!name) {
      return res.status(400).json({ error: 'name required' });
    }
    
    // Save to backend (would be database INSERT)
    const newItem = {
      id: Math.random().toString(36),
      name,
      description,
      createdAt: new Date().toISOString(),
    };
    
    // ╔═══════════════════════════════════════════════════════════════╗
    // ║  CACHE INVALIDATION HOOK                                      ║
    // ║  After mutation, invalidate affected cache entries            ║
    // ╚═══════════════════════════════════════════════════════════════╝
    const invalidate = cacheBootstrap.getInvalidationHook();
    
    // Invalidate the /api/items list cache
    await invalidate('/api/items*');
    // Also invalidate related caches if applicable
    await invalidate('/api/stats*');
    
    res.status(201).json({
      ...newItem,
      cached: false,
      message: 'Caches invalidated',
    });
  });

  /**
   * Example API: Update Data (Mutation)
   * NOT CACHED (PUT request)
   * Demonstrates selective cache invalidation
   */
  app.put('/api/items/:id', async (req, res) => {
    const itemId = req.params.id;
    const updates = req.body;
    
    // Update backend
    const updatedItem = { id: itemId, ...updates, updatedAt: new Date() };
    
    // Invalidate specific item cache + list cache
    const invalidate = cacheBootstrap.getInvalidationHook();
    await invalidate(`/api/items/${itemId}`);
    await invalidate(`/api/items`); // Also invalidate list
    
    res.json({
      ...updatedItem,
      message: 'Updated and caches invalidated',
    });
  });

  /**
   * Example API: Delete Data (Mutation)
   * NOT CACHED (DELETE request)
   */
  app.delete('/api/items/:id', async (req, res) => {
    const itemId = req.params.id;
    
    // Delete from backend
    
    // Invalidate caches
    const invalidate = cacheBootstrap.getInvalidationHook();
    await invalidate(`/api/items/${itemId}`);
    await invalidate(`/api/items`);
    
    res.json({
      id: itemId,
      deleted: true,
      message: 'Deleted and caches invalidated',
    });
  });

  /**
   * Cache Status Endpoint
   * Debug endpoint to check cache health
   */
  app.get('/api/cache-status', (req, res) => {
    const metrics = cacheBootstrap.monitoring;
    
    res.json({
      l1: {
        hits: metrics.l1Hits,
        misses: metrics.l1Misses,
        hitRate: (metrics.l1Hits / (metrics.l1Hits + metrics.l1Misses) * 100).toFixed(2) + '%',
      },
      l2: {
        hits: metrics.l2Hits,
        misses: metrics.l2Misses,
        hitRate: (metrics.l2Hits / (metrics.l2Hits + metrics.l2Misses) * 100).toFixed(2) + '%',
      },
      backend: {
        requests: metrics.backendRequests,
      },
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ERROR HANDLING
  // ─────────────────────────────────────────────────────────────────────

  app.use((err, req, res, next) => {
    console.error('[ERROR]', err);
    
    res.status(500).json({
      error: 'Internal Server Error',
      message: err.message,
      timestamp: new Date().toISOString(),
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // GRACEFUL SHUTDOWN
  // ─────────────────────────────────────────────────────────────────────

  process.on('SIGTERM', async () => {
    console.log('[APP] Received SIGTERM, shutting down gracefully...');
    
    // Stop accepting new requests
    server.close(() => {
      console.log('[APP] HTTP server closed');
    });
    
    // Shutdown cache services
    await cacheBootstrap.shutdown();
    
    process.exit(0);
  });

  return app;
}

/**
 * Simulate backend fetch (would be database query in production)
 * Adds artificial delay to show cache benefit
 */
async function simulateBackendFetch(key, delayMs) {
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        key,
        data: `Result for ${key}`,
        fetchedAt: new Date().toISOString(),
      });
    }, delayMs);
  });
}

/**
 * Start Server
 */
if (require.main === module) {
  const app = createApp();
  const PORT = parseInt(process.env.PORT || '3000');
  const HOST = process.env.HOST || '0.0.0.0';
  
  const server = app.listen(PORT, HOST, () => {
    console.log(`[APP] Express server listening on ${HOST}:${PORT}`);
    console.log('[APP] Tier 3 multi-tier caching ENABLED');
    console.log(`[APP]   - L1 Cache: In-process LRU (max 1000 items, 1h TTL)`);
    console.log(`[APP]   - L2 Cache: Redis distributed (24h TTL)`);
    console.log('[APP] Health check: http://localhost:' + PORT + '/healthz');
  });
}

module.exports = createApp;
