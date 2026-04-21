# Code Smell Audit Report

- Timestamp (UTC): 2026-04-21T12:18:22Z
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
apps/frontend/src/App.tsx:697 - App
apps/frontend/src/App.tsx:437 - WorkspaceStateHandle (used in module)
apps/frontend/src/hooks/index.ts:10 - useLogin
apps/frontend/src/hooks/index.ts:82 - useUserManagement
apps/frontend/src/hooks/index.ts:167 - useRepositoryAccess
apps/frontend/src/hooks/index.ts:214 - useAPITokens
apps/frontend/src/hooks/index.ts:274 - useSessions
apps/frontend/src/hooks/index.ts:323 - useEphemeralSessions
apps/frontend/src/store/index.ts:8 - useAuthStore
apps/frontend/src/store/index.ts:42 - useUserStore
apps/frontend/src/store/index.ts:79 - useRoleStore
apps/frontend/src/types/index.ts:8 - Organization (used in module)
apps/frontend/src/types/index.ts:15 - User (used in module)
apps/frontend/src/types/index.ts:27 - Role (used in module)
apps/frontend/src/types/index.ts:35 - UserRole (used in module)
apps/frontend/src/types/index.ts:44 - Team
apps/frontend/src/types/index.ts:52 - TeamMember
apps/frontend/src/types/index.ts:60 - Repository
apps/frontend/src/types/index.ts:68 - RepositoryAccess
apps/frontend/src/types/index.ts:78 - APIToken
apps/frontend/src/types/index.ts:87 - Session
apps/frontend/src/types/index.ts:98 - SessionLifecycleState (used in module)
apps/frontend/src/types/index.ts:100 - SessionQueueLane (used in module)
apps/frontend/src/types/index.ts:102 - SessionDataProfile (used in module)
apps/frontend/src/types/index.ts:104 - SessionProvenanceVerificationResult (used in module)
apps/frontend/src/types/index.ts:106 - SessionProvenanceManifest (used in module)
apps/frontend/src/types/index.ts:116 - EphemeralSession
apps/frontend/src/types/index.ts:144 - EphemeralSessionLaunchRequest
apps/frontend/src/types/index.ts:154 - SessionQueueSummary (used in module)
apps/frontend/src/types/index.ts:162 - EphemeralSessionStatus
apps/frontend/src/types/index.ts:178 - AuditLog
apps/frontend/src/types/index.ts:189 - Permission (used in module)
apps/frontend/src/types/index.ts:198 - LoginRequest
apps/frontend/src/types/index.ts:204 - LoginResponse
apps/frontend/src/types/index.ts:212 - MFAVerifyRequest
apps/frontend/src/types/index.ts:217 - MFAVerifyResponse
apps/frontend/src/types/index.ts:223 - MFASetupResponse
apps/frontend/src/types/index.ts:229 - CreateUserRequest
apps/frontend/src/types/index.ts:235 - UpdateUserRequest
apps/frontend/src/types/index.ts:240 - AssignRoleRequest
apps/frontend/src/types/index.ts:246 - GrantRepoAccessRequest
apps/frontend/src/types/index.ts:254 - CreateTokenRequest
apps/frontend/src/types/index.ts:260 - CreateTokenResponse
apps/frontend/src/types/index.ts:271 - AuthState
apps/frontend/src/types/index.ts:285 - UserState
apps/frontend/src/types/index.ts:299 - RoleState
apps/frontend/src/types/index.ts:308 - TableColumn
apps/frontend/src/types/index.ts:316 - PaginationParams
apps/frontend/src/types/index.ts:321 - FilterConfig (used in module)
apps/frontend/src/types/index.ts:332 - HealthCheckResponse
apps/frontend/src/types/index.ts:339 - ListResponse
apps/frontend/src/types/repo-card.ts:11 - RepoCard (used in module)
apps/frontend/src/types/repo-card.ts:38 - RepoCardError (used in module)
apps/frontend/src/types/repo-card.ts:51 - RepoCardAction (used in module)
apps/frontend/src/types/repo-card.ts:61 - RepoCardActionResult
apps/frontend/src/types/repo-card.ts:74 - HomeViewCache
apps/frontend/src/types/repo-card.ts:86 - HomeViewConfig
apps/frontend/src/utils/auth-sw-register.ts:11 - ServiceWorkerHealth (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:1 - MULTI_REPO_POLICY_SCHEMA_VERSION (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:4 - MultiRepoPolicySchemaVersion (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:6 - MultiRepoPolicyTier (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:8 - MultiRepoTelemetryLevel (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:10 - MultiRepoPolicyLimits (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:17 - MultiRepoPolicyDefinition (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:32 - MultiRepoPolicyRuntimeState (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:41 - MultiRepoPolicyIssue (used in module)
apps/frontend/src/utils/multiRepoPolicy.ts:54 - MultiRepoPolicyAuditRecord (used in module)
apps/frontend/src/utils/repoHomeData.ts:1 - RepoCardCiStatus (used in module)
apps/frontend/src/utils/repoHomeData.ts:3 - RepoCardErrorCode (used in module)
apps/frontend/src/utils/repoHomeData.ts:7 - RepoCardErrorHint (used in module)
apps/frontend/src/utils/repoHomeData.ts:13 - RepoCardStatus (used in module)
apps/frontend/src/utils/repoHomeData.ts:20 - RepoCardLinks (used in module)
apps/frontend/src/utils/repoHomeData.ts:27 - RepoHomeCard (used in module)
apps/frontend/src/utils/repoHomeData.ts:45 - RepoHomeActionPolicy (used in module)
apps/frontend/src/utils/repoHomeData.ts:54 - RepoCardActionState (used in module)
apps/frontend/src/utils/repoHomeData.ts:64 - REPO_HOME_CACHE_KEY (used in module)
apps/frontend/src/utils/session-keepalive.ts:144 - initSessionKeepalive
apps/frontend/src/utils/session-sync.ts:190 - broadcastRefresh
apps/frontend/src/utils/session-sync.ts:220 - broadcastExpiry
apps/frontend/src/utils/session-sync.ts:28 - SessionSyncMetrics (used in module)
apps/frontend/src/utils/session-sync.ts:39 - SessionMessage (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:9 - WorkspaceRepoIdentity (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:14 - WorkspaceEditorState (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:19 - WorkspaceTerminalDescriptor (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:27 - WorkspaceTaskDescriptor (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:32 - WorkspaceDebugDescriptor (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:63 - WORKSPACE_SESSION_SNAPSHOT_KEY (used in module)
apps/frontend/src/utils/workspaceSessionPersistence.ts:64 - WORKSPACE_RESTORE_PREFERENCES_KEY (used in module)
apps/frontend/src/utils/ws-session-handoff.ts:76 - setupWSAutoHandoff
```
- FAIL: apps/extensions/agent-farm has unused exports

### apps/extensions/agent-farm ts-prune findings
```
apps/extensions/agent-farm/src/extension.ts:9 - activate
apps/extensions/agent-farm/src/extension.ts:134 - deactivate
apps/extensions/agent-farm/src/types.ts:29 - CodeLocation (used in module)
apps/extensions/agent-farm/src/types.ts:42 - TaskDefinition
apps/extensions/agent-farm/src/agents/AdvancedSemanticSearchPhase4BAgent.ts:11 - AdvancedSemanticSearchPhase4BAgent
apps/extensions/agent-farm/src/agents/MultiSiteFederationPhase12Agent.ts:15 - MultiSiteFederationRequest (used in module)
apps/extensions/agent-farm/src/agents/MultiSiteFederationPhase12Agent.ts:21 - MultiSiteFederationResponse (used in module)
apps/extensions/agent-farm/src/agents/MultiSiteFederationPhase12Agent.ts:30 - MultiSiteFederationPhase12Agent
apps/extensions/agent-farm/src/agents/OnPremisesOptimizationPhase10Agent.ts:353 - default
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:6 - GitOpsConfig (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:17 - RepositorySource (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:26 - DeploymentTarget (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:37 - SyncPolicy (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:45 - HealthStatus (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:52 - ApplicationHealth (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:69 - SyncOperation (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:88 - GitOpsMetrics (used in module)
apps/extensions/agent-farm/src/deployment/GitOpsOrchestrator.ts:102 - GitOpsOrchestrator
apps/extensions/agent-farm/src/ml/CrossEncoderReranker.ts:6 - RankedResult (used in module)
apps/extensions/agent-farm/src/ml/DistributedOperationOrchestrator.ts:6 - DistributedOperation (used in module)
apps/extensions/agent-farm/src/ml/DistributedOperationOrchestrator.ts:350 - default
apps/extensions/agent-farm/src/ml/EdgeOptimizationEngine.ts:318 - default
apps/extensions/agent-farm/src/ml/FailoverManager.ts:6 - FailoverStrategy (used in module)
apps/extensions/agent-farm/src/ml/FailoverManager.ts:7 - FailoverTrigger (used in module)
apps/extensions/agent-farm/src/ml/FailoverManager.ts:9 - ReplicaHealth (used in module)
apps/extensions/agent-farm/src/ml/FailoverManager.ts:18 - FailoverEvent (used in module)
apps/extensions/agent-farm/src/ml/MultiModalAnalyzer.ts:6 - MultiModalAnalysis (used in module)
apps/extensions/agent-farm/src/ml/OfflineSyncManager.ts:6 - OperationType (used in module)
apps/extensions/agent-farm/src/ml/OfflineSyncManager.ts:7 - SyncStatus (used in module)
apps/extensions/agent-farm/src/ml/OfflineSyncManager.ts:339 - default
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:10 - GeographicRegion (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:21 - LatencyMeasurement (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:102 - LoadBalancingStrategy (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:107 - GlobalLoadBalancerMetrics (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:115 - GlobalLoadBalancer (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:216 - ReplicaSync (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:225 - MultiRegionReplicator (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:289 - FederationMember (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:298 - FederationTopology (used in module)
apps/extensions/agent-farm/src/ml/phase12-geographic-distribution.ts:505 - Phase12Examples
apps/extensions/agent-farm/src/ml/ResourceConstraintManager.ts:387 - default
apps/extensions/agent-farm/src/phases/phase10/index.ts:6 - EdgeOptimizationEngine
apps/extensions/agent-farm/src/phases/phase10/index.ts:7 - EdgeProfile
apps/extensions/agent-farm/src/phases/phase10/index.ts:7 - CachePolicy
apps/extensions/agent-farm/src/phases/phase10/index.ts:7 - CompressionStrategy
apps/extensions/agent-farm/src/phases/phase10/index.ts:7 - OptimizationProfile
apps/extensions/agent-farm/src/phases/phase10/index.ts:9 - OfflineSyncManager
apps/extensions/agent-farm/src/phases/phase10/index.ts:10 - OfflineOperation
apps/extensions/agent-farm/src/phases/phase10/index.ts:10 - SyncConflict
apps/extensions/agent-farm/src/phases/phase10/index.ts:10 - SyncBatch
apps/extensions/agent-farm/src/phases/phase10/index.ts:10 - SyncStatistics
apps/extensions/agent-farm/src/phases/phase10/index.ts:12 - ResourceConstraintManager
apps/extensions/agent-farm/src/phases/phase10/index.ts:13 - ResourceQuota
apps/extensions/agent-farm/src/phases/phase10/index.ts:13 - ResourceUsage
apps/extensions/agent-farm/src/phases/phase10/index.ts:13 - WorkloadPriority
apps/extensions/agent-farm/src/phases/phase10/index.ts:13 - ResourceAllocation
apps/extensions/agent-farm/src/phases/phase10/index.ts:15 - DistributedOperationOrchestrator
apps/extensions/agent-farm/src/phases/phase10/index.ts:16 - MapTask
apps/extensions/agent-farm/src/phases/phase10/index.ts:16 - ReduceTask
apps/extensions/agent-farm/src/phases/phase10/index.ts:16 - TaskResult
apps/extensions/agent-farm/src/phases/phase10/index.ts:16 - DistributedWorkflow
apps/extensions/agent-farm/src/phases/phase10/index.ts:18 - OnPremisesOptimizationPhase10Agent
apps/extensions/agent-farm/src/phases/phase10/index.ts:19 - OnPremisesDeploymentConfig
apps/extensions/agent-farm/src/phases/phase10/index.ts:19 - EdgeDeploymentStatus
apps/extensions/agent-farm/src/phases/phase10/index.ts:24 - Phase10Examples
apps/extensions/agent-farm/src/phases/phase11/index.ts:6 - CircuitBreaker
apps/extensions/agent-farm/src/phases/phase11/index.ts:7 - CircuitBreakerConfig
apps/extensions/agent-farm/src/phases/phase11/index.ts:7 - CircuitBreakerMetrics
apps/extensions/agent-farm/src/phases/phase11/index.ts:7 - CircuitState
apps/extensions/agent-farm/src/phases/phase11/index.ts:19 - ChaosEngineer
apps/extensions/agent-farm/src/phases/phase11/index.ts:20 - ChaosTest
apps/extensions/agent-farm/src/phases/phase11/index.ts:20 - ChaosTestMetrics
apps/extensions/agent-farm/src/phases/phase11/index.ts:20 - ChaosScenario
apps/extensions/agent-farm/src/phases/phase11/index.ts:22 - ResiliencePhase11Agent
apps/extensions/agent-farm/src/phases/phase11/index.ts:23 - ResilienceStatus
apps/extensions/agent-farm/src/phases/phase11/index.ts:28 - Phase11Examples
apps/extensions/agent-farm/src/phases/phase12/index.ts:23 - executePhase12
apps/extensions/agent-farm/src/phases/phase12/index.ts:37 - validatePhase12Prerequisites
apps/extensions/agent-farm/src/phases/phase12/index.ts:45 - rollbackPhase12
apps/extensions/agent-farm/src/phases/phase12/index.ts:6 - Phase12Config (used in module)
apps/extensions/agent-farm/src/phases/phase12/index.ts:13 - Phase12Result (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:9 - MetricPoint (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:15 - TraceSpan (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:28 - AlertRule (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:41 - MetricsAggregator (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:213 - DistributedTracing (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:388 - AnomalyDetection (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:456 - AlertManager (used in module)
apps/extensions/agent-farm/src/phases/phase7/Phase7ObservabilityAgent.ts:557 - Phase7ObservabilityAgent
```

## Complexity Checks
- PASS: apps/frontend complexity <= 40
- PASS: apps/extensions/agent-farm complexity <= 10

## Suppression Hygiene
- PASS: no unexplained eslint-disable/noqa markers

## TODO Hygiene
- FAIL: apps/extensions/agent-farm/src/phases/phase11/index.ts:9 has TODO/FIXME/HACK without issue reference

## Summary
- eslint_fail: 0
- unused_export_fail: 1
- complexity_fail: 0
- suppress_fail: 0
- todo_fail: 1
- total_failure_flags: 2
