#!/usr/bin/env node
// @file        src/services/ephemeral-workspace-lifecycle/types.ts
// @module      workspace/lifecycle
// @description Ephemeral workspace container lifecycle types
//
/**
 * Workspace state machine
 */
export var WorkspaceLifecycleState;
(function (WorkspaceLifecycleState) {
    // Creation states
    WorkspaceLifecycleState["REQUESTED"] = "requested";
    WorkspaceLifecycleState["PROVISIONING"] = "provisioning";
    WorkspaceLifecycleState["SNAPSHOT_RESTORING"] = "snapshot_restoring";
    // Active states
    WorkspaceLifecycleState["READY"] = "ready";
    WorkspaceLifecycleState["CONNECTED"] = "connected";
    WorkspaceLifecycleState["IDLE"] = "idle";
    // Cleanup states
    WorkspaceLifecycleState["PAUSING"] = "pausing";
    WorkspaceLifecycleState["PAUSED"] = "paused";
    WorkspaceLifecycleState["TERMINATING"] = "terminating";
    WorkspaceLifecycleState["TERMINATED"] = "terminated";
    WorkspaceLifecycleState["FAILED"] = "failed";
})(WorkspaceLifecycleState || (WorkspaceLifecycleState = {}));
/**
 * Workspace lifecycle event types
 */
export var WorkspaceLifecycleEventType;
(function (WorkspaceLifecycleEventType) {
    WorkspaceLifecycleEventType["WORKSPACE_CREATED"] = "workspace_created";
    WorkspaceLifecycleEventType["WORKSPACE_READY"] = "workspace_ready";
    WorkspaceLifecycleEventType["WORKSPACE_CONNECTED"] = "workspace_connected";
    WorkspaceLifecycleEventType["WORKSPACE_IDLE"] = "workspace_idle";
    WorkspaceLifecycleEventType["WORKSPACE_PAUSED"] = "workspace_paused";
    WorkspaceLifecycleEventType["WORKSPACE_RESUMED"] = "workspace_resumed";
    WorkspaceLifecycleEventType["WORKSPACE_TERMINATED"] = "workspace_terminated";
    WorkspaceLifecycleEventType["WORKSPACE_EXPIRED"] = "workspace_expired";
    WorkspaceLifecycleEventType["WORKSPACE_FAILED"] = "workspace_failed";
    WorkspaceLifecycleEventType["WORKSPACE_HARD_DELETED"] = "workspace_hard_deleted";
    WorkspaceLifecycleEventType["WORKSPACE_HEADLESS_TESTS_STARTED"] = "workspace_headless_tests_started";
    WorkspaceLifecycleEventType["WORKSPACE_HEADLESS_TESTS_COMPLETED"] = "workspace_headless_tests_completed";
    WorkspaceLifecycleEventType["SNAPSHOT_CREATED"] = "snapshot_created";
    WorkspaceLifecycleEventType["SNAPSHOT_RESTORED"] = "snapshot_restored";
    WorkspaceLifecycleEventType["CLEANUP_INITIATED"] = "cleanup_initiated";
    WorkspaceLifecycleEventType["CLEANUP_COMPLETED"] = "cleanup_completed";
})(WorkspaceLifecycleEventType || (WorkspaceLifecycleEventType = {}));
//# sourceMappingURL=types.js.map