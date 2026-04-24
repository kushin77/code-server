/**
 * Phase 12.2: Data Replication & Sync Layer
 * Type definitions for CRDT-based replication protocol
 */
/**
 * Operation types in the replication system
 */
export var OperationType;
(function (OperationType) {
    OperationType["CREATE"] = "create";
    OperationType["UPDATE"] = "update";
    OperationType["DELETE"] = "delete";
    OperationType["MERGE"] = "merge";
})(OperationType || (OperationType = {}));
//# sourceMappingURL=types.js.map