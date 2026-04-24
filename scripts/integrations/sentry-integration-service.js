#!/usr/bin/env node
/**
 * @file        scripts/integrations/sentry-integration-service.js
 * @module      integrations/sentry
 * @description Sentry SDK service for error fetching, processing, and AI-powered suggestions
 */

const axios = require('axios');
const EventEmitter = require('events');

class SentryIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.authToken = options.authToken || process.env.SENTRY_AUTH_TOKEN;
        this.orgSlug = options.orgSlug || process.env.SENTRY_ORG_SLUG;
        this.projectSlugs = (options.projectSlugs || process.env.SENTRY_PROJECT_SLUG || '').split(',').filter(Boolean);
        this.dsn = options.dsn || process.env.SENTRY_DSN;
        
        this.apiUrl = 'https://sentry.io/api/0';
        this.cache = new Map();
        this.cacheExpiry = 5 * 60 * 1000; // 5 minutes
        
        if (!this.authToken || !this.orgSlug) {
            console.warn('[Sentry] Warning: Missing SENTRY_AUTH_TOKEN or SENTRY_ORG_SLUG environment variables');
        }
    }
    
    /**
     * Fetch recent errors from Sentry
     */
    async fetchErrors(options = {}) {
        const {
            limit = 50,
            offset = 0,
            projects = this.projectSlugs,
            environment = 'production',
            minLevel = 'error'
        } = options;
        
        const cacheKey = `errors:${projects.join(',')},${environment},${minLevel},${limit},${offset}`;
        
        // Check cache
        if (this.cache.has(cacheKey)) {
            const cached = this.cache.get(cacheKey);
            if (Date.now() - cached.timestamp < this.cacheExpiry) {
                this.emit('cache-hit', { cacheKey, errorCount: cached.data.length });
                return cached.data;
            }
            this.cache.delete(cacheKey);
        }
        
        try {
            const errors = [];
            
            for (const project of projects) {
                const query = [
                    `level:[${minLevel}:fatal]`,
                    `environment:${environment}`,
                    'status:unresolved'
                ].join(' ');
                
                const response = await axios.get(
                    `${this.apiUrl}/projects/${this.orgSlug}/${project}/events/`,
                    {
                        headers: {
                            'Authorization': `Bearer ${this.authToken}`,
                            'Accept': 'application/json'
                        },
                        params: {
                            query,
                            limit,
                            offset,
                            sort: '-timestamp'
                        }
                    }
                );
                
                const processedErrors = response.data.map(event => ({
                    id: event.id || event.eventID,
                    title: event.title || event.message?.formatted || 'Unknown Error',
                    level: event.level || 'error',
                    type: event.type,
                    culprit: event.culprit,
                    timestamp: event.dateCreated,
                    count: event.stats?.['24h']?.[0]?.[1] || 1,
                    stackTrace: event.entries?.find(e => e.type === 'exception')?.data?.values?.[0]?.stacktrace?.frames || [],
                    exception: event.entries?.find(e => e.type === 'exception')?.data?.values?.[0],
                    breadcrumbs: event.entries?.find(e => e.type === 'breadcrumbs')?.data?.values || [],
                    rawEvent: event
                }));
                
                errors.push(...processedErrors);
            }
            
            // Cache the results
            this.cache.set(cacheKey, {
                data: errors,
                timestamp: Date.now()
            });
            
            this.emit('errors-fetched', { count: errors.length, projects });
            return errors;
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to fetch errors from Sentry',
                error: error.message,
                details: error.response?.data
            });
            throw error;
        }
    }
    
    /**
     * Fetch detailed error information
     */
    async getErrorDetails(projectSlug, eventId) {
        try {
            const response = await axios.get(
                `${this.apiUrl}/projects/${this.orgSlug}/${projectSlug}/events/${eventId}/`,
                {
                    headers: {
                        'Authorization': `Bearer ${this.authToken}`,
                        'Accept': 'application/json'
                    }
                }
            );
            
            const event = response.data;
            const exception = event.entries?.find(e => e.type === 'exception')?.data?.values?.[0];
            
            return {
                id: event.id,
                title: event.title,
                message: event.message?.formatted,
                level: event.level,
                culprit: event.culprit,
                timestamp: event.dateCreated,
                url: event.url,
                stackTrace: exception?.stacktrace?.frames || [],
                exception: exception,
                breadcrumbs: event.entries?.find(e => e.type === 'breadcrumbs')?.data?.values || [],
                userFeedback: event.userFeedback || [],
                tags: event.tags || {},
                context: event.contexts || {},
                request: event.request,
                release: event.release
            };
        } catch (error) {
            this.emit('error', {
                message: `Failed to fetch error details for ${eventId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Resolve an error in Sentry
     */
    async resolveError(projectSlug, groupId, resolution = 'fixed') {
        try {
            const response = await axios.put(
                `${this.apiUrl}/issues/${groupId}/`,
                { status: resolution },
                {
                    headers: {
                        'Authorization': `Bearer ${this.authToken}`,
                        'Accept': 'application/json',
                        'Content-Type': 'application/json'
                    }
                }
            );
            
            this.emit('error-resolved', {
                groupId,
                status: response.data.status
            });
            
            return { status: response.data.status };
        } catch (error) {
            this.emit('error', {
                message: `Failed to resolve error ${groupId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Extract source location from stack frame
     */
    extractSourceLocation(frame) {
        return {
            filename: frame.filename,
            function: frame.function,
            module: frame.module,
            lineNumber: frame.lineNo,
            columnNumber: frame.colNo,
            context: frame.context || [],
            vars: frame.vars || {},
            package: frame.package,
            platform: frame.platform
        };
    }
    
    /**
     * Get relevant source code context from stack frames
     */
    async getSourceContext(stackTrace, projectPath = './') {
        const contexts = [];
        
        for (const frame of stackTrace.slice(0, 3)) { // Top 3 frames
            const location = this.extractSourceLocation(frame);
            
            contexts.push({
                location,
                code: frame.context?.map(line => ({
                    lineNumber: line[0],
                    code: line[1],
                    isErrorLine: line[0] === frame.lineNo
                })) || []
            });
        }
        
        return contexts;
    }
    
    /**
     * Prepare error context for AI analysis
     */
    async prepareAIContext(error, stackTrace) {
        const topFrame = stackTrace[0];
        const context = await this.getSourceContext(stackTrace);
        
        return {
            errorId: error.id,
            errorMessage: error.title || error.message,
            errorType: error.type || 'Error',
            level: error.level,
            stackTrace: stackTrace.map(f => ({
                function: f.function,
                filename: f.filename,
                lineNo: f.lineNo,
                context: f.context
            })),
            topFrame: {
                filename: topFrame?.filename,
                function: topFrame?.function,
                lineNo: topFrame?.lineNo
            },
            sourceContext: context,
            breadcrumbs: error.breadcrumbs?.slice(0, 5) || [],
            tags: error.tags || {},
            release: error.release
        };
    }
    
    /**
     * Clear cache
     */
    clearCache() {
        this.cache.clear();
        this.emit('cache-cleared');
    }
}

module.exports = SentryIntegrationService;
