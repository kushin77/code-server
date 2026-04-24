#!/usr/bin/env node
/**
 * @file        scripts/integrations/github-issues-panel-service.js
 * @module      integrations/github
 * @description IDE sidebar panel for GitHub issues with immutable state and idempotent updates
 *
 * IaC Principles:
 * - Immutable: Issue snapshots frozen once fetched
 * - Idempotent: Same filter state = same results
 * - Versioned: Issue state versions for update tracking
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class GitHubIssuesPanelService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.githubToken = options.githubToken || process.env.GITHUB_TOKEN;
        this.owner = options.owner || process.env.GITHUB_OWNER || 'kushin77';
        this.repo = options.repo || process.env.GITHUB_REPO || 'code-server';
        
        // Immutable issue snapshots (frozen)
        this.issues = new Map(); // issueNumber → frozen issue
        this.comments = new Map(); // issueNumber → [frozen comments]
        
        // Filter/sort state (for idempotent caching)
        this.filterStates = new Map(); // filterHash → frozen state
        this.searchCache = new Map(); // searchHash → {timestamp, results}
        
        // Update tracking (idempotency)
        this.updateTokens = new Map(); // updateToken → processed timestamp
        
        // Panel state
        this.panelState = {
            selectedIssue: null,
            filters: {
                state: 'open',
                assignee: null,
                labels: [],
                milestone: null,
                priority: null,
            },
            sortBy: 'updated',
            sortOrder: 'desc',
            pageSize: 20,
            currentPage: 1,
            searchText: '',
        };
    }
    
    /**
     * Get issues list (immutable, cached)
     */
    async getIssuesList(filters = {}) {
        const appliedFilters = { ...this.panelState.filters, ...filters };
        const filterHash = this.hashFilters(appliedFilters);
        
        // Check cache (immutable snapshot)
        if (this.filterStates.has(filterHash)) {
            const cached = this.filterStates.get(filterHash);
            if (Date.now() - cached.timestamp < 60000) { // 60s TTL
                return cached.issues;
            }
        }
        
        // Simulate fetching from GitHub (immutable results)
        const issues = await this.fetchIssuesFromGitHub(appliedFilters);
        
        // Freeze and cache (immutable)
        const frozenIssues = Object.freeze(
            issues.map(i => Object.freeze(i))
        );
        
        this.filterStates.set(filterHash, {
            timestamp: Date.now(),
            issues: frozenIssues,
            filters: Object.freeze({ ...appliedFilters }),
        });
        
        return frozenIssues;
    }
    
    /**
     * Fetch issues from GitHub (immutable snapshot)
     */
    async fetchIssuesFromGitHub(filters) {
        // Simulate GitHub API call
        // In production: use @octokit/rest
        
        const mockIssues = [
            {
                number: 1315,
                title: 'Implement real-time collaboration',
                state: 'open',
                priority: 'P1',
                assignee: { login: 'alice' },
                labels: ['feature', 'collaboration'],
                createdAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
                updatedAt: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString(),
                commentCount: 3,
                version: 1,
            },
            {
                number: 1314,
                title: 'Fix WebSocket memory leak',
                state: 'open',
                priority: 'P0',
                assignee: { login: 'bob' },
                labels: ['bug', 'websocket'],
                createdAt: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString(),
                updatedAt: new Date().toISOString(),
                commentCount: 5,
                version: 1,
            },
            {
                number: 1313,
                title: 'WebSocket Gateway Cluster',
                state: 'closed',
                priority: 'P1',
                assignee: { login: 'charlie' },
                labels: ['infrastructure', 'completed'],
                createdAt: new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString(),
                updatedAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
                commentCount: 12,
                version: 2,
            },
        ];
        
        // Apply filters
        let filtered = mockIssues;
        
        if (filters.state) {
            filtered = filtered.filter(i => i.state === filters.state);
        }
        
        if (filters.assignee) {
            filtered = filtered.filter(i => i.assignee && i.assignee.login === filters.assignee);
        }
        
        if (filters.labels && filters.labels.length) {
            filtered = filtered.filter(i =>
                filters.labels.every(l => i.labels.includes(l))
            );
        }
        
        if (filters.priority) {
            filtered = filtered.filter(i => i.priority === filters.priority);
        }
        
        // Sort
        const sortKey = filters.sortBy || 'updated';
        const sortOrder = filters.sortOrder || 'desc';
        
        filtered.sort((a, b) => {
            const aVal = a[sortKey];
            const bVal = b[sortKey];
            
            if (typeof aVal === 'string' && sortKey.includes('At')) {
                const aTime = new Date(aVal).getTime();
                const bTime = new Date(bVal).getTime();
                return sortOrder === 'desc' ? bTime - aTime : aTime - bTime;
            }
            
            if (typeof aVal === 'string') {
                const cmp = aVal.localeCompare(bVal);
                return sortOrder === 'desc' ? -cmp : cmp;
            }
            
            return sortOrder === 'desc' ? bVal - aVal : aVal - bVal;
        });
        
        return filtered;
    }
    
    /**
     * Get issue details (immutable snapshot)
     */
    async getIssueDetails(issueNumber) {
        // Check cache
        if (this.issues.has(issueNumber)) {
            return this.issues.get(issueNumber);
        }
        
        // Simulate fetch
        const issue = {
            number: issueNumber,
            title: 'Example Issue',
            state: 'open',
            priority: 'P1',
            body: 'Issue description...',
            assignee: { login: 'alice' },
            labels: ['feature'],
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            commentCount: 5,
            version: 1,
        };
        
        // Freeze and cache
        Object.freeze(issue);
        this.issues.set(issueNumber, issue);
        
        return issue;
    }
    
    /**
     * Get issue comments (immutable array)
     */
    async getIssueComments(issueNumber) {
        // Check cache
        if (this.comments.has(issueNumber)) {
            return this.comments.get(issueNumber);
        }
        
        // Simulate fetch
        const comments = [
            {
                id: 1,
                author: { login: 'bob' },
                body: 'First comment...',
                createdAt: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString(),
                updatedAt: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString(),
                version: 1,
            },
            {
                id: 2,
                author: { login: 'charlie' },
                body: 'Second comment...',
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                version: 1,
            },
        ];
        
        // Freeze and cache (immutable array)
        const frozenComments = Object.freeze(
            comments.map(c => Object.freeze(c))
        );
        this.comments.set(issueNumber, frozenComments);
        
        return frozenComments;
    }
    
    /**
     * Create issue (immutable, idempotent)
     */
    async createIssue(issueData, idempotencyKey) {
        // Idempotent: check if already created
        if (this.updateTokens.has(idempotencyKey)) {
            const createdNumber = this.findCreatedIssueByToken(idempotencyKey);
            if (createdNumber) {
                return {
                    status: 'already-created',
                    issueNumber: createdNumber,
                };
            }
        }
        
        // Create issue (immutable)
        const newIssue = {
            number: Math.floor(Math.random() * 10000),
            title: issueData.title,
            body: issueData.body || '',
            labels: issueData.labels || [],
            assignee: issueData.assignee || null,
            state: 'open',
            priority: issueData.priority || 'P2',
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            commentCount: 0,
            version: 1,
        };
        
        // Freeze and store
        Object.freeze(newIssue);
        this.issues.set(newIssue.number, newIssue);
        
        // Mark as processed (idempotent)
        this.updateTokens.set(idempotencyKey, {
            timestamp: new Date().toISOString(),
            issueNumber: newIssue.number,
        });
        
        this.emit('issue-created', {
            issueNumber: newIssue.number,
            title: newIssue.title,
        });
        
        return {
            status: 'created',
            issueNumber: newIssue.number,
        };
    }
    
    /**
     * Update issue (idempotent, versioned)
     */
    async updateIssue(issueNumber, updateData, updateToken) {
        // Get current issue
        let issue = this.issues.get(issueNumber);
        if (!issue) {
            issue = await this.getIssueDetails(issueNumber);
        }
        
        // Idempotent: check if already updated
        const tokenKey = `issue-${issueNumber}-${updateToken}`;
        if (this.updateTokens.has(tokenKey)) {
            return {
                status: 'already-updated',
                issueNumber,
                version: issue.version,
            };
        }
        
        // Create new version (immutable update)
        const updatedIssue = {
            ...issue,
            // Apply updates
            title: updateData.title || issue.title,
            body: updateData.body !== undefined ? updateData.body : issue.body,
            state: updateData.state || issue.state,
            assignee: updateData.assignee || issue.assignee,
            labels: updateData.labels || issue.labels,
            priority: updateData.priority || issue.priority,
            updatedAt: new Date().toISOString(),
            version: issue.version + 1,
        };
        
        // Freeze and replace
        Object.freeze(updatedIssue);
        this.issues.set(issueNumber, updatedIssue);
        
        // Mark as processed
        this.updateTokens.set(tokenKey, new Date().toISOString());
        
        this.emit('issue-updated', {
            issueNumber,
            changes: updateData,
            version: updatedIssue.version,
        });
        
        return {
            status: 'updated',
            issueNumber,
            version: updatedIssue.version,
        };
    }
    
    /**
     * Add comment to issue (immutable append)
     */
    async addComment(issueNumber, commentData, idempotencyKey) {
        // Idempotent: check if already added
        const tokenKey = `comment-${issueNumber}-${idempotencyKey}`;
        if (this.updateTokens.has(tokenKey)) {
            const commentId = this.findCommentByToken(tokenKey);
            if (commentId) {
                return {
                    status: 'already-added',
                    commentId,
                };
            }
        }
        
        // Get current comments
        let comments = this.comments.get(issueNumber) || [];
        
        // Create new comment (immutable)
        const newComment = {
            id: Math.floor(Math.random() * 10000),
            author: { login: commentData.author },
            body: commentData.body,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            version: 1,
        };
        
        // Add to immutable array
        const updatedComments = [...comments, Object.freeze(newComment)];
        const frozenComments = Object.freeze(updatedComments);
        
        this.comments.set(issueNumber, frozenComments);
        
        // Mark as processed
        this.updateTokens.set(tokenKey, {
            timestamp: new Date().toISOString(),
            commentId: newComment.id,
        });
        
        this.emit('comment-added', {
            issueNumber,
            commentId: newComment.id,
            author: commentData.author,
        });
        
        return {
            status: 'added',
            commentId: newComment.id,
        };
    }
    
    /**
     * Assign issue (idempotent, versioned)
     */
    async assignIssue(issueNumber, assignee, assignmentToken) {
        return this.updateIssue(issueNumber, { assignee }, assignmentToken);
    }
    
    /**
     * Add label to issue (idempotent)
     */
    async addLabel(issueNumber, label, labelToken) {
        const issue = this.issues.get(issueNumber) || await this.getIssueDetails(issueNumber);
        
        const labelKey = `label-${issueNumber}-${label}`;
        if (this.updateTokens.has(labelKey)) {
            return {
                status: 'already-added',
                issueNumber,
                labels: issue.labels,
            };
        }
        
        const newLabels = [...new Set([...issue.labels, label])];
        
        const updatedIssue = {
            ...issue,
            labels: newLabels,
            version: issue.version + 1,
            updatedAt: new Date().toISOString(),
        };
        
        Object.freeze(updatedIssue);
        this.issues.set(issueNumber, updatedIssue);
        this.updateTokens.set(labelKey, new Date().toISOString());
        
        return {
            status: 'added',
            issueNumber,
            labels: newLabels,
        };
    }
    
    /**
     * Set filter and update panel (immutable filter state)
     */
    setFilter(filterName, value) {
        this.panelState.filters[filterName] = value;
        this.panelState.currentPage = 1;
        
        this.emit('filter-changed', {
            filterName,
            value,
            filters: Object.freeze({ ...this.panelState.filters }),
        });
    }
    
    /**
     * Set sort (immutable sort state)
     */
    setSort(sortBy, sortOrder = 'desc') {
        this.panelState.sortBy = sortBy;
        this.panelState.sortOrder = sortOrder;
        this.panelState.currentPage = 1;
        
        this.emit('sort-changed', {
            sortBy,
            sortOrder,
        });
    }
    
    /**
     * Hash filters for caching
     */
    hashFilters(filters) {
        const str = JSON.stringify(filters);
        return crypto.createHash('sha256').update(str).digest('hex');
    }
    
    /**
     * Find created issue by token
     */
    findCreatedIssueByToken(token) {
        const entry = this.updateTokens.get(token);
        return entry ? entry.issueNumber : null;
    }
    
    /**
     * Find comment by token
     */
    findCommentByToken(token) {
        const entry = this.updateTokens.get(token);
        return entry ? entry.commentId : null;
    }
}

module.exports = GitHubIssuesPanelService;
