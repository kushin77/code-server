#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization-engine/types.ts
// @module      collaboration/communication-optimization-engine
// @description Type definitions for communication optimization service
// @owner       collab-services
// @status      active
/**
 * Communication mode enumeration
 */
export var CommunicationMode;
(function (CommunicationMode) {
    CommunicationMode["ASYNC_COMMENT"] = "async_comment";
    CommunicationMode["SYNC_DM"] = "sync_dm";
    CommunicationMode["SYNC_MENTION"] = "sync_mention";
    CommunicationMode["CALL_MEETING"] = "call_meeting";
    CommunicationMode["SUMMARY_DIGEST"] = "summary_digest";
    CommunicationMode["DEFERRED"] = "deferred";
})(CommunicationMode || (CommunicationMode = {}));
/**
 * Communication channel enumeration
 */
export var CommunicationChannel;
(function (CommunicationChannel) {
    CommunicationChannel["IN_APP"] = "in_app";
    CommunicationChannel["EMAIL"] = "email";
    CommunicationChannel["SLACK"] = "slack";
    CommunicationChannel["PUSH"] = "push";
    CommunicationChannel["DIGEST"] = "digest";
})(CommunicationChannel || (CommunicationChannel = {}));
/**
 * Communication urgency enumeration
 */
export var CommunicationUrgency;
(function (CommunicationUrgency) {
    CommunicationUrgency["CRITICAL"] = "critical";
    CommunicationUrgency["HIGH"] = "high";
    CommunicationUrgency["NORMAL"] = "normal";
    CommunicationUrgency["LOW"] = "low";
})(CommunicationUrgency || (CommunicationUrgency = {}));
/**
 * Recommendation reason codes
 */
export var DecisionReason;
(function (DecisionReason) {
    DecisionReason["USER_UNAVAILABLE"] = "user_unavailable";
    DecisionReason["FOCUS_TIME"] = "focus_time";
    DecisionReason["DND_ACTIVE"] = "dnd_active";
    DecisionReason["TIMEZONE_MISMATCH"] = "timezone_mismatch";
    DecisionReason["BATCH_ELIGIBLE"] = "batch_eligible";
    DecisionReason["ESCALATION_REQUIRED"] = "escalation_required";
    DecisionReason["ASYNC_PREFERRED"] = "async_preferred";
    DecisionReason["SYNC_JUSTIFIED"] = "sync_justified";
    DecisionReason["ALREADY_NOTIFIED"] = "already_notified";
    DecisionReason["DISCUSSION_ONGOING"] = "discussion_ongoing";
    DecisionReason["MEETING_SCHEDULED"] = "meeting_scheduled";
    DecisionReason["OPTIMAL_TIMING"] = "optimal_timing";
})(DecisionReason || (DecisionReason = {}));
//# sourceMappingURL=types.js.map