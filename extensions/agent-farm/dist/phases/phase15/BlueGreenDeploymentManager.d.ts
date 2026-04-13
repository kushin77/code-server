/**
 * Phase 15: Blue-Green Deployment Manager
 * Simultaneous environment management for zero-downtime deployments
 */
export interface EnvironmentState {
    name: 'blue' | 'green';
    version: string;
    status: 'preparing' | 'ready' | 'active' | 'draining' | 'offline';
    deployment: {
        startTime: Date;
        readyTime?: Date;
        activeTime?: Date;
        completionTime?: Date;
    };
    metrics: EnvironmentMetrics;
}
export interface EnvironmentMetrics {
    health: 'healthy' | 'degraded' | 'critical';
    activeConnections: number;
    requestsPerSecond: number;
    errorRate: number;
    p99Latency: number;
    cpuUsage: number;
    memoryUsage: number;
}
export interface BlueGreenStatus {
    activeEnvironment: 'blue' | 'green';
    blue: EnvironmentState;
    green: EnvironmentState;
    trafficDistribution: {
        blue: number;
        green: number;
    };
    lastSwitch: Date;
    switchInProgress: boolean;
}
export interface ValidationResult {
    valid: boolean;
    errors: string[];
    warnings: string[];
}
export interface SmokeTestResults {
    passed: boolean;
    testCount: number;
    passedCount: number;
    failedCount: number;
    duration: number;
    errors: string[];
}
export interface TrafficShiftResult {
    success: boolean;
    sourceEnvironment: 'blue' | 'green';
    targetEnvironment: 'blue' | 'green';
    trafficShifted: number;
    duration: number;
}
export interface EnvironmentComparison {
    latencyDifference: number;
    errorRateDifference: number;
    throughputDifference: number;
    healthComparison: string;
}
export declare class BlueGreenDeploymentManager {
    private blueEnvironment;
    private greenEnvironment;
    private activeEnvironment;
    private trafficDistribution;
    private lastSwitchTime;
    constructor();
    prepareBlueEnvironment(): Promise<EnvironmentState>;
    prepareGreenEnvironment(version: string): Promise<EnvironmentState>;
    validateNewEnvironment(env: EnvironmentState): Promise<ValidationResult>;
    runSmokeTests(env: EnvironmentState): Promise<SmokeTestResults>;
    shiftTrafficToGreen(percentage: number): Promise<TrafficShiftResult>;
    completeTrafficSwitch(): Promise<void>;
    shiftTrafficBackToBlue(): Promise<TrafficShiftResult>;
    drainBlueEnvironment(): Promise<void>;
    cleanupOldEnvironment(): Promise<void>;
    compareEnvironments(blue: EnvironmentState, green: EnvironmentState): Promise<EnvironmentComparison>;
    getBlueGreenStatus(): BlueGreenStatus;
    getEnvironmentMetrics(env: 'blue' | 'green'): EnvironmentMetrics;
    private initializeEnvironment;
}
//# sourceMappingURL=BlueGreenDeploymentManager.d.ts.map