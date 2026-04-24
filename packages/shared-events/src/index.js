/**
 * @file        packages/shared-events/src/index.ts
 * @module      shared-events
 * @description Canonical Event Schema and standardized interfaces for cross-service communication
 * @owner       architecture-team
 * @status      active
 */
/**
 * Utility: Event Validation Helper
 */
export function isValidEvent(event) {
    return (typeof event === 'object' &&
        typeof event.id === 'string' &&
        typeof event.source === 'string' &&
        typeof event.type === 'string' &&
        ['collaboration', 'ai', 'infrastructure', 'security', 'presence', 'system'].includes(event.category) &&
        ['low', 'medium', 'high', 'critical'].includes(event.severity) &&
        (typeof event.timestamp === 'number' || typeof event.timestamp === 'string') &&
        typeof event.payload === 'object');
}
//# sourceMappingURL=index.js.map