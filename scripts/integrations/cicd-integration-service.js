#!/usr/bin/env node
/**
 * @file        scripts/integrations/cicd-integration-service.js
 * @module      integrations/cicd
 * @description CI/CD pipeline monitoring service with GitHub Actions integration
 */

const axios = require('axios');
const EventEmitter = require('events');

class CICDIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.githubToken = options.githubToken || process.env.GITHUB_TOKEN;
        this.owner = options.owner || 'kushin77';
        this.repo = options.repo || 'code-server';
        this.apiUrl = 'https://api.github.com';
        
        this.cache = new Map();
        this.cacheTTL = 30 * 1000; // 30 seconds for live updates
        this.pollInterval = null;
        this.isPolling = false;
    }
    
    /**
     * Fetch workflow runs for the repository
     */
    async fetchWorkflowRuns(options = {}) {
        const {
            status = 'all', // all, completed, action_required, in_progress, queued
            limit = 20,
            branch = 'main'
        } = options;
        
        const cacheKey = `workflows:${status},${branch},${limit}`;
        
        // Check cache
        if (this.cache.has(cacheKey)) {
            const cached = this.cache.get(cacheKey);
            if (Date.now() - cached.timestamp < this.cacheTTL) {
                this.emit('cache-hit', { cacheKey });
                return cached.data;
            }
        }
        
        try {
            const response = await axios.get(
                `${this.apiUrl}/repos/${this.owner}/${this.repo}/actions/runs`,
                {
                    headers: {
                        'Authorization': `Bearer ${this.githubToken}`,
                        'Accept': 'application/vnd.github.v3+json'
                    },
                    params: {
                        status: status !== 'all' ? status : undefined,
                        head_branch: branch,
                        per_page: Math.min(limit, 100)
                    }
                }
            );
            
            const runs = response.data.workflow_runs.map(run => ({
                id: run.id,
                name: run.name,
                status: run.status, // queued, in_progress, completed
                conclusion: run.conclusion, // success, failure, neutral, cancelled, skipped, timed_out
                headBranch: run.head_branch,
                headCommit: run.head_commit?.sha,
                headCommitMessage: run.head_commit?.message,
                createdAt: run.created_at,
                updatedAt: run.updated_at,
                startedAt: run.run_started_at,
                triggeredBy: run.triggering_actor?.login,
                jobsUrl: run.jobs_url,
                logsUrl: run.logs_url,
                url: run.html_url,
                durationSeconds: run.run_number
            }));
            
            // Cache the results
            this.cache.set(cacheKey, {
                data: runs,
                timestamp: Date.now()
            });
            
            this.emit('workflows-fetched', { count: runs.length, status, branch });
            return runs;
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to fetch workflow runs',
                error: error.message,
                status: error.response?.status
            });
            throw error;
        }
    }
    
    /**
     * Fetch jobs for a workflow run
     */
    async fetchJobsForRun(runId) {
        const cacheKey = `jobs:${runId}`;
        
        if (this.cache.has(cacheKey)) {
            const cached = this.cache.get(cacheKey);
            if (Date.now() - cached.timestamp < this.cacheTTL) {
                return cached.data;
            }
        }
        
        try {
            const response = await axios.get(
                `${this.apiUrl}/repos/${this.owner}/${this.repo}/actions/runs/${runId}/jobs`,
                {
                    headers: {
                        'Authorization': `Bearer ${this.githubToken}`,
                        'Accept': 'application/vnd.github.v3+json'
                    }
                }
            );
            
            const jobs = response.data.jobs.map(job => ({
                id: job.id,
                name: job.name,
                status: job.status,
                conclusion: job.conclusion,
                startedAt: job.started_at,
                completedAt: job.completed_at,
                runnerName: job.runner_name,
                logsUrl: job.logs_url,
                url: job.html_url,
                steps: (job.steps || []).map(step => ({
                    name: step.name,
                    status: step.status,
                    conclusion: step.conclusion,
                    number: step.number
                }))
            }));
            
            this.cache.set(cacheKey, {
                data: jobs,
                timestamp: Date.now()
            });
            
            this.emit('jobs-fetched', { runId, count: jobs.length });
            return jobs;
            
        } catch (error) {
            this.emit('error', {
                message: `Failed to fetch jobs for run ${runId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Fetch logs for a job
     */
    async fetchJobLogs(runId, jobId) {
        try {
            const response = await axios.get(
                `${this.apiUrl}/repos/${this.owner}/${this.repo}/actions/jobs/${jobId}/logs`,
                {
                    headers: {
                        'Authorization': `Bearer ${this.githubToken}`,
                        'Accept': 'application/vnd.github.v3+json'
                    }
                }
            );
            
            // Parse log format: [timestamp] log line
            const logLines = response.data.split('\n').map((line, index) => ({
                lineNumber: index + 1,
                timestamp: this._extractTimestamp(line),
                content: line,
                level: this._detectLogLevel(line)
            }));
            
            this.emit('logs-fetched', { jobId, lineCount: logLines.length });
            return logLines;
            
        } catch (error) {
            this.emit('error', {
                message: `Failed to fetch logs for job ${jobId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Trigger a workflow run
     */
    async triggerWorkflow(workflowId, inputs = {}) {
        try {
            const response = await axios.post(
                `${this.apiUrl}/repos/${this.owner}/${this.repo}/actions/workflows/${workflowId}/dispatches`,
                {
                    ref: 'main',
                    inputs
                },
                {
                    headers: {
                        'Authorization': `Bearer ${this.githubToken}`,
                        'Accept': 'application/vnd.github.v3+json'
                    }
                }
            );
            
            this.emit('workflow-triggered', { workflowId });
            return { status: 'triggered' };
            
        } catch (error) {
            this.emit('error', {
                message: `Failed to trigger workflow ${workflowId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Re-run a failed workflow
     */
    async reRunWorkflow(runId) {
        try {
            await axios.post(
                `${this.apiUrl}/repos/${this.owner}/${this.repo}/actions/runs/${runId}/rerun`,
                {},
                {
                    headers: {
                        'Authorization': `Bearer ${this.githubToken}`,
                        'Accept': 'application/vnd.github.v3+json'
                    }
                }
            );
            
            this.emit('workflow-rerun', { runId });
            return { status: 'rerun' };
            
        } catch (error) {
            this.emit('error', {
                message: `Failed to re-run workflow ${runId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Build a DAG (Directed Acyclic Graph) of jobs
     */
    async buildJobDAG(runId) {
        try {
            const jobs = await this.fetchJobsForRun(runId);
            
            const dag = {
                nodes: jobs.map(job => ({
                    id: job.id,
                    label: job.name,
                    status: job.status,
                    conclusion: job.conclusion
                })),
                edges: [] // Would need to parse job dependencies from GitHub API
            };
            
            this.emit('dag-built', { runId, nodeCount: dag.nodes.length });
            return dag;
            
        } catch (error) {
            this.emit('error', {
                message: `Failed to build DAG for run ${runId}`,
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Start polling for updates
     */
    startPolling(intervalSeconds = 30) {
        if (this.isPolling) return;
        
        this.isPolling = true;
        this.pollInterval = setInterval(async () => {
            try {
                const runs = await this.fetchWorkflowRuns({ limit: 5 });
                this.emit('poll-update', { runs, timestamp: Date.now() });
            } catch (error) {
                console.error('[CI/CD] Poll update error:', error.message);
            }
        }, intervalSeconds * 1000);
        
        this.emit('polling-started', { intervalSeconds });
    }
    
    /**
     * Stop polling
     */
    stopPolling() {
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
            this.isPolling = false;
            this.emit('polling-stopped');
        }
    }
    
    /**
     * Extract timestamp from log line
     */
    _extractTimestamp(line) {
        const match = line.match(/^\[(\d{4}-\d{2}-\d{2}T[\d:\.Z+-]+)\]/);
        return match ? match[1] : null;
    }
    
    /**
     * Detect log level from content
     */
    _detectLogLevel(line) {
        if (line.includes('ERROR') || line.includes('✗') || line.includes('FAILED')) return 'error';
        if (line.includes('WARN') || line.includes('WARNING')) return 'warn';
        if (line.includes('✓') || line.includes('SUCCESS')) return 'success';
        return 'info';
    }
    
    /**
     * Clear cache
     */
    clearCache() {
        this.cache.clear();
        this.emit('cache-cleared');
    }
}

module.exports = CICDIntegrationService;
