#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/types.ts
// @module      collaboration/readiness-indicator
// @description Type definitions for ReadinessIndicatorService
// @owner       collab-services
// @status      active
/**
 * Readiness level for team member availability
 */
export var ReadinessLevel;
(function (ReadinessLevel) {
    ReadinessLevel["AVAILABLE"] = "available";
    ReadinessLevel["BUSY"] = "busy";
    ReadinessLevel["AWAY"] = "away";
    ReadinessLevel["OFFLINE"] = "offline";
    ReadinessLevel["DND"] = "dnd";
})(ReadinessLevel || (ReadinessLevel = {}));
/**
 * Type of availability signal
 */
export var SignalType;
(function (SignalType) {
    SignalType["PRESENCE"] = "presence";
    SignalType["ACTIVITY"] = "activity";
    SignalType["CALENDAR"] = "calendar";
    SignalType["CAPACITY"] = "capacity";
    SignalType["HISTORY"] = "history";
})(SignalType || (SignalType = {}));
//# sourceMappingURL=types.js.map