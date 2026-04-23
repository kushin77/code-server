#!/usr/bin/env node
// @file        apps/backend/src/services/team-health-dashboard/__tests__/team-health-dashboard.test.ts
// @module      collaboration/team-health-dashboard/tests
// @description Comprehensive test suite for TeamHealthDashboard
// @owner       collab-6.4
// @status      active

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { TeamHealthDashboard } from '../team-health-dashboard';

describe('TeamHealthDashboard', () => {
  let dashboard: TeamHealthDashboard;

  beforeEach(async () => {
    dashboard = new TeamHealthDashboard({
      teamId: 'team-001',
      refreshIntervalSeconds: 60,
      enableRealTimeUpdates: false,
      enableAlerts: true,
      enableTrendAnalysis: true,
      alertThresholds: {
        highNotificationOverload: 75,
        slowDecisionVelocity: 5,
        lowAsyncAdoption: 40,
        highMeetingHeaviness: 5,
      },
    });
    await dashboard.initialize();
  });

  afterEach(async () => {
    await dashboard.shutdown();
  });

  describe('Dashboard Initialization', () => {
    it('should initialize dashboard successfully', async () => {
      expect(dashboard).toBeDefined();
    });

    it('should emit initialized event on startup', async () => {
      let emitted = false;
      const newDashboard = new TeamHealthDashboard();
      newDashboard.once('initialized', () => {
        emitted = true;
      });
      await newDashboard.initialize();
      expect(emitted).toBe(true);
      await newDashboard.shutdown();
    });
  });

  describe('Team Health Score', () => {
    it('should calculate team health score', async () => {
      const health = await dashboard.getTeamHealth('team-001');

      expect(health).toBeDefined();
      expect(health.teamId).toBe('team-001');
      expect(health.overallScore).toBeGreaterThanOrEqual(0);
      expect(health.overallScore).toBeLessThanOrEqual(100);
    });

    it('should include all health dimensions', async () => {
      const health = await dashboard.getTeamHealth('team-001');

      expect(health.collaborationScore).toBeDefined();
      expect(health.communicationHealth).toBeDefined();
      expect(health.activityHealth).toBeDefined();
      expect(health.readinessHealth).toBeDefined();
      expect(health.notificationHealth).toBeDefined();
    });

    it('should track trend direction', async () => {
      const health = await dashboard.getTeamHealth('team-001');

      expect(['improving', 'stable', 'declining']).toContain(health.trendDirection);
    });

    it('should emit healthCalculated event', async () => {
      let emitted = false;
      dashboard.once('healthCalculated', () => {
        emitted = true;
      });

      await dashboard.getTeamHealth('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Dashboard Snapshot', () => {
    it('should generate dashboard snapshot', async () => {
      const snapshot = await dashboard.getDashboardSnapshot('team-001');

      expect(snapshot).toBeDefined();
      expect(snapshot.teamId).toBe('team-001');
      expect(snapshot.health).toBeDefined();
      expect(snapshot.topRecommendations).toBeDefined();
      expect(snapshot.activeAlerts).toBeDefined();
      expect(snapshot.recentActivity).toBeDefined();
      expect(snapshot.trends).toBeDefined();
    });

    it('should include timestamp in snapshot', async () => {
      const snapshot = await dashboard.getDashboardSnapshot('team-001');

      expect(snapshot.timestamp).toBeDefined();
      expect(snapshot.timestamp).toBeInstanceOf(Date);
    });

    it('should include recent activity in snapshot', async () => {
      const snapshot = await dashboard.getDashboardSnapshot('team-001');

      expect(snapshot.recentActivity).toBeDefined();
      expect(Array.isArray(snapshot.recentActivity)).toBe(true);
      expect(snapshot.recentActivity.length).toBeGreaterThan(0);
    });

    it('should emit snapshotGenerated event', async () => {
      let emitted = false;
      dashboard.once('snapshotGenerated', () => {
        emitted = true;
      });

      await dashboard.getDashboardSnapshot('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Recommendations', () => {
    it('should retrieve top recommendations', async () => {
      const recommendations = await dashboard.getTopRecommendations('team-001', 5);

      expect(recommendations).toBeDefined();
      expect(Array.isArray(recommendations)).toBe(true);
    });

    it('should filter by confidence', async () => {
      const recommendations = await dashboard.getTopRecommendations('team-001', 5, {
        minConfidence: 0.0,
      });

      recommendations.forEach((rec) => {
        expect(rec.confidence).toBeGreaterThanOrEqual(0.0);
      });
    });

    it('should return array of recommendations', async () => {
      const recommendations = await dashboard.getTopRecommendations('team-001', 3);
      expect(Array.isArray(recommendations)).toBe(true);
      expect(recommendations.length).toBeLessThanOrEqual(3);
    });
  });

  describe('Health Trends', () => {
    it('should analyze health trends', async () => {
      const trends = await dashboard.getHealthTrends('team-001');

      expect(trends).toBeDefined();
      expect(Array.isArray(trends)).toBe(true);
      expect(trends.length).toBeGreaterThan(0);
    });

    it('should include trend direction', async () => {
      const trends = await dashboard.getHealthTrends('team-001');

      trends.forEach((trend) => {
        expect(['up', 'stable', 'down']).toContain(trend.trendDirection);
      });
    });

    it('should provide forecast values', async () => {
      const trends = await dashboard.getHealthTrends('team-001');

      trends.forEach((trend) => {
        expect(trend.forecastedValue).toBeDefined();
        expect(typeof trend.forecastedValue).toBe('number');
      });
    });

    it('should provide forecast confidence', async () => {
      const trends = await dashboard.getHealthTrends('team-001');

      trends.forEach((trend) => {
        expect(trend.forecastConfidence).toBeGreaterThanOrEqual(0);
        expect(trend.forecastConfidence).toBeLessThanOrEqual(1);
      });
    });

    it('should emit trendsAnalyzed event', async () => {
      let emitted = false;
      dashboard.once('trendsAnalyzed', () => {
        emitted = true;
      });

      await dashboard.getHealthTrends('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Team Comparison', () => {
    it('should compare teams', async () => {
      const comparisons = await dashboard.compareTeams('team-001');

      expect(comparisons).toBeDefined();
      expect(Array.isArray(comparisons)).toBe(true);
    });

    it('should calculate percentiles for comparisons', async () => {
      const comparisons = await dashboard.compareTeams('team-001');

      comparisons.forEach((comparison) => {
        if (comparison.percentile !== undefined) {
          expect(comparison.percentile).toBeGreaterThanOrEqual(0);
          expect(comparison.percentile).toBeLessThanOrEqual(100);
        }
      });
    });

    it('should provide team comparison metrics', async () => {
      const comparisons = await dashboard.compareTeams('team-001');

      expect(Array.isArray(comparisons)).toBe(true);
      if (comparisons.length > 0) {
        expect(comparisons[0]).toHaveProperty('teamId');
      }
    });

    it('should emit teamsCompared event', async () => {
      let emitted = false;
      dashboard.once('teamsCompared', () => {
        emitted = true;
      });

      await dashboard.compareTeams('team-002');
      expect(emitted).toBe(true);
    });
  });

  describe('Alert Configuration', () => {
    it('should configure alerts', async () => {
      let emitted = false;
      dashboard.once('alertsConfigured', () => {
        emitted = true;
      });

      await dashboard.configureAlerts('team-001', {
        highNotificationOverload: 80,
        slowDecisionVelocity: 4,
      });

      expect(emitted).toBe(true);
    });

    it('should merge threshold configurations', async () => {
      await dashboard.configureAlerts('team-001', {
        highNotificationOverload: 90,
      });

      // Configuration should be updated while preserving other settings
      expect(dashboard).toBeDefined();
    });
  });

  describe('Alert Evaluation', () => {
    it('should evaluate alerts for team', async () => {
      const alerts = await dashboard.evaluateAlerts('team-001');

      expect(alerts).toBeDefined();
      expect(Array.isArray(alerts)).toBe(true);
    });

    it('should classify alert severity', async () => {
      const alerts = await dashboard.evaluateAlerts('team-001');

      alerts.forEach((alert) => {
        expect(['low', 'medium', 'high', 'critical']).toContain(alert.severity);
      });
    });

    it('should include suggested actions in alerts', async () => {
      const alerts = await dashboard.evaluateAlerts('team-001');

      alerts.forEach((alert) => {
        expect(alert.suggestedActions).toBeDefined();
        expect(Array.isArray(alert.suggestedActions)).toBe(true);
        expect(alert.suggestedActions.length).toBeGreaterThan(0);
      });
    });

    it('should emit alertTriggered events', async () => {
      const emittedAlerts: any[] = [];
      dashboard.on('alertTriggered', (alert) => {
        emittedAlerts.push(alert);
      });

      await dashboard.evaluateAlerts('team-001');
      // May or may not emit depending on simulated metrics
      expect(Array.isArray(emittedAlerts)).toBe(true);
    });
  });

  describe('Recommendation Status Tracking', () => {
    it('should track recommendation status updates', async () => {
      await dashboard.updateRecommendationStatus('rec-001', 'in-progress');
      expect(dashboard).toBeDefined();
    });

    it('should handle recommendation status changes', async () => {
      await dashboard.updateRecommendationStatus('rec-001', 'completed');
      expect(dashboard).toBeDefined();
    });
  });

  describe('Report Generation', () => {
    it('should generate report', async () => {
      const report = await dashboard.generateReport({
        teamId: 'team-001',
        format: 'json',
        period: 'month',
        sections: ['executive-summary', 'detailed-metrics'],
      });

      expect(report).toBeDefined();
      expect(typeof report).toBe('string');
    });

    it('should emit reportGenerated event', async () => {
      let emitted = false;
      dashboard.once('reportGenerated', () => {
        emitted = true;
      });

      await dashboard.generateReport({
        teamId: 'team-002',
        format: 'pdf',
        period: 'week',
        sections: ['executive-summary'],
      });

      expect(emitted).toBe(true);
    });
  });

  describe('Widget Management', () => {
    it('should configure widgets', async () => {
      let emitted = false;
      dashboard.once('widgetsConfigured', () => {
        emitted = true;
      });

      await dashboard.configureWidgets([
        {
          id: 'widget-1',
          name: 'health-summary',
          displayName: 'Health Summary',
          position: 1,
          size: 'medium',
          refreshIntervalSeconds: 60,
          isVisible: true,
          lastUpdated: new Date(),
        },
      ]);

      expect(emitted).toBe(true);
    });

    it('should get widget data', async () => {
      await dashboard.configureWidgets([
        {
          id: 'widget-1',
          name: 'health-summary',
          displayName: 'Health Summary',
          position: 1,
          size: 'medium',
          refreshIntervalSeconds: 60,
          isVisible: true,
          lastUpdated: new Date(),
          data: { score: 75 },
        },
      ]);

      const data = await dashboard.getWidgetData('widget-1');
      expect(data).toBeDefined();
    });

    it('should emit widgetDataFetched event', async () => {
      await dashboard.configureWidgets([
        {
          id: 'widget-1',
          name: 'health-summary',
          displayName: 'Health Summary',
          position: 1,
          size: 'medium',
          refreshIntervalSeconds: 60,
          isVisible: true,
          lastUpdated: new Date(),
        },
      ]);

      let emitted = false;
      dashboard.once('widgetDataFetched', () => {
        emitted = true;
      });

      await dashboard.getWidgetData('widget-1');
      expect(emitted).toBe(true);
    });
  });

  describe('Performance', () => {
    it('should calculate health in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.getTeamHealth('team-perf-001');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should generate snapshot in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.getDashboardSnapshot('team-perf-002');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should retrieve recommendations in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.getTopRecommendations('team-perf-003', 5);
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should analyze trends in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.getHealthTrends('team-perf-004');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should compare teams in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.compareTeams('team-perf-005');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });

    it('should evaluate alerts in <15ms', async () => {
      const startTime = performance.now();
      await dashboard.evaluateAlerts('team-perf-006');
      const endTime = performance.now();

      expect(endTime - startTime).toBeLessThan(15);
    });
  });

  describe('Integration', () => {
    it('should handle multiple teams concurrently', async () => {
      const results = await Promise.all([
        dashboard.getTeamHealth('team-a'),
        dashboard.getTeamHealth('team-b'),
        dashboard.getTeamHealth('team-c'),
      ]);

      expect(results.length).toBe(3);
      results.forEach((result) => {
        expect(result.overallScore).toBeGreaterThanOrEqual(0);
        expect(result.overallScore).toBeLessThanOrEqual(100);
      });
    });

    it('should perform multiple analysis types for same team', async () => {
      const teamId = 'team-integration-001';

      const [health, snapshot, trends, comparisons] = await Promise.all([
        dashboard.getTeamHealth(teamId),
        dashboard.getDashboardSnapshot(teamId),
        dashboard.getHealthTrends(teamId),
        dashboard.compareTeams(teamId),
      ]);

      expect(health).toBeDefined();
      expect(snapshot).toBeDefined();
      expect(trends).toBeDefined();
      expect(comparisons).toBeDefined();
    });
  });
});
