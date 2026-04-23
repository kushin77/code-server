#!/usr/bin/env node
// @file        apps/backend/src/services/debugging/debug-session-ai-service.ts
// @module      services/debugging
// @description AI-powered debugging service with root cause analysis and fix suggestions
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
const logger = getLogger('DebugSessionAIService');
/**
 * Debug Session AI Service
 * Provides AI-powered debugging with root cause analysis and fix suggestions
 */
class DebugSessionAIService extends EventEmitter {
    constructor() {
        super();
        this.sessions = new Map();
    }
    static getInstance() {
        if (!DebugSessionAIService.instance) {
            DebugSessionAIService.instance = new DebugSessionAIService();
        }
        return DebugSessionAIService.instance;
    }
    /**
     * Reset all sessions (for testing)
     */
    reset() {
        this.sessions.clear();
    }
    /**
     * Start a new debug session
     */
    startSession(userId, workspaceId, sessionId, type) {
        const debugSessionId = `ds-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const session = {
            id: debugSessionId,
            userId,
            workspaceId,
            sessionId,
            type,
            state: 'running',
            breakpoints: new Map(),
            variables: [],
            stackFrames: [],
            fixSuggestions: [],
            startedAt: Date.now(),
            issueHistory: [],
        };
        this.sessions.set(debugSessionId, session);
        logger.info(`Started debug session ${debugSessionId} for user ${userId}`);
        this.emit('sessionStarted', session);
        return session;
    }
    /**
     * Stop a debug session
     */
    stopSession(debugSessionId) {
        const session = this.sessions.get(debugSessionId);
        if (session) {
            session.state = 'stopped';
            session.stoppedAt = Date.now();
            this.emit('sessionStopped', session);
            logger.info(`Stopped debug session ${debugSessionId}`);
        }
        return session;
    }
    /**
     * Get a debug session
     */
    getSession(debugSessionId) {
        return this.sessions.get(debugSessionId);
    }
    /**
     * List all active debug sessions for a workspace
     */
    listSessions(workspaceId) {
        return Array.from(this.sessions.values()).filter((s) => s.workspaceId === workspaceId && s.state !== 'stopped');
    }
    /**
     * Add or update a breakpoint in a session
     */
    setBreakpoint(debugSessionId, breakpoint) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return undefined;
        session.breakpoints.set(breakpoint.id, breakpoint);
        this.emit('breakpointSet', session, breakpoint);
        logger.info(`Set breakpoint ${breakpoint.id} at ${breakpoint.file}:${breakpoint.line}`);
        return session;
    }
    /**
     * Remove a breakpoint from a session
     */
    removeBreakpoint(debugSessionId, breakpointId) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return undefined;
        session.breakpoints.delete(breakpointId);
        this.emit('breakpointRemoved', session, breakpointId);
        logger.info(`Removed breakpoint ${breakpointId}`);
        return session;
    }
    /**
     * Update session state (pause/resume)
     */
    updateSessionState(debugSessionId, state) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return undefined;
        session.state = state;
        this.emit('sessionStateChanged', session, state);
        logger.info(`Debug session ${debugSessionId} state changed to ${state}`);
        return session;
    }
    /**
     * Capture current variables at a breakpoint
     */
    captureVariables(debugSessionId, breakpointId, variables) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return undefined;
        const breakpoint = session.breakpoints.get(breakpointId);
        if (!breakpoint)
            return undefined;
        session.variables = variables;
        session.currentBreakpoint = breakpoint;
        // Record in history
        session.issueHistory.push({
            timestamp: Date.now(),
            breakpoint,
            variables,
        });
        // Limit history to last 100 items
        if (session.issueHistory.length > 100) {
            session.issueHistory.shift();
        }
        this.emit('variablesCaptured', session, variables);
        logger.info(`Captured ${variables.length} variables at breakpoint ${breakpointId}`);
        return session;
    }
    /**
     * Capture stack frames
     */
    captureStackFrames(debugSessionId, stackFrames) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return undefined;
        session.stackFrames = stackFrames;
        this.emit('stackFramesCaptured', session, stackFrames);
        logger.info(`Captured ${stackFrames.length} stack frames`);
        return session;
    }
    /**
     * Analyze root cause of a debugging issue
     */
    analyzeRootCause(debugSessionId) {
        const session = this.sessions.get(debugSessionId);
        if (!session || !session.currentBreakpoint)
            return undefined;
        const breakpoint = session.currentBreakpoint;
        const variables = session.variables;
        const stackFrames = session.stackFrames;
        // Simulate AI analysis
        const likely = [];
        const evidence = [];
        // Check for null/undefined values
        const nullVars = variables.filter((v) => v.value === 'null' || v.value === 'undefined');
        if (nullVars.length > 0) {
            likely.push('Null/undefined reference exception');
            evidence.push(`Found ${nullVars.length} null/undefined variables: ${nullVars.map((v) => v.name).join(', ')}`);
        }
        // Check for type mismatches
        const typeMismatches = variables.filter((v) => v.type.toLowerCase().includes('any') || v.type.toLowerCase().includes('unknown'));
        if (typeMismatches.length > 0) {
            likely.push('Type mismatch or unexpected type');
            evidence.push(`Found ${typeMismatches.length} variables with unknown/any types`);
        }
        // Check for out-of-bounds or invalid values
        const invalidVars = variables.filter((v) => v.value.includes('Error') || v.value.includes('error'));
        if (invalidVars.length > 0) {
            likely.push('Invalid value or range error');
            evidence.push(`Found ${invalidVars.length} variables containing error messages`);
        }
        // Check stack depth
        if (stackFrames.length > 50) {
            likely.push('Stack overflow or infinite recursion');
            evidence.push(`Stack depth is ${stackFrames.length}, indicating potential recursion`);
        }
        // Check for repeated breakpoints
        const sameLineHits = session.issueHistory.filter((h) => h.breakpoint.file === breakpoint.file && h.breakpoint.line === breakpoint.line);
        if (sameLineHits.length > 5) {
            likely.push('Infinite loop or repeated exception');
            evidence.push(`This breakpoint has been hit ${sameLineHits.length} times in this session`);
        }
        const stackTrace = stackFrames.map((f) => `at ${f.name} (${f.file}:${f.line}:${f.column || 0})`).join('\n');
        const analysis = {
            likely: likely.length > 0 ? likely : ['Unknown error (insufficient data for analysis)'],
            confidence: Math.min(100, likely.length * 25),
            evidence,
            stackTrace,
            affectedVariables: nullVars.length > 0 ? nullVars : invalidVars,
        };
        session.rootCauseAnalysis = analysis;
        session.lastAnalyzedAt = Date.now();
        this.emit('rootCauseAnalyzed', session, analysis);
        logger.info(`Analyzed root cause at ${breakpoint.file}:${breakpoint.line}`);
        return analysis;
    }
    /**
     * Generate fix suggestions based on analysis
     */
    generateFixSuggestions(debugSessionId) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return [];
        const suggestions = [];
        if (!session.rootCauseAnalysis) {
            this.analyzeRootCause(debugSessionId);
        }
        const analysis = session.rootCauseAnalysis;
        if (!analysis)
            return [];
        // Generate suggestions based on root cause analysis
        analysis.likely.forEach((cause) => {
            if (cause.includes('Null')) {
                suggestions.push({
                    approach: 'Add null checks',
                    description: 'Add null/undefined guards before accessing the variable',
                    severity: 'high',
                    codeSnippet: 'if (variable != null) { /* use variable */ }',
                    relatedDocs: ['https://nodejs.org/docs/optional-chaining', 'https://docs.microsoft.com/nullish-coalescing'],
                });
            }
            if (cause.includes('Type')) {
                suggestions.push({
                    approach: 'Add type validation',
                    description: 'Validate the type before using the variable',
                    severity: 'high',
                    codeSnippet: 'if (typeof variable === "expected-type") { /* use variable */ }',
                    relatedDocs: ['https://www.typescriptlang.org/docs/handbook/type-guards.html'],
                });
            }
            if (cause.includes('Stack overflow')) {
                suggestions.push({
                    approach: 'Review recursion logic',
                    description: 'Check for infinite recursion or add depth limit',
                    severity: 'critical',
                    codeSnippet: 'if (depth > MAX_DEPTH) { return; } /* recursive call */',
                    relatedDocs: ['https://stackoverflow.com/questions/tagged/recursion', 'https://en.wikipedia.org/wiki/Tail_call'],
                });
            }
            if (cause.includes('Infinite loop')) {
                suggestions.push({
                    approach: 'Add loop termination condition',
                    description: 'Ensure loop has proper exit condition',
                    severity: 'critical',
                    codeSnippet: 'for (let i = 0; i < MAX; i++) { /* ensure i increments */ }',
                    relatedDocs: ['https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Loops_and_iteration'],
                });
            }
            if (cause.includes('Range error')) {
                suggestions.push({
                    approach: 'Validate array/string bounds',
                    description: 'Add bounds checking before accessing array/string elements',
                    severity: 'high',
                    codeSnippet: 'if (index >= 0 && index < array.length) { const val = array[index]; }',
                    relatedDocs: ['https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array'],
                });
            }
        });
        // Add generic suggestions
        if (suggestions.length === 0) {
            suggestions.push({
                approach: 'Add debug logging',
                description: 'Add console.log or debugger statements to trace execution',
                severity: 'low',
                codeSnippet: 'console.log("Variable:", variable);',
                relatedDocs: ['https://nodejs.org/docs/latest/api/debugger.html'],
            });
        }
        session.fixSuggestions = suggestions;
        this.emit('fixSuggestionsGenerated', session, suggestions);
        logger.info(`Generated ${suggestions.length} fix suggestions`);
        return suggestions;
    }
    /**
     * Get relevant documentation based on error patterns
     */
    getRelevantDocs(debugSessionId) {
        const session = this.sessions.get(debugSessionId);
        if (!session)
            return [];
        const docs = new Set();
        if (session.rootCauseAnalysis) {
            session.rootCauseAnalysis.likely.forEach((cause) => {
                if (cause.includes('Null')) {
                    docs.add('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Nullish_coalescing_operator');
                    docs.add('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Optional_chaining');
                }
                if (cause.includes('Type')) {
                    docs.add('https://www.typescriptlang.org/docs/handbook/type-checking-javascript-files.html');
                    docs.add('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Typed_arrays');
                }
                if (cause.includes('Stack')) {
                    docs.add('https://nodejs.org/docs/latest/api/process.html#process_process_maxlisteners');
                    docs.add('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Stack');
                }
            });
        }
        session.fixSuggestions.forEach((suggestion) => {
            if (suggestion.relatedDocs) {
                suggestion.relatedDocs.forEach((doc) => docs.add(doc));
            }
        });
        return Array.from(docs);
    }
    /**
     * Get session statistics
     */
    getStatistics() {
        const allSessions = Array.from(this.sessions.values());
        const activeSessions = allSessions.filter((s) => s.state === 'running' || s.state === 'paused');
        const totalDuration = allSessions.reduce((sum, s) => {
            const duration = (s.stoppedAt || Date.now()) - s.startedAt;
            return sum + duration;
        }, 0);
        const avgDuration = allSessions.length > 0 ? totalDuration / allSessions.length : 0;
        const totalBreakpointHits = allSessions.reduce((sum, s) => sum + s.breakpoints.size, 0);
        const avgHits = allSessions.length > 0 ? totalBreakpointHits / allSessions.length : 0;
        const languageCounts = new Map();
        allSessions.forEach((s) => {
            languageCounts.set(s.type, (languageCounts.get(s.type) || 0) + 1);
        });
        let mostCommon = 'unknown';
        let maxCount = 0;
        languageCounts.forEach((count, lang) => {
            if (count > maxCount) {
                maxCount = count;
                mostCommon = lang;
            }
        });
        return {
            totalSessions: allSessions.length,
            activeSessions: activeSessions.length,
            averageSessionDuration: avgDuration,
            averageBreakpointHits: avgHits,
            mostCommonLanguage: mostCommon,
        };
    }
}
const instance = new DebugSessionAIService();
export default instance;
export { DebugSessionAIService };
//# sourceMappingURL=debug-session-ai-service.js.map