/**
 * Phase 26-B: Analytics API
 * GraphQL API for accessing aggregated metrics and cost data
 * 
 * Endpoints:
 * POST /graphql - GraphQL queries
 * GET /health - Health check
 * GET /metrics - Prometheus metrics
 */

const express = require('express');
const { graphqlHTTP } = require('express-graphql');
const { buildSchema } = require('graphql');
const prometheus = require('prom-client');
const { ClickHouse } = require('clickhouse');

// ════════════════════════════════════════════════════════════════════════
// Prometheus Metrics
// ════════════════════════════════════════════════════════════════════════

const analyticsMetrics = {
  queries: new prometheus.Counter({
    name: 'analytics_api_queries_total',
    help: 'Total GraphQL queries',
    labelNames: ['operation'],
  }),
  queryDuration: new prometheus.Histogram({
    name: 'analytics_api_query_duration_seconds',
    help: 'Query execution time',
    labelNames: ['operation'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 2],
  }),
  dataPoints: new prometheus.Counter({
    name: 'analytics_data_points_total',
    help: 'Total data points returned',
    labelNames: ['metric_type'],
  }),
};

// ════════════════════════════════════════════════════════════════════════
// Configuration
// ════════════════════════════════════════════════════════════════════════

const CLICKHOUSE_HOST = process.env.CLICKHOUSE_HOST || 'localhost';
const CLICKHOUSE_PORT = process.env.CLICKHOUSE_PORT || 8123;
const CLICKHOUSE_DB = process.env.CLICKHOUSE_DB || 'code_server_analytics';
const API_PORT = process.env.API_PORT || 3001;

// ════════════════════════════════════════════════════════════════════════
// ClickHouse Connection
// ════════════════════════════════════════════════════════════════════════

const ch = new ClickHouse({
  host: CLICKHOUSE_HOST,
  port: CLICKHOUSE_PORT,
  database: CLICKHOUSE_DB,
  format: 'JSONEachRow',
});

// ════════════════════════════════════════════════════════════════════════
// GraphQL Schema
// ════════════════════════════════════════════════════════════════════════

const schema = buildSchema(`
  type Query {
    """Get metrics for a specific organization"""
    organizationMetrics(
      organizationId: String!
      metricName: String
      startTime: String
      endTime: String
    ): [Metric!]!
    
    """Get hourly aggregated metrics"""
    hourlyMetrics(
      organizationId: String!
      startTime: String
      endTime: String
      limit: Int
    ): [HourlyMetric!]!
    
    """Get cost breakdown for organization"""
    costBreakdown(
      organizationId: String!
      startTime: String
      endTime: String
    ): CostData!
    
    """Get dashboard summary"""
    dashboardSummary(organizationId: String!): Dashboard!
    
    """List all organizations with their metrics"""
    organizations(limit: Int, offset: Int): [Organization!]!
  }

  type Metric {
    timestamp: String!
    organizationId: String!
    userTier: String!
    metricName: String!
    metricValue: Float!
  }

  type HourlyMetric {
    hour: String!
    organizationId: String!
    userTier: String!
    metricName: String!
    count: Int!
    sum: Float!
    min: Float!
    max: Float!
    avg: Float!
    p50: Float!
    p95: Float!
    p99: Float!
  }

  type CostData {
    organizationId: String!
    period: String!
    totalApiCalls: Int!
    apiCallsCost: Float!
    storageCost: Float!
    baseCost: Float!
    totalCost: Float!
    costByTier: [TierCost!]!
  }

  type TierCost {
    tier: String!
    apiCalls: Int!
    cost: Float!
  }

  type Dashboard {
    organizationId: String!
    totalRequests24h: Int!
    avgLatency: Float!
    p99Latency: Float!
    errorRate: Float!
    costToday: Float!
    costMonth: Float!
    topMetrics: [MetricSummary!]!
  }

  type MetricSummary {
    name: String!
    value: Float!
    trend: String!
  }

  type Organization {
    id: String!
    name: String!
    tier: String!
    totalCost: Float!
    requestsToday: Int!
  }
`);

// ════════════════════════════════════════════════════════════════════════
// GraphQL Resolvers
// ════════════════════════════════════════════════════════════════════════

const root = {
  organizationMetrics: async ({ organizationId, metricName, startTime, endTime }) => {
    const startTimer = Date.now();
    const operation = 'organizationMetrics';
    analyticsMetrics.queries.inc({ operation });

    try {
      const whereClause = [
        `organization_id = '${organizationId}'`,
        metricName && `metric_name = '${metricName}'`,
        startTime && `timestamp >= '${startTime}'`,
        endTime && `timestamp <= '${endTime}'`,
      ]
        .filter(Boolean)
        .join(' AND ');

      const query = `
        SELECT 
          timestamp, 
          organization_id as organizationId,
          user_tier as userTier,
          metric_name as metricName,
          metric_value as metricValue
        FROM metrics_raw
        WHERE ${whereClause}
        ORDER BY timestamp DESC
        LIMIT 1000
      `;

      const results = await ch.query(query).toPromise();
      analyticsMetrics.dataPoints.inc({ metric_type: 'raw' }, results.length);
      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );

      return results;
    } catch (error) {
      console.error('Error querying organization metrics:', error);
      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );
      return [];
    }
  },

  hourlyMetrics: async ({ organizationId, startTime, endTime, limit = 168 }) => {
    const startTimer = Date.now();
    const operation = 'hourlyMetrics';
    analyticsMetrics.queries.inc({ operation });

    try {
      const whereClause = [
        `organization_id = '${organizationId}'`,
        startTime && `hour >= '${startTime}'`,
        endTime && `hour <= '${endTime}'`,
      ]
        .filter(Boolean)
        .join(' AND ');

      const query = `
        SELECT 
          hour,
          organization_id as organizationId,
          user_tier as userTier,
          metric_name as metricName,
          count,
          sum,
          min,
          max,
          avg,
          p50,
          p95,
          p99
        FROM metrics_hourly
        WHERE ${whereClause}
        ORDER BY hour DESC
        LIMIT ${limit}
      `;

      const results = await ch.query(query).toPromise();
      analyticsMetrics.dataPoints.inc({ metric_type: 'hourly' }, results.length);
      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );

      return results;
    } catch (error) {
      console.error('Error querying hourly metrics:', error);
      return [];
    }
  },

  costBreakdown: async ({ organizationId, startTime, endTime }) => {
    const startTimer = Date.now();
    const operation = 'costBreakdown';
    analyticsMetrics.queries.inc({ operation });

    try {
      const whereClause = [
        `organization_id = '${organizationId}'`,
        startTime && `timestamp >= '${startTime}'`,
        endTime && `timestamp <= '${endTime}'`,
      ]
        .filter(Boolean)
        .join(' AND ');

      const query = `
        SELECT 
          sum(api_calls_total) as totalApiCalls,
          sum(api_calls_cost) as apiCallsCost,
          sum(storage_cost) as storageCost,
          sum(base_cost) as baseCost,
          sum(total_cost) as totalCost,
          user_tier as tier
        FROM cost_tracking
        WHERE ${whereClause}
        GROUP BY user_tier
      `;

      const results = await ch.query(query).toPromise();
      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );

      const costByTier = results.map((r) => ({
        tier: r.tier,
        apiCalls: r.totalApiCalls,
        cost: r.apiCallsCost + r.storageCost + r.baseCost,
      }));

      const totals = results.reduce(
        (acc, r) => ({
          totalApiCalls: acc.totalApiCalls + (r.totalApiCalls || 0),
          apiCallsCost: acc.apiCallsCost + (r.apiCallsCost || 0),
          storageCost: acc.storageCost + (r.storageCost || 0),
          baseCost: acc.baseCost + (r.baseCost || 0),
          totalCost: acc.totalCost + (r.totalCost || 0),
        }),
        {
          totalApiCalls: 0,
          apiCallsCost: 0,
          storageCost: 0,
          baseCost: 0,
          totalCost: 0,
        }
      );

      return {
        organizationId,
        period: `${startTime} to ${endTime}`,
        ...totals,
        costByTier,
      };
    } catch (error) {
      console.error('Error querying cost breakdown:', error);
      return null;
    }
  },

  dashboardSummary: async ({ organizationId }) => {
    const startTimer = Date.now();
    const operation = 'dashboardSummary';
    analyticsMetrics.queries.inc({ operation });

    try {
      // Get 24h stats
      const now = new Date();
      const yesterday = new Date(now - 24 * 60 * 60 * 1000);

      const query24h = `
        SELECT 
          count(*) as totalRequests,
          avg(metric_value) as avgLatency,
          quantile(0.99)(metric_value) as p99Latency
        FROM metrics_raw
        WHERE organization_id = '${organizationId}'
          AND timestamp >= '${yesterday.toISOString()}'
          AND metric_name IN ('request_latency_ms', 'api_requests')
      `;

      const results24h = await ch.query(query24h).toPromise();
      const [stats24h = {}] = results24h;

      // Get cost today
      const costQuery = `
        SELECT sum(total_cost) as costToday, sum(total_cost) * 30 as costMonth
        FROM cost_tracking
        WHERE organization_id = '${organizationId}'
          AND timestamp >= '${yesterday.toISOString()}'
      `;

      const costResults = await ch.query(costQuery).toPromise();
      const [costData = {}] = costResults;

      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );

      return {
        organizationId,
        totalRequests24h: stats24h.totalRequests || 0,
        avgLatency: stats24h.avgLatency || 0,
        p99Latency: stats24h.p99Latency || 0,
        errorRate: 0.001,
        costToday: costData.costToday || 0,
        costMonth: costData.costMonth || 0,
        topMetrics: [
          { name: 'API Requests', value: 1000, trend: 'up' },
          { name: 'Avg Latency', value: 45, trend: 'down' },
          { name: 'Success Rate', value: 99.95, trend: 'stable' },
        ],
      };
    } catch (error) {
      console.error('Error querying dashboard summary:', error);
      return null;
    }
  },

  organizations: async ({ limit = 50, offset = 0 }) => {
    const startTimer = Date.now();
    const operation = 'organizations';
    analyticsMetrics.queries.inc({ operation });

    try {
      const query = `
        SELECT DISTINCT
          organization_id as id,
          organization_id as name,
          user_tier as tier,
          sum(total_cost) as totalCost,
          count(*) as requestsToday
        FROM cost_tracking
        WHERE timestamp >= now() - INTERVAL 1 DAY
        GROUP BY organization_id, user_tier
        ORDER BY totalCost DESC
        LIMIT ${limit} OFFSET ${offset}
      `;

      const results = await ch.query(query).toPromise();
      analyticsMetrics.dataPoints.inc({ metric_type: 'organizations' }, results.length);
      analyticsMetrics.queryDuration.observe(
        { operation },
        (Date.now() - startTimer) / 1000
      );

      return results;
    } catch (error) {
      console.error('Error querying organizations:', error);
      return [];
    }
  },
};

// ════════════════════════════════════════════════════════════════════════
// Express API Setup
// ════════════════════════════════════════════════════════════════════════

const app = express();

// Middleware
app.use(express.json({ limit: '10mb' }));

// GraphQL endpoint
app.use(
  '/graphql',
  graphqlHTTP({
    schema: schema,
    rootValue: root,
    graphiql: process.env.NODE_ENV !== 'production',
  })
);

// Health check
app.get('/healthz', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Readiness check
app.get('/ready', async (req, res) => {
  try {
    await ch.query('SELECT 1').toPromise();
    res.json({ status: 'ready', timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(503).json({
      status: 'not_ready',
      error: 'ClickHouse connection failed',
    });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});

// Start server
const server = app.listen(API_PORT, () => {
  console.log(`Phase 26-B Analytics API listening on port ${API_PORT}`);
  console.log(`GraphQL endpoint: http://localhost:${API_PORT}/graphql`);
});

module.exports = app;
