#!/usr/bin/env node
/**
 * @file        scripts/integrations/sentry-error-analyzer.js
 * @module      integrations/sentry
 * @description AI-powered error analysis and fix suggestion using GitHub Copilot APIs
 */

const axios = require('axios');
const EventEmitter = require('events');

class SentryErrorAnalyzer extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.copilotToken = options.copilotToken || process.env.GITHUB_TOKEN;
        this.cache = options.cache !== false;
        this.cacheStore = new Map();
        this.cacheTTL = 60 * 60 * 1000; // 1 hour
        
        this.copilotAPIUrl = 'https://api.github.com/copilot_internal/completions';
        this.model = 'gpt-4-turbo';
    }
    
    /**
     * Generate a fix suggestion for an error
     */
    async generateFixSuggestion(errorContext) {
        const cacheKey = `fix:${errorContext.errorId}`;
        
        // Check cache
        if (this.cache && this.cacheStore.has(cacheKey)) {
            const cached = this.cacheStore.get(cacheKey);
            if (Date.now() - cached.timestamp < this.cacheTTL) {
                this.emit('cache-hit', { cacheKey });
                return cached.suggestion;
            }
            this.cacheStore.delete(cacheKey);
        }
        
        try {
            // Build context for Copilot
            const prompt = this._buildAnalysisPrompt(errorContext);
            
            // Call Copilot API
            const response = await axios.post(
                this.copilotAPIUrl,
                {
                    messages: [
                        {
                            role: 'system',
                            content: 'You are a code debugging expert. Analyze the error and provide a fix with explanation.'
                        },
                        {
                            role: 'user',
                            content: prompt
                        }
                    ],
                    model: this.model,
                    temperature: 0.5,
                    max_tokens: 1024
                },
                {
                    headers: {
                        'Authorization': `Bearer ${this.copilotToken}`,
                        'Accept': 'application/json',
                        'Content-Type': 'application/json',
                        'User-Agent': 'Sentry-Integration-Error-Analyzer/1.0'
                    },
                    timeout: 30000
                }
            );
            
            // Parse the response
            const analysisText = response.data.choices?.[0]?.message?.content || '';
            const suggestion = this._parseAnalysisResponse(analysisText, errorContext);
            
            // Determine confidence based on error type and context
            suggestion.confidence = this._calculateConfidence(errorContext, suggestion);
            
            // Cache the result
            if (this.cache) {
                this.cacheStore.set(cacheKey, {
                    suggestion,
                    timestamp: Date.now()
                });
            }
            
            this.emit('fix-generated', {
                errorId: errorContext.errorId,
                confidence: suggestion.confidence,
                hasCodeSnippet: !!suggestion.codeSnippet
            });
            
            return suggestion;
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to generate fix suggestion',
                error: error.message,
                errorId: errorContext.errorId
            });
            
            // Return a safe fallback
            return this._getFallbackSuggestion(errorContext, error);
        }
    }
    
    /**
     * Build analysis prompt for the error
     */
    _buildAnalysisPrompt(context) {
        const stackFrames = context.stackTrace
            .slice(0, 5)
            .map((frame, i) => `  ${i + 1}. ${frame.function} (${frame.filename}:${frame.lineNo})`)
            .join('\n');
        
        const sourceCode = context.sourceContext
            ?.map(ctx => {
                const lines = ctx.code
                    .map(line => `    ${line.lineNumber}: ${line.code}`)
                    .join('\n');
                return `${ctx.location.filename}:${ctx.location.lineNumber}\n${lines}`;
            })
            .join('\n\n') || 'No source context available';
        
        const breadcrumbs = context.breadcrumbs
            ?.slice(0, 3)
            .map(b => `  - ${b.category}: ${b.message} (${b.timestamp})`)
            .join('\n') || 'No breadcrumbs available';
        
        return `
Analyze this error and provide a fix:

**Error Type**: ${context.errorType}
**Error Message**: ${context.errorMessage}
**Severity**: ${context.level}

**Stack Trace** (top 5 frames):
${stackFrames}

**Source Code Context**:
${sourceCode}

**Breadcrumbs** (previous events):
${breadcrumbs}

**Related Release/Environment**: ${context.release || 'unknown'}

Please provide:
1. Root cause analysis
2. Recommended fix with code example
3. Explanation of why this fix works
4. Potential edge cases to consider
5. Unit test case to verify the fix
`;
    }
    
    /**
     * Parse the analysis response from Copilot
     */
    _parseAnalysisResponse(responseText, context) {
        const sections = {
            explanation: '',
            fix: '',
            codeSnippet: '',
            testCase: '',
            relatedDocs: []
        };
        
        // Extract sections using regex
        const explanationMatch = responseText.match(/root cause|analysis:?\s*([\s\S]*?)(?=recommended fix|fix|##|$)/i);
        if (explanationMatch) {
            sections.explanation = explanationMatch[1].trim().substring(0, 500);
        }
        
        const fixMatch = responseText.match(/recommended fix|fix:?\s*([\s\S]*?)(?=code|example|test|##|$)/i);
        if (fixMatch) {
            sections.fix = fixMatch[1].trim().substring(0, 300);
        }
        
        // Extract code snippet (typically in code blocks)
        const codeMatch = responseText.match(/```(?:javascript|js|typescript|ts)?\s*([\s\S]*?)```/);
        if (codeMatch) {
            sections.codeSnippet = codeMatch[1].trim().substring(0, 1000);
        }
        
        // Extract test case
        const testMatch = responseText.match(/test|unit test:?\s*([\s\S]*?)(?=##|edge|related|$)/i);
        if (testMatch) {
            sections.testCase = testMatch[1].trim().substring(0, 500);
        }
        
        // Common documentation links based on error type
        if (context.errorType?.includes('TypeError')) {
            sections.relatedDocs.push('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/TypeError');
        }
        if (context.errorType?.includes('ReferenceError')) {
            sections.relatedDocs.push('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/ReferenceError');
        }
        if (context.errorType?.includes('Promise')) {
            sections.relatedDocs.push('https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise');
        }
        
        return sections;
    }
    
    /**
     * Calculate confidence score for the fix
     */
    _calculateConfidence(context, suggestion) {
        let confidence = 0.5; // Base confidence
        
        // Increase confidence if we have good context
        if (context.sourceContext?.length > 0) confidence += 0.15;
        if (context.breadcrumbs?.length > 2) confidence += 0.1;
        if (suggestion.codeSnippet) confidence += 0.15;
        if (suggestion.testCase) confidence += 0.1;
        
        // Decrease confidence for generic errors
        if (context.errorMessage?.toLowerCase().includes('unknown')) confidence -= 0.1;
        if (!context.topFrame?.filename) confidence -= 0.15;
        
        return Math.min(Math.max(confidence, 0.1), 0.95); // Clamp 0.1-0.95
    }
    
    /**
     * Fallback suggestion when Copilot API fails
     */
    _getFallbackSuggestion(context, error) {
        return {
            explanation: `Error analysis is temporarily unavailable: ${error.message}. Check the error details and stack trace for more information.`,
            fix: 'Unable to generate automated fix suggestion. Please review the stack trace and error context manually.',
            codeSnippet: null,
            testCase: null,
            relatedDocs: [
                'https://sentry.io/docs/product/issues/',
                'https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error'
            ],
            confidence: 0.2
        };
    }
    
    /**
     * Analyze error trends
     */
    async analyzeErrorTrends(errors) {
        const trends = {
            mostCommon: [],
            byType: {},
            byLevel: {},
            temporalPattern: {}
        };
        
        errors.forEach(error => {
            // Group by type
            if (!trends.byType[error.type]) trends.byType[error.type] = 0;
            trends.byType[error.type]++;
            
            // Group by level
            if (!trends.byLevel[error.level]) trends.byLevel[error.level] = 0;
            trends.byLevel[error.level]++;
        });
        
        // Sort by frequency
        trends.mostCommon = Object.entries(trends.byType)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5)
            .map(([type, count]) => ({ type, count }));
        
        this.emit('trends-analyzed', { totalErrors: errors.length, uniqueTypes: Object.keys(trends.byType).length });
        
        return trends;
    }
    
    /**
     * Clear cache
     */
    clearCache() {
        this.cacheStore.clear();
        this.emit('cache-cleared');
    }
}

module.exports = SentryErrorAnalyzer;
