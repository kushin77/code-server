import { describe, it, expect, beforeEach, vi } from 'vitest';
import { CapacityForecastingService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('CapacityForecastingService', () => {
  let service: CapacityForecastingService;
  let mockPool: any;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn()
    };

    mockPool = {
      connect: vi.fn().mockResolvedValue(mockClient)
    };

    service = new CapacityForecastingService(mockPool);
  });

  it('should initialize service and create tables', async () => {
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});
    mockClient.query.mockResolvedValueOnce({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('capacity_metrics'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('should record a metric', async () => {
    mockClient.query.mockResolvedValueOnce({});

    const metric = await service.recordMetric('sessions_per_day', 100);

    expect(metric.value).toBe(100);
    expect(metric.timestamp).toBeDefined();
  });

  it('should get metrics for a time period', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-20T10:00:00'), metric_value: 100 },
        { recorded_at: new Date('2025-04-21T10:00:00'), metric_value: 110 }
      ]
    });

    const metrics = await service.getMetrics('sessions_per_day', 30);

    expect(metrics.length).toBe(2);
    expect(metrics[0].value).toBe(100);
  });

  it('should calculate forecast with linear regression', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-01T10:00:00'), metric_value: 50 },
        { recorded_at: new Date('2025-04-02T10:00:00'), metric_value: 52 },
        { recorded_at: new Date('2025-04-03T10:00:00'), metric_value: 54 },
        { recorded_at: new Date('2025-04-04T10:00:00'), metric_value: 56 },
        { recorded_at: new Date('2025-04-05T10:00:00'), metric_value: 58 }
      ]
    });

    mockClient.query.mockResolvedValueOnce({});

    const forecast = await service.calculateForecast('sessions_per_day');

    expect(forecast.metric).toBe('sessions_per_day');
    expect(forecast.forecast30d).toBeGreaterThan(50);
    expect(forecast.forecast60d).toBeGreaterThan(forecast.forecast30d);
    expect(forecast.confidence).toBeGreaterThan(0);
  });

  it('should determine trend as increasing', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-01T10:00:00'), metric_value: 50 },
        { recorded_at: new Date('2025-04-02T10:00:00'), metric_value: 60 },
        { recorded_at: new Date('2025-04-03T10:00:00'), metric_value: 70 }
      ]
    });

    mockClient.query.mockResolvedValueOnce({});

    const forecast = await service.calculateForecast('cpu_usage');

    expect(forecast.trend).toBe('increasing');
  });

  it('should get existing forecast', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        metric_type: 'sessions_per_day',
        forecast_30d: 120,
        forecast_60d: 130,
        forecast_90d: 140,
        confidence: 85,
        trend: 'increasing'
      }]
    });

    const forecast = await service.getForecast('sessions_per_day');

    expect(forecast?.metric).toBe('sessions_per_day');
    expect(forecast?.forecast30d).toBe(120);
  });

  it('should set breach alert when threshold will be exceeded', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        metric_type: 'cpu_usage',
        forecast_30d: 95,
        forecast_60d: 105,
        forecast_90d: 115,
        confidence: 80,
        trend: 'increasing'
      }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.setBreachAlert('cpu_usage', 90, 30, 'critical');

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should get active breach alerts', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        metric_type: 'memory_usage',
        threshold_value: 80,
        forecast_days: 30,
        alert_severity: 'warning'
      }]
    });

    const breaches = await service.getActiveBreaches();

    expect(breaches.length).toBe(1);
    expect(breaches[0].metric_type).toBe('memory_usage');
  });

  it('should dismiss breach alert', async () => {
    mockClient.query.mockResolvedValueOnce({});

    await service.dismissBreachAlert('alert-123');

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE capacity_breach_alerts'),
      expect.any(Array)
    );
  });

  it('should cleanup old metrics', async () => {
    mockClient.query.mockResolvedValueOnce({
      rowCount: 500
    });

    const count = await service.cleanupOldMetrics(90);

    expect(count).toBe(500);
  });

  it('should emit metric-recorded event', async () => {
    let emittedEvent: any;

    service.on('metric-recorded', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.recordMetric('sessions_per_day', 100);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.metricType).toBe('sessions_per_day');
  });

  it('should emit forecast-calculated event', async () => {
    let emittedEvent: any;

    service.on('forecast-calculated', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-01T10:00:00'), metric_value: 50 },
        { recorded_at: new Date('2025-04-02T10:00:00'), metric_value: 52 }
      ]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.calculateForecast('cpu_usage');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.metric).toBe('cpu_usage');
  });

  it('should return null for non-existent forecast', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: []
    });

    const forecast = await service.getForecast('non_existent_metric');

    expect(forecast).toBeNull();
  });

  it('should throw error if insufficient data for forecast', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{ recorded_at: new Date(), metric_value: 100 }]
    });

    await expect(service.calculateForecast('sessions_per_day')).rejects.toThrow('Insufficient data');
  });

  it('should emit breach-alert-triggered event', async () => {
    let emittedEvent: any;

    service.on('breach-alert-triggered', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        metric_type: 'cpu_usage',
        forecast_30d: 95,
        forecast_60d: 105,
        forecast_90d: 115,
        confidence: 80,
        trend: 'increasing'
      }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.setBreachAlert('cpu_usage', 90, 30, 'critical');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.metricType).toBe('cpu_usage');
  });

  it('should handle forecast with stable trend', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-01T10:00:00'), metric_value: 50 },
        { recorded_at: new Date('2025-04-02T10:00:00'), metric_value: 50 },
        { recorded_at: new Date('2025-04-03T10:00:00'), metric_value: 50 }
      ]
    });

    mockClient.query.mockResolvedValueOnce({});

    const forecast = await service.calculateForecast('memory_usage');

    expect(forecast.trend).toBe('stable');
    expect(Number.isFinite(forecast.confidence)).toBe(true);
  });

  it('should handle forecast with decreasing trend', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { recorded_at: new Date('2025-04-01T10:00:00'), metric_value: 100 },
        { recorded_at: new Date('2025-04-02T10:00:00'), metric_value: 90 },
        { recorded_at: new Date('2025-04-03T10:00:00'), metric_value: 80 }
      ]
    });

    mockClient.query.mockResolvedValueOnce({});

    const forecast = await service.calculateForecast('memory_usage');

    expect(forecast.trend).toBe('decreasing');
  });

  it('should emit metrics-cleaned event', async () => {
    let emittedEvent: any;

    service.on('metrics-cleaned', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rowCount: 300
    });

    await service.cleanupOldMetrics(90);

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.count).toBe(300);
  });

  it('should handle 60 day forecast in breach alert', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        metric_type: 'cpu_usage',
        forecast_30d: 85,
        forecast_60d: 98,
        forecast_90d: 110,
        confidence: 80,
        trend: 'increasing'
      }]
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.setBreachAlert('cpu_usage', 95, 60, 'warning');

    expect(mockClient.query).toHaveBeenCalled();
  });

  it('should emit breach-alert-dismissed event', async () => {
    let emittedEvent: any;

    service.on('breach-alert-dismissed', (event) => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({});

    await service.dismissBreachAlert('alert-456');

    expect(emittedEvent).toBeDefined();
    expect(emittedEvent.alertId).toBe('alert-456');
  });
});
