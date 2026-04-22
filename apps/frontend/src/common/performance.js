/**
 * Performance profiling utilities for extensions
 * Provides hooks and utilities for measuring extension performance
 */
import { useEffect } from 'react';
const metrics = new Map();
/**
 * Hook to mount a performance profiler for an extension
 */
export function useExtensionMountProfiler(config) {
    useEffect(() => {
        const metric = {
            ...config,
            startTime: performance.now(),
        };
        metrics.set(config.id, metric);
        return () => {
            const m = metrics.get(config.id);
            if (m) {
                m.endTime = performance.now();
                m.duration = m.endTime - m.startTime;
            }
        };
    }, [config]);
}
/**
 * Measure an async operation
 */
export async function measureAsyncExtensionProfiler(config, fn) {
    const startTime = performance.now();
    const metric = {
        ...config,
        startTime,
    };
    try {
        const result = await fn();
        metric.endTime = performance.now();
        metric.duration = metric.endTime - metric.startTime;
        metrics.set(config.id, metric);
        return result;
    }
    catch (error) {
        metric.endTime = performance.now();
        metric.duration = metric.endTime - metric.startTime;
        metrics.set(config.id, metric);
        throw error;
    }
}
/**
 * Get all recorded metrics
 */
export function getAllMetrics() {
    return Array.from(metrics.values());
}
/**
 * Clear all metrics
 */
export function clearMetrics() {
    metrics.clear();
}
/**
 * Get metrics for a specific extension
 */
export function getMetricsForExtension(extensionId) {
    return Array.from(metrics.values()).filter((m) => m.id.startsWith(extensionId));
}
//# sourceMappingURL=performance.js.map