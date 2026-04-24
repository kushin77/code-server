#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/types.ts
// @module      collaboration/activity-stream/types
// @description Type definitions for ActivityStreamService
// @owner       collab-6.2
// @status      active
/**
 * Enumeration of activity types
 */
export var ActivityType;
(function (ActivityType) {
    ActivityType["CODE_CHANGE"] = "code_change";
    ActivityType["COLLABORATION"] = "collaboration";
    ActivityType["DECISION"] = "decision";
    ActivityType["SYSTEM_EVENT"] = "system_event";
    ActivityType["COMMENT"] = "comment";
    ActivityType["REVIEW"] = "review";
    ActivityType["MERGE"] = "merge";
    ActivityType["DEPLOYMENT"] = "deployment";
    ActivityType["MEETING"] = "meeting";
    ActivityType["MENTION"] = "mention";
})(ActivityType || (ActivityType = {}));
//# sourceMappingURL=types.js.map