# Code Smell Audit Report

- Timestamp (UTC): 2026-04-24T01:00:13Z
- Strict mode: 1
- Run ESLint checks: 1
- Run unused-export checks: 1
- Run complexity checks: 1
- Frontend complexity max threshold: 40
- Agent farm complexity max threshold: 10

## ESLint Strict Mode
- PASS: apps/frontend eslint strict check
- PASS: apps/extensions/agent-farm eslint strict check

## Unused Export Checks
- FAIL: apps/frontend has unused exports

### apps/frontend ts-prune findings
```
\apps\frontend\src\App.tsx:1060 - App
\apps\frontend\src\App.tsx:438 - WorkspaceStateHandle (used in module)
\apps\frontend\src\common\lucide-react.tsx:108 - AlertCircle
\apps\frontend\src\common\lucide-react.tsx:128 - ChevronDown
\apps\frontend\src\common\lucide-react.tsx:146 - ChevronRight
\apps\frontend\src\common\lucide-react.tsx:164 - Search
\apps\frontend\src\common\lucide-react.tsx:183 - X
\apps\frontend\src\common\performance.ts:28 - useExtensionMountProfiler
\apps\frontend\src\common\performance.ts:86 - getAllMetrics
\apps\frontend\src\common\performance.ts:93 - clearMetrics
\apps\frontend\src\common\performance.ts:100 - getMetricsForExtension
\apps\frontend\src\common\performance.ts:8 - PerformanceMetric (used in module)
\apps\frontend\src\components\CollaborativeDebuggingPanel.tsx:20 - CollaborativeDebuggingPanelProps (used in module)
\apps\frontend\src\components\RichPresencePanel.tsx:27 - RichPresencePanel
\apps\frontend\src\components\RichPresencePanel.tsx:5 - RichPresencePanelProps (used in module)
\apps\frontend\src\components\SessionSnapshotManager.tsx:18 - SessionSnapshotManager (used in module)
\apps\frontend\src\components\SessionSnapshotManager.tsx:468 - default
\apps\frontend\src\components\shared-session-modal.tsx:53 - SharedSessionModal (used in module)
\apps\frontend\src\components\shared-session-modal.tsx:270 - default
\apps\frontend\src\components\VoiceChannelPanel.tsx:18 - VoiceChannelPanelProps (used in module)
\apps\frontend\src\components\WorkspaceDiffPanel.tsx:11 - WorkspaceDiffPanel
\apps\frontend\src\components\WorkspaceDiffPanel.tsx:5 - WorkspaceDiffPanelProps (used in module)
\apps\frontend\src\components\WorkspaceSwitcher.tsx:32 - WorkspaceSwitcherPanel
\apps\frontend\src\extensions\pagerduty-incidents.ts:39 - createPagerDutyApiClient (used in module)
\apps\frontend\src\extensions\pagerduty-incidents.ts:118 - acknowledgeIncident
\apps\frontend\src\extensions\pagerduty-incidents.ts:163 - resolveIncident
\apps\frontend\src\hooks\index.ts:21 - useLogin
\apps\frontend\src\hooks\index.ts:95 - useUserManagement
\apps\frontend\src\hooks\index.ts:182 - useRepositoryAccess
\apps\frontend\src\hooks\index.ts:231 - useAPITokens
\apps\frontend\src\hooks\index.ts:293 - useSessions
\apps\frontend\src\hooks\index.ts:344 - useEphemeralSessions
\apps\frontend\src\hooks\useApprovalWorkflow.ts:19 - useApprovalWorkflow
\apps\frontend\src\hooks\useRemoteSignals.ts:11 - useRemoteSignals
\apps\frontend\src\hooks\useWorkspacePolicy.ts:16 - useWorkspacePolicy
\apps\frontend\src\hooks\useWorkspaceStorage.ts:12 - useWorkspaceStorage
\apps\frontend\src\pages\CiLogsPage.tsx:65 - default
\apps\frontend\src\pages\UserManagement.tsx:166 - default
\apps\frontend\src\services\workspace-state-cache.ts:59 - WORKSPACE_STATE_DB (used in module)
\apps\frontend\src\store\index.ts:10 - useAuthStore
\apps\frontend\src\store\index.ts:46 - useUserStore
\apps\frontend\src\store\index.ts:85 - useRoleStore
\apps\frontend\src\types\index.ts:15 - Organization (used in module)
\apps\frontend\src\types\index.ts:22 - User (used in module)
\apps\frontend\src\types\index.ts:34 - Role (used in module)
\apps\frontend\src\types\index.ts:42 - UserRole (used in module)
\apps\frontend\src\types\index.ts:53 - RepositoryAccess
\apps\frontend\src\types\index.ts:65 - APIToken
\apps\frontend\src\types\index.ts:76 - Session
\apps\frontend\src\types\index.ts:87 - SessionLifecycleState (used in module)
\apps\frontend\src\types\index.ts:89 - SessionQueueLane (used in module)
\apps\frontend\src\types\index.ts:91 - SessionDataProfile (used in module)
\apps\frontend\src\types\index.ts:93 - SessionProvenanceVerificationResult (used in module)
\apps\frontend\src\types\index.ts:95 - SessionProvenanceManifest (used in module)
\apps\frontend\src\types\index.ts:107 - EphemeralSession
\apps\frontend\src\types\index.ts:136 - EphemeralSessionLaunchRequest
\apps\frontend\src\types\index.ts:147 - SessionQueueSummary (used in module)
\apps\frontend\src\types\index.ts:156 - EphemeralSessionStatus
\apps\frontend\src\types\index.ts:173 - AuditLog
\apps\frontend\src\types\index.ts:184 - Permission (used in module)
\apps\frontend\src\types\index.ts:195 - LoginRequest
\apps\frontend\src\types\index.ts:202 - LoginResponse
\apps\frontend\src\types\index.ts:212 - MFAVerifyRequest
\apps\frontend\src\types\index.ts:218 - MFAVerifyResponse
\apps\frontend\src\types\index.ts:225 - MFASetupResponse
\apps\frontend\src\types\index.ts:232 - CreateUserRequest
\apps\frontend\src\types\index.ts:238 - UpdateUserRequest
\apps\frontend\src\types\index.ts:244 - AssignRoleRequest
\apps\frontend\src\types\index.ts:251 - GrantRepoAccessRequest
\apps\frontend\src\types\index.ts:260 - CreateTokenRequest
\apps\frontend\src\types\index.ts:267 - CreateTokenResponse
\apps\frontend\src\types\index.ts:279 - AuthState
\apps\frontend\src\types\index.ts:294 - UserState
\apps\frontend\src\types\index.ts:309 - RoleState
\apps\frontend\src\types\index.ts:319 - TableColumn
\apps\frontend\src\types\index.ts:328 - PaginationParams
\apps\frontend\src\types\index.ts:334 - FilterConfig (used in module)
\apps\frontend\src\types\index.ts:346 - HealthCheckResponse
\apps\frontend\src\types\index.ts:354 - ListResponse
\apps\frontend\src\types\repo-card.ts:12 - RepoCard
\apps\frontend\src\types\repo-card.ts:39 - RepoCardError (used in module)
\apps\frontend\src\types\repo-card.ts:52 - RepoCardAction
\apps\frontend\src\utils\auth-sw-register.ts:11 - ServiceWorkerHealth (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:1 - DebugSessionParticipantRole (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:24 - DebugSessionParticipant (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:31 - DebugStepEvent (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:39 - DebugRelayMessage (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:49 - DebugRelaySyncResult (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:74 - CreateDebugSessionInput (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:83 - UpdateDebugBreakpointsInput (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:88 - UpdateDebugVariablesInput (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:93 - RecordDebugStepInput (used in module)
\apps\frontend\src\utils\debugCollaboration.ts:99 - RelayDebugMessageInput (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:1 - MULTI_REPO_POLICY_SCHEMA_VERSION (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:4 - MultiRepoPolicySchemaVersion (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:6 - MultiRepoPolicyTier (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:8 - MultiRepoTelemetryLevel (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:10 - MultiRepoPolicyLimits (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:17 - MultiRepoPolicyDefinition (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:32 - MultiRepoPolicyRuntimeState (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:41 - MultiRepoPolicyIssue (used in module)
\apps\frontend\src\utils\multiRepoPolicy.ts:54 - MultiRepoPolicyAuditRecord (used in module)
\apps\frontend\src\utils\repoHomeData.ts:1 - RepoCardCiStatus (used in module)
\apps\frontend\src\utils\repoHomeData.ts:3 - RepoCardErrorCode (used in module)
\apps\frontend\src\utils\repoHomeData.ts:7 - RepoCardErrorHint (used in module)
\apps\frontend\src\utils\repoHomeData.ts:13 - RepoCardStatus (used in module)
\apps\frontend\src\utils\repoHomeData.ts:20 - RepoCardLinks (used in module)
\apps\frontend\src\utils\repoHomeData.ts:28 - RepoHomeCard (used in module)
\apps\frontend\src\utils\repoHomeData.ts:46 - RepoHomeActionPolicy (used in module)
\apps\frontend\src\utils\repoHomeData.ts:55 - RepoCardActionState (used in module)
\apps\frontend\src\utils\repoHomeData.ts:65 - REPO_HOME_CACHE_KEY (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:134 - fetchMonthlyCostReport (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:138 - fetchBudgetAlerts (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:142 - summarizeMonthlyCostReport (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:158 - normalizeBudgetAlerts (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:1 - ResourceCostTotals (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:8 - ResourceCostMetric (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:10 - MonthlyCostQuotaLike (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:22 - MonthlyCostReportLike (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:32 - BudgetAlertLike (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:51 - ResourceCostRollup (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:59 - ResourceBudgetAlert (used in module)
\apps\frontend\src\utils\resourceQuotaDashboard.ts:77 - ResourceCostDashboardSnapshot (used in module)
\apps\frontend\src\utils\richPresence.ts:20 - RichPresenceTeamSnapshot (used in module)
\apps\frontend\src\utils\richPresence.ts:26 - RichPresenceUpsertInput (used in module)
\apps\frontend\src\utils\session-sync.ts:28 - SessionSyncMetrics (used in module)
\apps\frontend\src\utils\session-sync.ts:39 - SessionMessage (used in module)
\apps\frontend\src\utils\symbolDiscussions.ts:5 - SymbolDiscussionCommentReaction (used in module)
\apps\frontend\src\utils\symbolDiscussions.ts:11 - SymbolDiscussionComment (used in module)
\apps\frontend\src\utils\symbolDiscussions.ts:23 - SymbolDiscussionThread (used in module)
\apps\frontend\src\utils\symbolDiscussions.ts:35 - SymbolDiscussion (used in module)
\apps\frontend\src\utils\symbolDiscussions.ts:47 - SymbolDiscussionLocationResult (used in module)
\apps\frontend\src\utils\voiceChannel.ts:94 - fetchVoiceSession
\apps\frontend\src\utils\voiceChannel.ts:5 - VoiceSessionStatus (used in module)
\apps\frontend\src\utils\voiceChannel.ts:18 - VoiceParticipant (used in module)
\apps\frontend\src\utils\voiceChannel.ts:38 - VoiceSessionCreateResponse (used in module)
\apps\frontend\src\utils\voiceChannel.ts:44 - VoiceSessionJoinResponse (used in module)
\apps\frontend\src\utils\voiceChannel.ts:46 - VoiceWorkspaceSessionsResponse (used in module)
\apps\frontend\src\utils\voiceChannel.ts:51 - VoiceSessionDetailsResponse (used in module)
\apps\frontend\src\utils\workspaceCatalog.ts:44 - scoreWorkspace
\apps\frontend\src\utils\workspaceCatalog.ts:10 - WorkspaceState (used in module)
\apps\frontend\src\utils\workspaceCatalog.ts:15 - RECENT_STORAGE_KEY (used in module)
\apps\frontend\src\utils\workspaceCatalog.ts:16 - WORKSPACE_STORAGE_KEY (used in module)
\apps\frontend\src\utils\workspaceCatalog.ts:17 - WORKSPACE_STATE_SYNC_EVENT (used in module)
\apps\frontend\src\utils\workspaceCatalog.ts:19 - PINNED_WORKSPACES (used in module)
\apps\frontend\src\utils\workspaceDiff.ts:5 - WorkspaceDiffFileStatus (used in module)
\apps\frontend\src\utils\workspaceDiff.ts:7 - WorkspaceDiffFile (used in module)
\apps\frontend\src\utils\workspaceProfiles.d.ts:49 - buildWorkspaceProfileSnapshot
\apps\frontend\src\utils\workspaceProfiles.d.ts:53 - getWorkspaceProfile
\apps\frontend\src\utils\workspaceProfiles.d.ts:57 - resolveWorkspaceRootProfile
\apps\frontend\src\utils\workspaceProfiles.d.ts:4 - WorkspaceDebuggerProfile (used in module)
\apps\frontend\src\utils\workspaceProfiles.d.ts:19 - WorkspaceRoot (used in module)
\apps\frontend\src\utils\workspaceProfiles.d.ts:27 - WorkspaceProfile (used in module)
\apps\frontend\src\utils\workspaceProfiles.d.ts:38 - WorkspaceProfileSnapshot (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:567 - readStoredWorkspaceTabs
\apps\frontend\src\utils\workspaceProfilesData.ts:585 - writeStoredWorkspaceTabs
\apps\frontend\src\utils\workspaceProfilesData.ts:594 - buildRecentWorkspaceIds
\apps\frontend\src\utils\workspaceProfilesData.ts:598 - getSuggestedWorkspaceId
\apps\frontend\src\utils\workspaceProfilesData.ts:615 - notifyWorkspaceTabsChanged
\apps\frontend\src\utils\workspaceProfilesData.ts:5 - WorkspaceDebuggerProfile (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:17 - WorkspaceTerminalProfile (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:33 - WorkspaceProfile (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:45 - WorkspaceProjectType (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:47 - WorkspaceAutoConfigSuggestion (used in module)
\apps\frontend\src\utils\workspaceProfilesData.ts:57 - WorkspaceProfileSnapshot (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:9 - WorkspaceRepoIdentity (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:14 - WorkspaceEditorState (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:19 - WorkspaceTerminalDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:27 - WorkspaceTaskDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:32 - WorkspaceDebugDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:63 - WORKSPACE_SESSION_SNAPSHOT_KEY (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:64 - WORKSPACE_RESTORE_PREFERENCES_KEY (used in module)
\apps\frontend\src\utils\workspaceTemplates.ts:5 - WorkspaceTemplateDefinition (used in module)
\apps\frontend\src\services\session-snapshot\storage.ts:12 - SNAPSHOT_DB_CONFIG (used in module)
\apps\frontend\src\services\session-snapshot\types.ts:112 - SnapshotListResponse
```
- FAIL: apps/extensions/agent-farm has unused exports

### apps/extensions/agent-farm ts-prune findings
```
\apps\extensions\agent-farm\src\extension.ts:10 - activate
\apps\extensions\agent-farm\src\extension.ts:136 - deactivate
\apps\extensions\agent-farm\src\types.ts:30 - CodeLocation (used in module)
\apps\extensions\agent-farm\src\types.ts:44 - TaskDefinition
\apps\extensions\agent-farm\src\agents\AdvancedSemanticSearchPhase4BAgent.ts:12 - AdvancedSemanticSearchPhase4BAgent
\apps\extensions\agent-farm\src\agents\MultiSiteFederationPhase12Agent.ts:16 - MultiSiteFederationRequest (used in module)
\apps\extensions\agent-farm\src\agents\MultiSiteFederationPhase12Agent.ts:22 - MultiSiteFederationResponse (used in module)
\apps\extensions\agent-farm\src\agents\MultiSiteFederationPhase12Agent.ts:31 - MultiSiteFederationPhase12Agent
\apps\extensions\agent-farm\src\agents\OnPremisesOptimizationPhase10Agent.ts:354 - default
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:7 - GitOpsConfig (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:18 - RepositorySource (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:27 - DeploymentTarget (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:38 - SyncPolicy (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:46 - HealthStatus (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:53 - ApplicationHealth (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:70 - SyncOperation (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:89 - GitOpsMetrics (used in module)
\apps\extensions\agent-farm\src\deployment\GitOpsOrchestrator.ts:103 - GitOpsOrchestrator
\apps\extensions\agent-farm\src\ml\CrossEncoderReranker.ts:7 - RankedResult (used in module)
\apps\extensions\agent-farm\src\ml\DistributedOperationOrchestrator.ts:7 - DistributedOperation (used in module)
\apps\extensions\agent-farm\src\ml\DistributedOperationOrchestrator.ts:351 - default
\apps\extensions\agent-farm\src\ml\EdgeOptimizationEngine.ts:319 - default
\apps\extensions\agent-farm\src\ml\MultiModalAnalyzer.ts:7 - MultiModalAnalysis (used in module)
\apps\extensions\agent-farm\src\ml\OfflineSyncManager.ts:6 - OperationType (used in module)
\apps\extensions\agent-farm\src\ml\OfflineSyncManager.ts:7 - SyncStatus (used in module)
\apps\extensions\agent-farm\src\ml\OfflineSyncManager.ts:339 - default
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:10 - GeographicRegion (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:21 - LatencyMeasurement (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:102 - LoadBalancingStrategy (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:107 - GlobalLoadBalancerMetrics (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:115 - GlobalLoadBalancer (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:216 - ReplicaSync (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:225 - MultiRegionReplicator (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:289 - FederationMember (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:298 - FederationTopology (used in module)
\apps\extensions\agent-farm\src\ml\phase12-geographic-distribution.ts:505 - Phase12Examples
\apps\extensions\agent-farm\src\ml\ResourceConstraintManager.ts:387 - default
\apps\extensions\agent-farm\src\phases\phase10\index.ts:6 - EdgeOptimizationEngine
\apps\extensions\agent-farm\src\phases\phase10\index.ts:7 - EdgeProfile
\apps\extensions\agent-farm\src\phases\phase10\index.ts:7 - CachePolicy
\apps\extensions\agent-farm\src\phases\phase10\index.ts:7 - CompressionStrategy
\apps\extensions\agent-farm\src\phases\phase10\index.ts:7 - OptimizationProfile
\apps\extensions\agent-farm\src\phases\phase10\index.ts:9 - OfflineSyncManager
\apps\extensions\agent-farm\src\phases\phase10\index.ts:10 - OfflineOperation
\apps\extensions\agent-farm\src\phases\phase10\index.ts:10 - SyncConflict
\apps\extensions\agent-farm\src\phases\phase10\index.ts:10 - SyncBatch
\apps\extensions\agent-farm\src\phases\phase10\index.ts:10 - SyncStatistics
\apps\extensions\agent-farm\src\phases\phase10\index.ts:12 - ResourceConstraintManager
\apps\extensions\agent-farm\src\phases\phase10\index.ts:13 - ResourceQuota
\apps\extensions\agent-farm\src\phases\phase10\index.ts:13 - ResourceUsage
\apps\extensions\agent-farm\src\phases\phase10\index.ts:13 - WorkloadPriority
\apps\extensions\agent-farm\src\phases\phase10\index.ts:13 - ResourceAllocation
\apps\extensions\agent-farm\src\phases\phase10\index.ts:15 - DistributedOperationOrchestrator
\apps\extensions\agent-farm\src\phases\phase10\index.ts:16 - MapTask
\apps\extensions\agent-farm\src\phases\phase10\index.ts:16 - ReduceTask
\apps\extensions\agent-farm\src\phases\phase10\index.ts:16 - TaskResult
\apps\extensions\agent-farm\src\phases\phase10\index.ts:16 - DistributedWorkflow
\apps\extensions\agent-farm\src\phases\phase10\index.ts:18 - OnPremisesOptimizationPhase10Agent
\apps\extensions\agent-farm\src\phases\phase10\index.ts:19 - OnPremisesDeploymentConfig
\apps\extensions\agent-farm\src\phases\phase10\index.ts:19 - EdgeDeploymentStatus
\apps\extensions\agent-farm\src\phases\phase10\index.ts:24 - Phase10Examples
\apps\extensions\agent-farm\src\phases\phase11\index.ts:6 - CircuitBreaker
\apps\extensions\agent-farm\src\phases\phase11\index.ts:7 - CircuitBreakerConfig
\apps\extensions\agent-farm\src\phases\phase11\index.ts:7 - CircuitBreakerMetrics
\apps\extensions\agent-farm\src\phases\phase11\index.ts:7 - CircuitState
\apps\extensions\agent-farm\src\phases\phase11\index.ts:19 - ChaosEngineer
\apps\extensions\agent-farm\src\phases\phase11\index.ts:20 - ChaosTest
\apps\extensions\agent-farm\src\phases\phase11\index.ts:20 - ChaosTestMetrics
\apps\extensions\agent-farm\src\phases\phase11\index.ts:20 - ChaosScenario
\apps\extensions\agent-farm\src\phases\phase11\index.ts:22 - ResiliencePhase11Agent
\apps\extensions\agent-farm\src\phases\phase11\index.ts:23 - ResilienceStatus
\apps\extensions\agent-farm\src\phases\phase11\index.ts:28 - Phase11Examples
\apps\extensions\agent-farm\src\phases\phase12\index.ts:23 - executePhase12
\apps\extensions\agent-farm\src\phases\phase12\index.ts:37 - validatePhase12Prerequisites
\apps\extensions\agent-farm\src\phases\phase12\index.ts:45 - rollbackPhase12
\apps\extensions\agent-farm\src\phases\phase12\index.ts:6 - Phase12Config (used in module)
\apps\extensions\agent-farm\src\phases\phase12\index.ts:13 - Phase12Result (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:9 - MetricPoint (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:15 - TraceSpan (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:28 - AlertRule (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:41 - MetricsAggregator (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:213 - DistributedTracing (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:388 - AnomalyDetection (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:456 - AlertManager (used in module)
\apps\extensions\agent-farm\src\phases\phase7\Phase7ObservabilityAgent.ts:557 - Phase7ObservabilityAgent
```

## Complexity Checks
- PASS: apps/frontend complexity <= 40
- PASS: apps/extensions/agent-farm complexity <= 10

## Suppression Hygiene
- FAIL: apps/frontend/src/extensions/symbol-discussions-panel.js:40 has unexplained eslint-disable

## TODO Hygiene
- FAIL: apps/agent-registry/billing.py:191 has TODO/FIXME/HACK without issue reference
- FAIL: apps/agent-registry/billing.py:221 has TODO/FIXME/HACK without issue reference
- FAIL: apps/agent-registry/main.py:356 has TODO/FIXME/HACK without issue reference
- FAIL: apps/agent-registry/main.py:357 has TODO/FIXME/HACK without issue reference
- FAIL: apps/agent-registry/main.py:358 has TODO/FIXME/HACK without issue reference
- FAIL: apps/agent-registry/packages.py:189 has TODO/FIXME/HACK without issue reference
- FAIL: apps/backend/src/services/mention-system/index.js:264 has TODO/FIXME/HACK without issue reference
- FAIL: apps/backend/src/services/mention-system/index.js:298 has TODO/FIXME/HACK without issue reference
- FAIL: apps/backend/src/services/standup-summaries/index.js:497 has TODO/FIXME/HACK without issue reference
- FAIL: apps/frontend/src/pages/UserManagement.js:26 has TODO/FIXME/HACK without issue reference
- FAIL: apps/frontend/src/pages/UserManagement.js:56 has TODO/FIXME/HACK without issue reference
- FAIL: apps/frontend/src/pages/UserManagement.tsx:46 has TODO/FIXME/HACK without issue reference
- FAIL: apps/frontend/src/pages/UserManagement.tsx:82 has TODO/FIXME/HACK without issue reference
- FAIL: apps/multimodal-ai/diagrams.py:23 has TODO/FIXME/HACK without issue reference
- FAIL: apps/multimodal-ai/image_analysis.py:26 has TODO/FIXME/HACK without issue reference
- FAIL: apps/multimodal-ai/voice.py:19 has TODO/FIXME/HACK without issue reference
- FAIL: apps/multimodal-ai/voice.py:33 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/anomaly_detector.py:126 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/anomaly_detector.py:144 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:131 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:138 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:194 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:231 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:337 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:338 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:339 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:340 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/main.py:350 has TODO/FIXME/HACK without issue reference
- FAIL: apps/self-healing/playbook_runner.py:223 has TODO/FIXME/HACK without issue reference

## Summary
- eslint_fail: 0
- unused_export_fail: 1
- complexity_fail: 0
- suppress_fail: 1
- todo_fail: 1
- total_failure_flags: 3
