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
export { initializeGuestSessionRuntime } from './services/guest-sessions/integration-example';
export {
  initializeVoiceChannelRuntime,
  setupVoiceChannelIntegration,
  createVoiceChannelExampleApp,
} from './services/voice-channel/integration-example';
export { initializeSharedClipboardRoutes, SharedClipboardService } from './services/shared-clipboard';
export { setupSharedClipboardIntegration, createSharedClipboardExampleApp } from './services/shared-clipboard/integration-example';
export { CRDTOperationsService } from './services/crdt-operations';
export type { CRDTOperation, CRDTDocumentState } from './services/crdt-operations';
export { initializeCRDTRoutes, setupCRDTIntegration, createCRDTExampleApp } from './services/crdt-operations/integration-example';
export { TeamRichPresenceService, PresenceState } from './services/team-rich-presence';
export type { UserPresence, TeamActivitySummary, PresenceSnapshot } from './services/team-rich-presence';
export { initializeTeamRichPresenceRoutes, setupTeamRichPresenceIntegration, createTeamRichPresenceExampleApp } from './services/team-rich-presence/integration-example';
export { GuestSessionQuotasService, QuotaTier, QUOTA_LIMITS } from './services/guest-session-quotas';
export type { GuestSessionQuota, QuotaLimit, QuotaWarning } from './services/guest-session-quotas';
export { initializeGuestSessionQuotasRoutes, setupGuestSessionQuotasIntegration, createGuestSessionQuotasExampleApp } from './services/guest-session-quotas/integration-example';
export { PresenceTimezoneService } from './services/presence-timezone';
export type { TimezoneInfo, PresenceWithTimezone, TeamTimezoneStats } from './services/presence-timezone';
export { initializePresenceTimezoneRoutes, setupPresenceTimezoneIntegration, createPresenceTimezoneExampleApp } from './services/presence-timezone/integration-example';
export { SessionCostTrackingService } from './services/session-cost-tracking';
export type { SessionCost, CostComponent, UserCostSummary, ProjectCostSummary } from './services/session-cost-tracking';
export { initializeSessionCostTrackingRoutes, setupSessionCostTrackingIntegration, createSessionCostTrackingExampleApp } from './services/session-cost-tracking/integration-example';
export { InlineCommunicationService } from './services/inline-communication';
export type { InlineCommentThread, InlineComment, CodeLocation, ThreadArchive } from './services/inline-communication';
export { initializeInlineCommunicationRoutes, setupInlineCommunicationIntegration, createInlineCommunicationExampleApp } from './services/inline-communication/integration-example';

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
export { router as workspaceAutoConfigRouter } from './routes/workspace-auto-config';
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
export { setupDebugSessionCollaborationIntegration, createDebugSessionCollaborationExampleApp } from './services/debug-session-collaboration/integration-example';
export { CollaborationMessageEncryptionService } from './services/collaboration-message-encryption';
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
export { initializeStandupRoutes } from './routes/standup-summaries';
export { initializeSymbolDiscussionsRoutes } from './routes/symbol-discussions';
export { default as websocketHealthRouter } from './routes/websocket-health';
export type { ConnectionHealth, ConnectionType, QualityMetric } from './services/monitoring/websocket-health-service';
export { default as websocketHealthService } from './services/monitoring/websocket-health-service';
export { default as resourceQuotaRouter, initializeResourceQuotaRoutes } from './routes/resource-quota';
export { default as resourceQuotaService, ResourceQuotaService, QuotaTier } from './services/resource-quota';
export type {
  QuotaConfig,
  ResourceUsage,
  QuotaEnforcement,
  QuotaViolation,
  CostRateCard,
  CostUsageSample,
  SessionCostEntry,
  CostBudget,
  CostAlert,
  CostSummary,
  MonthlyCostReport,
} from './services/resource-quota';
export { default as helpQueueAuditRouter } from './routes/help-queue-audit';
export type { HelpQueueAuditAction, HelpQueueAuditEntry } from './services/help-queue/help-queue-audit';
export { HelpQueueAuditService } from './services/help-queue/help-queue-audit';
export { default as extensionRegistryRouter } from './routes/extension-registry';
export type { ExtensionMetadata, ExtensionStatus, VersionPinning, RegistryStats } from './services/extension-registry/registry-manager';
export { RegistryManagerService } from './services/extension-registry/registry-manager';

// AI Router
export { AIRouter } from './services/ai/router';
export type { RouteRequest, RouteResult, ModelEntry } from './services/ai/router';

// Logger
export { getLogger } from './lib/logger';
