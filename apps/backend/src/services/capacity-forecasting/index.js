#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/capacity-forecasting/index.ts
 * @module      services/analytics
 * @description Capacity forecasting with time-series regression for 30/60/90 day forecasts
 */
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class CapacityForecastingService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('CapacityForecastingService');
        this.pool = pool;
    }
    async initialize() {
        this.logger.info('Initializing CapacityForecastingService');
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            // Create capacity_metrics table
            await client.query(`
        CREATE TABLE IF NOT EXISTS capacity_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          metric_type VARCHAR(255) NOT NULL,
          metric_value FLOAT NOT NULL,
          recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create capacity_forecasts table
            await client.query(`
        CREATE TABLE IF NOT EXISTS capacity_forecasts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          metric_type VARCHAR(255) NOT NULL,
          forecast_30d FLOAT NOT NULL,
          forecast_60d FLOAT NOT NULL,
          forecast_90d FLOAT NOT NULL,
          confidence FLOAT NOT NULL,
          trend VARCHAR(50) NOT NULL,
          breach_threshold FLOAT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create capacity_breach_alerts table
            await client.query(`
        CREATE TABLE IF NOT EXISTS capacity_breach_alerts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          metric_type VARCHAR(255) NOT NULL,
          threshold_value FLOAT NOT NULL,
          forecast_days INTEGER NOT NULL,
          alert_severity VARCHAR(50) NOT NULL,
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create indexes
            await client.query(`CREATE INDEX IF NOT EXISTS idx_capacity_metrics_type ON capacity_metrics(metric_type, recorded_at DESC)`);
            await client.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_capacity_forecasts_metric_type_unique ON capacity_forecasts(metric_type)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_capacity_breach_alerts_active ON capacity_breach_alerts(is_active)`);
            this.logger.info('Capacity forecasting tables created successfully');
        }
        finally {
            client.release();
        }
    }
    async recordMetric(metricType, value) {
        const client = await this.pool.connect();
        try {
            const timestamp = new Date();
            await client.query(`INSERT INTO capacity_metrics (metric_type, metric_value, recorded_at)
         VALUES ($1, $2, $3)`, [metricType, value, timestamp]);
            this.emit('metric-recorded', { metricType, value });
            return { timestamp, value };
        }
        finally {
            client.release();
        }
    }
    async getMetrics(metricType, daysBack = 30) {
        const client = await this.pool.connect();
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysBack);
            const result = await client.query(`SELECT recorded_at, metric_value FROM capacity_metrics
         WHERE metric_type = $1 AND recorded_at >= $2
         ORDER BY recorded_at ASC`, [metricType, cutoffDate]);
            return result.rows.map(row => ({
                timestamp: new Date(row.recorded_at),
                value: row.metric_value
            }));
        }
        finally {
            client.release();
        }
    }
    async calculateForecast(metricType) {
        const client = await this.pool.connect();
        try {
            // Get last 30 days of data
            const metrics = await this.getMetrics(metricType, 30);
            if (metrics.length < 2) {
                throw new Error('Insufficient data for forecasting');
            }
            // Simple linear regression
            const regression = this.performLinearRegression(metrics);
            // Calculate forecasts for 30, 60, 90 days
            const forecast30d = this.projectValue(regression, 30);
            const forecast60d = this.projectValue(regression, 60);
            const forecast90d = this.projectValue(regression, 90);
            // Determine trend
            const trend = regression.slope > 0.1 ? 'increasing' : regression.slope < -0.1 ? 'decreasing' : 'stable';
            // Calculate confidence based on R²
            const confidence = Math.min(regression.r2 * 100, 95);
            const forecast = {
                metric: metricType,
                forecast30d,
                forecast60d,
                forecast90d,
                confidence,
                trend,
                breachAlertEnabled: true
            };
            // Store forecast
            await client.query(`INSERT INTO capacity_forecasts (metric_type, forecast_30d, forecast_60d, forecast_90d, confidence, trend)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (metric_type) DO UPDATE SET
         forecast_30d = $2, forecast_60d = $3, forecast_90d = $4, confidence = $5, trend = $6, updated_at = CURRENT_TIMESTAMP`, [metricType, forecast30d, forecast60d, forecast90d, confidence, trend]);
            this.emit('forecast-calculated', forecast);
            return forecast;
        }
        finally {
            client.release();
        }
    }
    performLinearRegression(data) {
        const n = data.length;
        let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
        data.forEach((point, index) => {
            const x = index;
            const y = point.value;
            sumX += x;
            sumY += y;
            sumXY += x * y;
            sumX2 += x * x;
            sumY2 += y * y;
        });
        const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
        const intercept = (sumY - slope * sumX) / n;
        // Calculate R²
        const yMean = sumY / n;
        let ssRes = 0, ssTot = 0;
        data.forEach((point, index) => {
            const predicted = slope * index + intercept;
            ssRes += Math.pow(point.value - predicted, 2);
            ssTot += Math.pow(point.value - yMean, 2);
        });
        const r2 = ssTot === 0 ? (ssRes === 0 ? 1 : 0) : 1 - (ssRes / ssTot);
        return { slope, intercept, r2 };
    }
    projectValue(regression, daysAhead) {
        // Assuming daily data points
        const x = daysAhead;
        return Math.max(0, regression.slope * x + regression.intercept);
    }
    async getForecast(metricType) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT metric_type, forecast_30d, forecast_60d, forecast_90d, confidence, trend
         FROM capacity_forecasts
         WHERE metric_type = $1
         ORDER BY created_at DESC
         LIMIT 1`, [metricType]);
            if (result.rows.length === 0)
                return null;
            const row = result.rows[0];
            return {
                metric: row.metric_type,
                forecast30d: row.forecast_30d,
                forecast60d: row.forecast_60d,
                forecast90d: row.forecast_90d,
                confidence: row.confidence,
                trend: row.trend,
                breachAlertEnabled: true
            };
        }
        finally {
            client.release();
        }
    }
    async setBreachAlert(metricType, threshold, forecastDays, severity = 'warning') {
        const client = await this.pool.connect();
        try {
            // Check if breach is likely
            const forecast = await this.getForecast(metricType);
            if (!forecast) {
                throw new Error('No forecast available for metric');
            }
            let forecastValue;
            switch (forecastDays) {
                case 30:
                    forecastValue = forecast.forecast30d;
                    break;
                case 60:
                    forecastValue = forecast.forecast60d;
                    break;
                case 90:
                    forecastValue = forecast.forecast90d;
                    break;
                default: forecastValue = forecast.forecast30d;
            }
            const willBreach = forecastValue >= threshold;
            if (willBreach) {
                await client.query(`INSERT INTO capacity_breach_alerts (metric_type, threshold_value, forecast_days, alert_severity)
           VALUES ($1, $2, $3, $4)`, [metricType, threshold, forecastDays, severity]);
                this.emit('breach-alert-triggered', {
                    metricType,
                    threshold,
                    forecastDays,
                    projectedValue: forecastValue
                });
            }
        }
        finally {
            client.release();
        }
    }
    async getActiveBreaches() {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT metric_type, threshold_value, forecast_days, alert_severity
         FROM capacity_breach_alerts
         WHERE is_active = true
         ORDER BY created_at DESC`);
            return result.rows;
        }
        finally {
            client.release();
        }
    }
    async dismissBreachAlert(alertId) {
        const client = await this.pool.connect();
        try {
            await client.query(`UPDATE capacity_breach_alerts
         SET is_active = false
         WHERE id = $1`, [alertId]);
            this.emit('breach-alert-dismissed', { alertId });
        }
        finally {
            client.release();
        }
    }
    async cleanupOldMetrics(daysOld = 90) {
        const client = await this.pool.connect();
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysOld);
            const result = await client.query(`DELETE FROM capacity_metrics
         WHERE recorded_at < $1`, [cutoffDate]);
            this.emit('metrics-cleaned', { count: result.rowCount, daysOld });
            return result.rowCount || 0;
        }
        finally {
            client.release();
        }
    }
}
export async function initializeCapacityForecastingRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('CapacityForecastingRoutes');
    router.post('/api/metrics/record', async (req, res) => {
        try {
            const { metricType, value } = req.body;
            const metric = await service.recordMetric(metricType, value);
            res.json(metric);
        }
        catch (error) {
            logger.error('Failed to record metric', error);
            res.status(500).json({ error: 'Failed to record metric' });
        }
    });
    router.get('/api/metrics/:metricType', async (req, res) => {
        try {
            const { metricType } = req.params;
            const daysBack = parseInt(req.query.daysBack) || 30;
            const metrics = await service.getMetrics(metricType, daysBack);
            res.json(metrics);
        }
        catch (error) {
            logger.error('Failed to get metrics', error);
            res.status(500).json({ error: 'Failed to get metrics' });
        }
    });
    router.post('/api/forecasts/calculate', async (req, res) => {
        try {
            const { metricType } = req.body;
            const forecast = await service.calculateForecast(metricType);
            res.json(forecast);
        }
        catch (error) {
            logger.error('Failed to calculate forecast', error);
            res.status(500).json({ error: 'Failed to calculate forecast' });
        }
    });
    router.get('/api/forecasts/:metricType', async (req, res) => {
        try {
            const { metricType } = req.params;
            const forecast = await service.getForecast(metricType);
            if (!forecast) {
                return res.status(404).json({ error: 'No forecast found' });
            }
            res.json(forecast);
        }
        catch (error) {
            logger.error('Failed to get forecast', error);
            res.status(500).json({ error: 'Failed to get forecast' });
        }
    });
    router.post('/api/alerts/breach', async (req, res) => {
        try {
            const { metricType, threshold, forecastDays, severity } = req.body;
            await service.setBreachAlert(metricType, threshold, forecastDays, severity);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to set breach alert', error);
            res.status(500).json({ error: 'Failed to set breach alert' });
        }
    });
    router.get('/api/alerts/breaches', async (req, res) => {
        try {
            const breaches = await service.getActiveBreaches();
            res.json(breaches);
        }
        catch (error) {
            logger.error('Failed to get breaches', error);
            res.status(500).json({ error: 'Failed to get breaches' });
        }
    });
    router.post('/api/alerts/:alertId/dismiss', async (req, res) => {
        try {
            const { alertId } = req.params;
            await service.dismissBreachAlert(alertId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to dismiss alert', error);
            res.status(500).json({ error: 'Failed to dismiss alert' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map