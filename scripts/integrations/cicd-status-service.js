#!/usr/bin/env node
/**
 * @file        scripts/integrations/cicd-status-service.js
 * @module      integrations/cicd
 * @description CI/CD pipeline status tracking with immutable job state and idempotent updates
 *
 * IaC Principles:
 * - Immutable: Pipeline runs are versioned, jobs frozen after completion
 * - Idempotent: Status updates safe to retry without side effects
 * - Versioned: All state changes tracked with timestamps
 */

const EventEmitter = require('events');

class CICDStatusService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.gitHubToken = options.gitHubToken || process.env.GITHUB_TOKEN;
        this.owner = options.owner || 'kushin77';
        this.repo = options.repo || 'code-server';
        
        // Immutable run storage (versioned)
        this.runs = new Map(); // runId → frozen run object
        this.jobs = new Map(); // jobId → frozen job object
        this.logs = new Map(); // jobId → log lines (immutable array)
        
        // Idempotent update tracking
        this.updateTokens = new Map(); // updateId → processed timestamp
    }
    
    /**
     * Register workflow run (immutable, idempotent)
     * Same run registered multiple times = same result
     */
    registerWorkflowRun(runData) {
        const runId = `${this.owner}/${this.repo}/${runData.id}`;
        
        // Idempotent: if already registered, return existing
        if (this.runs.has(runId)) {
            return this.runs.get(runId);
        }
        
        const run = {
            // Immutable identifiers
            id: runData.id,
            name: runData.name,
            headBranch: runData.head_branch,
            headSha: runData.head_sha,
            
            // Immutable workflow definition
            workflowId: runData.workflow_id,
            workflowFile: runData.path,
            
            // Event classification (immutable)
            event: runData.event,
            eventTimestamp: runData.created_at,
            triggeredBy: runData.actor?.login,
            
            // Mutable state (updated idempotently)
            status: runData.status,
            conclusion: runData.conclusion,
            
            // Timestamps
            createdAt: runData.created_at,
            updatedAt: runData.updated_at,
            runStartedAt: runData.run_started_at,
            
            // Run metadata
            jobs: [],
            jobsCount: 0,
            version: 1, // Version for idempotent updates
        };
        
        // Freeze immutable fields
        Object.freeze(run);
        this.runs.set(runId, run);
        
        this.emit('run-registered', run);
        return run;
    }
    
    /**
     * Update job status (idempotent with version control)
     */
    updateJobStatus(jobData, updateToken) {
        const jobId = jobData.id;
        const updateId = updateToken || `${jobId}-${jobData.updated_at}`;
        
        // Idempotent: if already processed, return existing
        if (this.updateTokens.has(updateId)) {
            return this.jobs.get(jobId);
        }
        
        const job = {
            // Immutable identifiers
            id: jobData.id,
            runId: jobData.run_id,
            workflowJobId: jobData.workflow_job?.id,
            
            // Immutable job definition
            name: jobData.name,
            stepCount: jobData.steps?.length || 0,
            
            // Mutable state
            status: jobData.status,
            conclusion: jobData.conclusion,
            
            // Timestamps
            startedAt: jobData.started_at,
            completedAt: jobData.completed_at,
            createdAt: jobData.created_at,
            
            // Duration
            duration: this.calculateDuration(jobData.started_at, jobData.completed_at),
            
            // Steps (immutable once job completes)
            steps: this.processSteps(jobData.steps || []),
            
            // Failure info (immutable once set)
            failureReason: jobData.failure_reason,
            failureMessage: null,
            
            // Version for idempotent updates
            version: 1,
            lastUpdated: new Date().toISOString(),
        };
        
        // Freeze immutable fields
        Object.freeze(job);
        this.jobs.set(jobId, job);
        
        // Mark update as processed
        this.updateTokens.set(updateId, new Date().toISOString());
        
        this.emit('job-updated', job);
        return job;
    }
    
    /**
     * Process job steps (immutable)
     */
    processSteps(steps) {
        return Object.freeze(
            steps.map(step => ({
                number: step.number,
                name: step.name,
                status: step.status,
                conclusion: step.conclusion,
                startedAt: step.started_at,
                completedAt: step.completed_at,
                duration: this.calculateDuration(step.started_at, step.completed_at),
            }))
        );
    }
    
    /**
     * Calculate duration in seconds
     */
    calculateDuration(startedAt, completedAt) {
        if (!startedAt || !completedAt) return null;
        
        const start = new Date(startedAt).getTime();
        const end = new Date(completedAt).getTime();
        
        return Math.max(0, Math.round((end - start) / 1000));
    }
    
    /**
     * Append log lines (immutable array)
     */
    appendLogs(jobId, newLines) {
        const existingLogs = this.logs.get(jobId) || [];
        
        // Create new immutable array
        const updatedLogs = [
            ...existingLogs,
            ...newLines.map((line, index) => ({
                lineNumber: existingLogs.length + index + 1,
                timestamp: new Date().toISOString(),
                content: line,
            })),
        ];
        
        // Freeze for immutability
        Object.freeze(updatedLogs);
        this.logs.set(jobId, updatedLogs);
        
        this.emit('logs-appended', { jobId, lineCount: updatedLogs.length });
        return updatedLogs;
    }
    
    /**
     * Get job logs (immutable snapshot)
     */
    getJobLogs(jobId, fromLine = 0, toLine = null) {
        const logs = this.logs.get(jobId) || [];
        
        const end = toLine || logs.length;
        const slice = logs.slice(fromLine, end);
        
        // Return immutable snapshot
        return Object.freeze({
            jobId,
            total: logs.length,
            fromLine,
            toLine: end,
            lines: Object.freeze(slice.map(l => l.content)),
            metadata: Object.freeze({
                firstTimestamp: slice[0]?.timestamp,
                lastTimestamp: slice[slice.length - 1]?.timestamp,
            }),
        });
    }
    
    /**
     * Build pipeline DAG (immutable, versioned)
     */
    buildPipelineDAG(runId) {
        const run = this.runs.get(runId);
        if (!run) return null;
        
        // Collect all jobs for this run
        const runJobs = Array.from(this.jobs.values())
            .filter(job => job.runId === run.id);
        
        // Build dependency graph
        const jobsByName = new Map(runJobs.map(job => [job.name, job]));
        const dag = {
            runId,
            workflowName: run.name,
            branch: run.headBranch,
            commit: run.headSha,
            
            // Nodes (immutable)
            nodes: Object.freeze(
                runJobs.map(job => ({
                    id: job.id,
                    name: job.name,
                    status: job.status,
                    conclusion: job.conclusion,
                    duration: job.duration,
                    steps: job.stepCount,
                    startedAt: job.startedAt,
                    completedAt: job.completedAt,
                }))
            ),
            
            // Edges (inferred from job dependencies)
            edges: Object.freeze(this.inferJobDependencies(runJobs)),
            
            // Critical path (immutable)
            criticalPath: Object.freeze(this.calculateCriticalPath(runJobs)),
            
            // Metadata
            totalJobs: runJobs.length,
            startTime: run.createdAt,
            endTime: run.updatedAt,
        };
        
        return Object.freeze(dag);
    }
    
    /**
     * Infer job dependencies from needs field
     */
    inferJobDependencies(jobs) {
        const edges = [];
        
        // In production, parse job needs from workflow
        // For now, infer from job naming patterns
        const jobNameMap = new Map(jobs.map(j => [j.name, j.id]));
        
        jobs.forEach(job => {
            // Common patterns: build → test, test → deploy
            if (job.name.includes('test')) {
                const buildJob = jobs.find(j => j.name.includes('build'));
                if (buildJob) {
                    edges.push({ from: buildJob.id, to: job.id });
                }
            }
            if (job.name.includes('deploy')) {
                const testJob = jobs.find(j => j.name.includes('test'));
                if (testJob) {
                    edges.push({ from: testJob.id, to: job.id });
                }
            }
        });
        
        return edges;
    }
    
    /**
     * Calculate critical path (longest path in DAG)
     */
    calculateCriticalPath(jobs) {
        // Simplified: return longest running job chain
        const sorted = jobs
            .filter(j => j.duration)
            .sort((a, b) => (b.duration || 0) - (a.duration || 0));
        
        return Object.freeze({
            duration: (sorted[0]?.duration || 0),
            jobName: sorted[0]?.name,
            bottleneck: sorted[0]?.name,
        });
    }
    
    /**
     * Get pipeline status (immutable snapshot)
     */
    getPipelineStatus(runId) {
        const run = this.runs.get(runId);
        if (!run) return null;
        
        const runJobs = Array.from(this.jobs.values())
            .filter(job => job.runId === run.id);
        
        const succeeded = runJobs.filter(j => j.conclusion === 'success').length;
        const failed = runJobs.filter(j => j.conclusion === 'failure').length;
        const cancelled = runJobs.filter(j => j.conclusion === 'cancelled').length;
        const skipped = runJobs.filter(j => j.conclusion === 'skipped').length;
        const inProgress = runJobs.filter(j => j.status === 'in_progress').length;
        
        const status = Object.freeze({
            runId,
            name: run.name,
            overallStatus: run.status,
            overallConclusion: run.conclusion,
            
            // Job breakdown (immutable counts)
            jobs: Object.freeze({
                total: runJobs.length,
                succeeded,
                failed,
                cancelled,
                skipped,
                inProgress,
            }),
            
            // Progress
            percentComplete: runJobs.length > 0 
                ? Math.round(((succeeded + failed + cancelled + skipped) / runJobs.length) * 100)
                : 0,
            
            // Timing
            startTime: run.createdAt,
            endTime: run.updatedAt,
            duration: this.calculateDuration(run.createdAt, run.updatedAt),
            
            // DAG
            dag: this.buildPipelineDAG(runId),
        });
        
        return status;
    }
    
    /**
     * Get job details with logs (immutable snapshot)
     */
    getJobDetails(jobId) {
        const job = this.jobs.get(jobId);
        if (!job) return null;
        
        const logs = this.logs.get(jobId) || [];
        
        return Object.freeze({
            id: job.id,
            name: job.name,
            status: job.status,
            conclusion: job.conclusion,
            
            // Timing
            startedAt: job.startedAt,
            completedAt: job.completedAt,
            duration: job.duration,
            
            // Steps
            steps: job.steps,
            stepCount: job.stepCount,
            
            // Logs
            logCount: logs.length,
            logPreview: logs.slice(-20).map(l => l.content),
            
            // Failure info
            failureReason: job.failureReason,
            failureMessage: job.failureMessage,
        });
    }
    
    /**
     * Trigger job re-run (idempotent)
     */
    async rerunJob(jobId, rerunToken) {
        const rerunId = `${jobId}-rerun-${rerunToken}`;
        
        // Idempotent: if already triggered, return existing
        if (this.updateTokens.has(rerunId)) {
            return {
                status: 'already-triggered',
                jobId,
                token: rerunToken,
            };
        }
        
        const result = {
            jobId,
            rerunToken: rerunToken,
            requestedAt: new Date().toISOString(),
            status: 'triggered',
        };
        
        // Mark as processed
        this.updateTokens.set(rerunId, new Date().toISOString());
        
        this.emit('job-rerun-requested', result);
        return Object.freeze(result);
    }
}

module.exports = CICDStatusService;
