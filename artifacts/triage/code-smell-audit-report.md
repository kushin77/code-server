# Code Smell Audit Report

- Timestamp (UTC): 2026-04-21T12:50:44Z
- Strict mode: 1
- Run ESLint checks: 1
- Run unused-export checks: 1
- Run complexity checks: 1
- Frontend complexity max threshold: 40
- Agent farm complexity max threshold: 10

## ESLint Strict Mode
- PASS: apps/frontend eslint strict check
- FAIL: apps/extensions/agent-farm eslint strict check

## Unused Export Checks
- FAIL: apps/frontend has unused exports

### apps/frontend ts-prune findings
```
\apps\frontend\src\App.tsx:720 - App
\apps\frontend\src\App.tsx:417 - WorkspaceStateHandle (used in module)
\apps\frontend\src\hooks\index.ts:20 - useLogin
\apps\frontend\src\hooks\index.ts:93 - useUserManagement
\apps\frontend\src\hooks\index.ts:179 - useRepositoryAccess
\apps\frontend\src\hooks\index.ts:227 - useAPITokens
\apps\frontend\src\hooks\index.ts:288 - useSessions
\apps\frontend\src\hooks\index.ts:338 - useEphemeralSessions
\apps\frontend\src\store\index.ts:9 - useAuthStore
\apps\frontend\src\store\index.ts:44 - useUserStore
\apps\frontend\src\store\index.ts:82 - useRoleStore
\apps\frontend\src\types\index.ts:15 - Organization (used in module)
\apps\frontend\src\types\index.ts:22 - User (used in module)
\apps\frontend\src\types\index.ts:34 - Role (used in module)
\apps\frontend\src\types\index.ts:42 - UserRole (used in module)
\apps\frontend\src\types\index.ts:52 - RepositoryAccess
\apps\frontend\src\types\index.ts:63 - APIToken
\apps\frontend\src\types\index.ts:73 - Session
\apps\frontend\src\types\index.ts:84 - SessionLifecycleState (used in module)
\apps\frontend\src\types\index.ts:86 - SessionQueueLane (used in module)
\apps\frontend\src\types\index.ts:88 - SessionDataProfile (used in module)
\apps\frontend\src\types\index.ts:90 - SessionProvenanceVerificationResult (used in module)
\apps\frontend\src\types\index.ts:92 - SessionProvenanceManifest (used in module)
\apps\frontend\src\types\index.ts:103 - EphemeralSession
\apps\frontend\src\types\index.ts:132 - EphemeralSessionLaunchRequest
\apps\frontend\src\types\index.ts:142 - SessionQueueSummary (used in module)
\apps\frontend\src\types\index.ts:151 - EphemeralSessionStatus
\apps\frontend\src\types\index.ts:168 - AuditLog
\apps\frontend\src\types\index.ts:179 - Permission (used in module)
\apps\frontend\src\types\index.ts:189 - LoginRequest
\apps\frontend\src\types\index.ts:196 - LoginResponse
\apps\frontend\src\types\index.ts:205 - MFAVerifyRequest
\apps\frontend\src\types\index.ts:211 - MFAVerifyResponse
\apps\frontend\src\types\index.ts:218 - MFASetupResponse
\apps\frontend\src\types\index.ts:225 - CreateUserRequest
\apps\frontend\src\types\index.ts:232 - UpdateUserRequest
\apps\frontend\src\types\index.ts:238 - AssignRoleRequest
\apps\frontend\src\types\index.ts:245 - GrantRepoAccessRequest
\apps\frontend\src\types\index.ts:254 - CreateTokenRequest
\apps\frontend\src\types\index.ts:261 - CreateTokenResponse
\apps\frontend\src\types\index.ts:273 - AuthState
\apps\frontend\src\types\index.ts:288 - UserState
\apps\frontend\src\types\index.ts:303 - RoleState
\apps\frontend\src\types\index.ts:313 - TableColumn
\apps\frontend\src\types\index.ts:322 - PaginationParams
\apps\frontend\src\types\index.ts:328 - FilterConfig (used in module)
\apps\frontend\src\types\index.ts:340 - HealthCheckResponse
\apps\frontend\src\types\index.ts:348 - ListResponse
\apps\frontend\src\types\repo-card.ts:12 - RepoCard
\apps\frontend\src\types\repo-card.ts:39 - RepoCardError (used in module)
\apps\frontend\src\types\repo-card.ts:52 - RepoCardAction
\apps\frontend\src\utils\auth-sw-register.ts:11 - ServiceWorkerHealth (used in module)
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
\apps\frontend\src\utils\repoHomeData.ts:27 - RepoHomeCard (used in module)
\apps\frontend\src\utils\repoHomeData.ts:45 - RepoHomeActionPolicy (used in module)
\apps\frontend\src\utils\repoHomeData.ts:54 - RepoCardActionState (used in module)
\apps\frontend\src\utils\repoHomeData.ts:64 - REPO_HOME_CACHE_KEY (used in module)
\apps\frontend\src\utils\session-sync.ts:28 - SessionSyncMetrics (used in module)
\apps\frontend\src\utils\session-sync.ts:39 - SessionMessage (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:9 - WorkspaceRepoIdentity (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:14 - WorkspaceEditorState (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:19 - WorkspaceTerminalDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:27 - WorkspaceTaskDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:32 - WorkspaceDebugDescriptor (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:63 - WORKSPACE_SESSION_SNAPSHOT_KEY (used in module)
\apps\frontend\src\utils\workspaceSessionPersistence.ts:64 - WORKSPACE_RESTORE_PREFERENCES_KEY (used in module)
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
- PASS: no unexplained eslint-disable/noqa markers

## TODO Hygiene
- PASS: TODO/FIXME/HACK markers are issue-linked or absent

## Summary
- eslint_fail: 1
- unused_export_fail: 1
- complexity_fail: 0
- suppress_fail: 0
- todo_fail: 0
- total_failure_flags: 2
