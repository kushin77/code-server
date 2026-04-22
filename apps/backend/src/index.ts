// @file        apps/backend/src/index.ts
// @module      backend
// @description Main exports for the backend library - routes, services, and initialization functions
// @owner       backend

// Services
export { StandupSummariesService } from './services/standup-summaries';
export type {
  DailyActivity,
  CommitActivity,
  ReviewActivity,
  CommentActivity,
  IssueActivity,
  StandupSummary,
  StandupConfig,
} from './services/standup-summaries';

// Integration examples
export { setupStandupSummariesIntegration, createExampleApp } from './services/standup-summaries/integration-example';

// Routes
export { default as standupSummariesRouter, initializeStandupRoutes } from './routes/standup-summaries';
export { initializeSymbolDiscussionsRoutes, SymbolDiscussionsService } from './routes/symbol-discussions';
export { initializeMentionSystemRoutes, MentionSystemService } from './routes/mention-system';
export { initializeFigmaIntegrationRoutes, FigmaIntegrationService } from './routes/figma-integration';
export { initializeIssueLinkingRoutes, IssueLinkingService } from './routes/issue-linking';
export { initializeDORAMetricsRoutes, DORAMetricsService } from './routes/dora-metrics';
export { initializeHelpQueueRoutes, HelpQueueService } from './routes/help-queue';
export { initializeSmartNotificationRoutingRoutes, SmartNotificationRoutingService } from './routes/smart-notification-routing';
export { initializeActivityFeedRoutes, ActivityFeedService } from './routes/activity-feed';
export { initializeGuestSessionRoutes, GuestSessionService } from './routes/guest-sessions';
export { initializeSharedPromptLibraryRoutes, SharedPromptLibraryService } from './routes/shared-prompt-library';
export { initializeAIReviewerRouterRoutes, AIReviewerRouterService } from './routes/ai-reviewer-router';
export { initializeSessionReplayTimelineRoutes, SessionReplayTimelineService } from './services/session-replay-timeline';
export { initializeCapacityForecastingRoutes, CapacityForecastingService } from './services/capacity-forecasting';
export { initializeFunnelAnalyticsRoutes, FunnelAnalyticsService } from './services/funnel-analytics';
export { initializeIDEPerformanceProfilerRoutes, IDEPerformanceProfilerService } from './services/ide-performance-profiler';
export { initializeDependencyImpactGraphRoutes, DependencyImpactGraphService } from './services/dependency-impact-graph';
export { initializeDatabaseBrowserRoutes, DatabaseBrowserService } from './services/database-browser';
export { initializeTeamHealthDashboardRoutes, TeamHealthDashboardService } from './services/team-health-dashboard';
export { initializeCodeOwnershipGraphRoutes, CodeOwnershipGraphService } from './services/code-ownership-graph';
export { initializeCalendarIntegrationRoutes, CalendarIntegrationService } from './services/calendar-integration';
export { initializeFlowStateDetectionRoutes, FlowStateDetectionService } from './services/flow-state-detection';
export { initializeFileAdvisoryLockRoutes, FileAdvisoryLockService } from './services/file-advisory-locks';
export { initializeWorkspaceDiffRoutes, WorkspaceDiffService } from './services/workspace-diff';
export { initializeWorkspaceForkingRoutes, WorkspaceForkingService } from './services/workspace-forking';
export { initializeMultiRootWorkspaceManagerRoutes, MultiRootWorkspaceManagerService } from './services/multi-root-workspace-manager';
export { initializeDebugSessionCollaborationRoutes, DebugSessionCollaborationService } from './services/debug-session-collaboration';
export { initializeConflictPredictionRoutes, ConflictPredictionService } from './services/conflict-prediction';
export { initializeSessionHandoffProtocolRoutes, SessionHandoffProtocolService } from './services/session-handoff-protocol';
export { initializeSessionHandOffNotesRoutes, SessionHandOffNotesService } from './services/session-handoff-notes';
export { initializeExpertiseHeatmapRoutes, ExpertiseHeatmapService } from './services/expertise-heatmap';
export { initializeMessageCompressionPipelineRoutes, MessageCompressionPipelineService } from './services/message-compression-pipeline';
export { initializeEmbeddedAPIExplorerRoutes, EmbeddedAPIExplorerService } from './services/embedded-api-explorer';
export { initializeKeyboardShortcutManagerRoutes, KeyboardShortcutManagerService } from './services/keyboard-shortcut-manager';
export { initializeAutoTestGenerationRoutes } from './routes/auto-test-generation';
export { AutoTestGenerationService } from './services/auto-test-generation';
export { default as onboardingRouter } from './routes/onboarding';
export { default as sloRouter } from './routes/slo';
export { default as anomalyRouter } from './routes/anomaly';

// AI Router
export { AIRouter } from './services/ai/router';
export type { RouteRequest, RouteResult, ModelEntry } from './services/ai/router';

// Logger
export { getLogger } from './lib/logger';