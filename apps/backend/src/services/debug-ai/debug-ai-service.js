/**
 * @file        apps/backend/src/services/debug-ai/debug-ai-service.ts
 * @module      ai/debug-session
 * @description Debug session AI analysis service
 */
import { EventEmitter } from 'events';
/**
 * DebugAIService: Analyze debug sessions with AI
 */
export class DebugAIService extends EventEmitter {
    constructor() {
        super(...arguments);
        this.isInitialized = false;
        this.sessions = new Map();
        this.sessionHistory = new Map();
        this.analyses = new Map();
        this.feedback = new Map();
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[DebugAIService] Initialized');
        this.emit('initialized');
    }
    /**
     * Start debug session
     */
    async startSession(sessionId, workspaceId, language, runtime) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = {
            sessionId,
            workspaceId,
            createdAt: Date.now(),
            isPaused: false,
            stackTrace: [],
            variables: [],
            breakpoints: [],
            output: [],
            language,
            runtime,
        };
        this.sessions.set(sessionId, session);
        this.sessionHistory.set(sessionId, []);
        console.log(`[DebugAIService] Started session ${sessionId} (${language})`);
        this.emit('session-started', { sessionId, language, runtime });
    }
    /**
     * Update session state on pause
     */
    async updateOnPause(sessionId, reason, stackTrace, variables) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        // Save to history
        const history = this.sessionHistory.get(sessionId) || [];
        history.push({ ...session });
        this.sessionHistory.set(sessionId, history);
        // Update current state
        session.isPaused = true;
        session.pauseReason = reason;
        session.pausedAt = Date.now();
        session.stackTrace = stackTrace;
        session.variables = variables;
        console.log(`[DebugAIService] Paused session ${sessionId} due to ${reason}`);
        this.emit('session-paused', {
            sessionId,
            reason,
            frameCount: stackTrace.length,
        });
    }
    /**
     * Update session state on resume
     */
    async updateOnResume(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        session.isPaused = false;
        console.log(`[DebugAIService] Resumed session ${sessionId}`);
        this.emit('session-resumed', { sessionId });
    }
    /**
     * Add output to session
     */
    async addOutput(sessionId, category, output, source) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        session.output.push({
            category,
            output,
            source,
        });
    }
    /**
     * Analyze current debug state with AI
     */
    async analyzeDebugState(sessionId, relevantCode) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        const history = this.sessionHistory.get(sessionId) || [];
        const context = {
            state: session,
            history,
            relevantCode: relevantCode
                ? {
                    filePath: relevantCode.filePath,
                    content: relevantCode.content,
                    startLine: relevantCode.startLine,
                    endLine: relevantCode.startLine + relevantCode.content.split('\n').length,
                    lineNumber: relevantCode.startLine,
                }
                : undefined,
        };
        // Simulate AI analysis
        const analysis = await this.performAnalysis(sessionId, context);
        const analysisId = `analysis-${sessionId}-${Date.now()}`;
        const result = {
            sessionId,
            analysisId,
            timestamp: Date.now(),
            suspectedCause: {
                confidence: analysis.confidence,
                description: analysis.cause,
                evidence: analysis.evidence,
            },
            suggestedFixes: analysis.fixes,
            relevantDocs: analysis.docs,
            variableAnalysis: analysis.variableAnalysis,
            commonPatterns: analysis.patterns,
            suggestedNextSteps: analysis.nextSteps,
            model: 'gpt-4',
            processingTime: Math.random() * 2000 + 500, // Simulated 500-2500ms
        };
        this.analyses.set(analysisId, result);
        console.log(`[DebugAIService] Analyzed session ${sessionId}: ${result.suspectedCause.description}`);
        this.emit('analysis-complete', { sessionId, analysisId });
        return analysisId;
    }
    /**
     * Simulate AI analysis (in production, call actual LLM)
     */
    async performAnalysis(sessionId, context) {
        const state = context.state;
        // Analyze variables for null/undefined
        const variables = state.variables;
        const suspiciousVariables = variables
            .filter((v) => v.value === 'undefined' || v.value === 'null')
            .map((v) => ({
            name: v.name,
            reason: `Variable is ${v.value}`,
            suggestedValues: undefined,
        }));
        // Detect common error patterns
        const errorOutput = state.output.find((o) => o.category === 'stderr');
        const cause = errorOutput
            ? errorOutput.output.substring(0, 100)
            : suspiciousVariables.length > 0
                ? `Uninitialized variables: ${suspiciousVariables.map((v) => v.name).join(', ')}`
                : 'Logic error or unexpected state transition';
        return {
            confidence: suspiciousVariables.length > 0 ? 0.85 : 0.6,
            cause,
            evidence: [
                ...suspiciousVariables.map((v) => `${v.name} is undefined`),
                errorOutput ? `Error in stderr: ${errorOutput.output.substring(0, 50)}` : '',
            ].filter(Boolean),
            fixes: [
                {
                    title: 'Add null checks',
                    description: 'Guard against undefined/null values',
                    difficulty: 'easy',
                    estimatedTime: 5,
                },
                {
                    title: 'Review initialization order',
                    description: 'Ensure variables are initialized before use',
                    difficulty: 'medium',
                    estimatedTime: 10,
                },
            ],
            docs: [
                {
                    title: 'TypeScript Strict Null Checks',
                    url: 'https://www.typescriptlang.org/docs/handbook/2/narrowing.html',
                    relevance: 0.9,
                },
            ],
            variableAnalysis: {
                suspiciousVariables,
                uninitializedVariables: suspiciousVariables.map((v) => v.name),
                unexpectedTypes: [],
            },
            patterns: [
                {
                    pattern: 'Null reference',
                    frequency: suspiciousVariables.length,
                    hasOccurred: suspiciousVariables.length > 0,
                    fix: 'Add !== null checks',
                },
            ],
            nextSteps: [
                'Check variable initialization in current scope',
                'Add console.log to trace variable values',
                'Step into function to see execution flow',
            ],
        };
    }
    /**
     * Get analysis result
     */
    async getAnalysis(analysisId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.analyses.get(analysisId) || null;
    }
    /**
     * Get session state
     */
    async getSession(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.sessions.get(sessionId) || null;
    }
    /**
     * Get session history
     */
    async getSessionHistory(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.sessionHistory.get(sessionId) || [];
    }
    /**
     * Submit feedback on analysis
     */
    async submitFeedback(analysisId, sessionId, userId, helpfulness, accuracy, correctDiagnosis, comment) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const feedbackId = `feedback-${analysisId}-${Date.now()}`;
        const fb = {
            analysisId,
            sessionId,
            timestamp: Date.now(),
            userId,
            helpfulness,
            accuracy,
            correctDiagnosis,
            appliedSuggestions: 0,
            comment,
            needsFurtherHelp: accuracy < 3,
        };
        this.feedback.set(feedbackId, fb);
        console.log(`[DebugAIService] Received feedback for analysis ${analysisId}`);
        this.emit('feedback-received', fb);
    }
    /**
     * Get statistics
     */
    async getStatistics(workspaceId) {
        const sessions = Array.from(this.sessions.values()).filter((s) => s.workspaceId === workspaceId);
        const allAnalyses = Array.from(this.analyses.values()).filter((a) => sessions.some((s) => s.sessionId === a.sessionId));
        const stats = {
            totalSessions: sessions.length,
            activeSessions: sessions.filter((s) => s.isPaused).length,
            averageSessionDuration: 0,
            analysisRuns: allAnalyses.length,
            suggestedFixesGenerated: allAnalyses.reduce((sum, a) => sum + a.suggestedFixes.length, 0),
            fixesApplied: 0,
            applyRate: 0,
            averageResolutionTime: 0,
            commonCauses: {},
            byLanguage: {},
            byPauseReason: {},
        };
        // Count by language
        for (const session of sessions) {
            stats.byLanguage[session.language] =
                (stats.byLanguage[session.language] || 0) + 1;
            if (session.pauseReason) {
                stats.byPauseReason[session.pauseReason] =
                    (stats.byPauseReason[session.pauseReason] || 0) + 1;
            }
        }
        // Count causes
        for (const analysis of allAnalyses) {
            const cause = analysis.suspectedCause.description.substring(0, 50);
            stats.commonCauses[cause] = (stats.commonCauses[cause] || 0) + 1;
        }
        // Calculate average session duration
        if (sessions.length > 0) {
            const durations = sessions
                .map((s) => (s.pausedAt || Date.now()) - s.createdAt)
                .filter((d) => d > 0);
            if (durations.length > 0) {
                stats.averageSessionDuration =
                    durations.reduce((a, b) => a + b, 0) / durations.length;
            }
        }
        // Count feedback
        const allFeedback = Array.from(this.feedback.values());
        const sessionFeedback = allFeedback.filter((f) => sessions.some((s) => s.sessionId === f.sessionId));
        if (sessionFeedback.length > 0) {
            stats.fixesApplied = sessionFeedback.reduce((sum, f) => sum + f.appliedSuggestions, 0);
            stats.applyRate =
                stats.suggestedFixesGenerated > 0
                    ? (stats.fixesApplied / stats.suggestedFixesGenerated) * 100
                    : 0;
        }
        return stats;
    }
    /**
     * End session
     */
    async endSession(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        console.log(`[DebugAIService] Ended session ${sessionId}`);
        this.emit('session-ended', { sessionId, duration: Date.now() - session.createdAt });
    }
    /**
     * Get suggestions for current pause
     */
    async getSuggestions(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const session = this.sessions.get(sessionId);
        if (!session)
            throw new Error(`Session ${sessionId} not found`);
        if (!session.isPaused)
            return [];
        // Return generic suggestions based on pause reason
        const suggestions = {
            breakpoint: [
                'Inspect variables in current scope',
                'Check stack trace for unexpected calls',
                'Use conditional breakpoint to narrow down',
            ],
            exception: [
                'Check error message and stack trace',
                'Look for null/undefined values',
                'Verify function arguments',
            ],
            step: [
                'Step into function to debug',
                'Check variable values after statement',
                'Review function implementation',
            ],
        };
        return suggestions[session.pauseReason || 'step'] || [];
    }
}
/**
 * Global service instance
 */
let serviceInstance = null;
/**
 * Get global service instance
 */
export async function getDebugAIService() {
    if (!serviceInstance) {
        serviceInstance = new DebugAIService();
        await serviceInstance.initialize();
    }
    return serviceInstance;
}
//# sourceMappingURL=debug-ai-service.js.map