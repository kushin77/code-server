#!/usr/bin/env node
/**
 * @file        scripts/integrations/github-issues-panel-api.js
 * @module      integrations/github
 * @description REST API for GitHub Issues IDE panel with immutable state
 */

const express = require('express');
const GitHubIssuesPanelService = require('./github-issues-panel-service');

const app = express();
const PORT = process.env.PORT || 9097;

// Initialize service
const issuesService = new GitHubIssuesPanelService({
    githubToken: process.env.GITHUB_TOKEN,
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
});

// Event listeners
issuesService.on('issue-created', (context) => {
    console.log(`[GitHub Issues] Created: #${context.issueNumber} - ${context.title}`);
});

issuesService.on('issue-updated', (context) => {
    console.log(`[GitHub Issues] Updated: #${context.issueNumber} v${context.version}`);
});

issuesService.on('comment-added', (context) => {
    console.log(`[GitHub Issues] Comment: #${context.issueNumber} by ${context.author}`);
});

issuesService.on('filter-changed', (context) => {
    console.log(`[GitHub Issues] Filter: ${context.filterName} = ${context.value}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'github-issues-panel' });
});

// Get issues list
app.get('/issues', async (req, res) => {
    try {
        const filters = {
            state: req.query.state || 'open',
            assignee: req.query.assignee,
            labels: req.query.labels ? req.query.labels.split(',') : [],
            priority: req.query.priority,
            sortBy: req.query.sortBy || 'updated',
            sortOrder: req.query.sortOrder || 'desc',
        };
        
        const issues = await issuesService.getIssuesList(filters);
        
        res.json({
            total: issues.length,
            filters,
            issues: issues.map(i => ({
                number: i.number,
                title: i.title,
                state: i.state,
                priority: i.priority,
                assignee: i.assignee ? i.assignee.login : null,
                labels: i.labels,
                createdAt: i.createdAt,
                updatedAt: i.updatedAt,
                commentCount: i.commentCount,
                version: i.version,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get issue details
app.get('/issues/:issueNumber', async (req, res) => {
    try {
        const issue = await issuesService.getIssueDetails(parseInt(req.params.issueNumber));
        
        if (!issue) {
            return res.status(404).json({ error: 'Issue not found' });
        }
        
        res.json({
            number: issue.number,
            title: issue.title,
            state: issue.state,
            priority: issue.priority,
            body: issue.body,
            assignee: issue.assignee ? issue.assignee.login : null,
            labels: issue.labels,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            commentCount: issue.commentCount,
            version: issue.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get issue comments
app.get('/issues/:issueNumber/comments', async (req, res) => {
    try {
        const comments = await issuesService.getIssueComments(parseInt(req.params.issueNumber));
        
        res.json({
            issueNumber: parseInt(req.params.issueNumber),
            total: comments.length,
            comments: comments.map(c => ({
                id: c.id,
                author: c.author.login,
                body: c.body,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
                version: c.version,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create issue
app.post('/issues', async (req, res) => {
    try {
        const { title, body, labels, assignee, priority } = req.body;
        const idempotencyKey = req.headers['x-idempotency-key'] || 
            `${Date.now()}-${Math.random()}`;
        
        if (!title) {
            return res.status(400).json({ error: 'Title is required' });
        }
        
        const result = await issuesService.createIssue(
            { title, body, labels, assignee, priority },
            idempotencyKey
        );
        
        if (result.status === 'already-created') {
            return res.status(409).json({
                status: 'conflict',
                issueNumber: result.issueNumber,
                message: 'Issue already created with this idempotency key',
            });
        }
        
        res.status(201).json({
            status: 'created',
            issueNumber: result.issueNumber,
            url: `https://github.com/kushin77/code-server/issues/${result.issueNumber}`,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Update issue
app.put('/issues/:issueNumber', async (req, res) => {
    try {
        const issueNumber = parseInt(req.params.issueNumber);
        const updateToken = req.headers['x-update-token'] || 
            `update-${Date.now()}-${Math.random()}`;
        
        const result = await issuesService.updateIssue(
            issueNumber,
            req.body,
            updateToken
        );
        
        if (result.status === 'already-updated') {
            return res.status(409).json({
                status: 'conflict',
                issueNumber,
                version: result.version,
                message: 'Update already applied',
            });
        }
        
        res.json({
            status: 'updated',
            issueNumber,
            version: result.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Add comment
app.post('/issues/:issueNumber/comments', async (req, res) => {
    try {
        const issueNumber = parseInt(req.params.issueNumber);
        const { body, author } = req.body;
        const idempotencyKey = req.headers['x-idempotency-key'] || 
            `${Date.now()}-${Math.random()}`;
        
        if (!body || !author) {
            return res.status(400).json({ error: 'Body and author required' });
        }
        
        const result = await issuesService.addComment(
            issueNumber,
            { body, author },
            idempotencyKey
        );
        
        if (result.status === 'already-added') {
            return res.status(409).json({
                status: 'conflict',
                commentId: result.commentId,
                message: 'Comment already added',
            });
        }
        
        res.status(201).json({
            status: 'added',
            commentId: result.commentId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Assign issue
app.put('/issues/:issueNumber/assign', async (req, res) => {
    try {
        const issueNumber = parseInt(req.params.issueNumber);
        const { assignee } = req.body;
        const assignmentToken = req.headers['x-assignment-token'] || 
            `assign-${Date.now()}-${Math.random()}`;
        
        if (!assignee) {
            return res.status(400).json({ error: 'Assignee is required' });
        }
        
        const result = await issuesService.assignIssue(
            issueNumber,
            assignee,
            assignmentToken
        );
        
        res.json({
            status: 'updated',
            issueNumber,
            version: result.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Add label
app.post('/issues/:issueNumber/labels', async (req, res) => {
    try {
        const issueNumber = parseInt(req.params.issueNumber);
        const { label } = req.body;
        const labelToken = req.headers['x-label-token'] || 
            `label-${Date.now()}-${Math.random()}`;
        
        if (!label) {
            return res.status(400).json({ error: 'Label is required' });
        }
        
        const result = await issuesService.addLabel(
            issueNumber,
            label,
            labelToken
        );
        
        res.json({
            status: result.status,
            issueNumber,
            labels: result.labels,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Set filter
app.post('/panel/filter', (req, res) => {
    try {
        const { filterName, value } = req.body;
        
        if (!filterName) {
            return res.status(400).json({ error: 'Filter name is required' });
        }
        
        issuesService.setFilter(filterName, value);
        
        res.json({
            status: 'applied',
            filter: filterName,
            value,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Set sort
app.post('/panel/sort', (req, res) => {
    try {
        const { sortBy, sortOrder } = req.body;
        
        if (!sortBy) {
            return res.status(400).json({ error: 'Sort field is required' });
        }
        
        issuesService.setSort(sortBy, sortOrder || 'desc');
        
        res.json({
            status: 'applied',
            sortBy,
            sortOrder: sortOrder || 'desc',
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[GitHub Issues Panel API] Listening on port ${PORT}`);
    console.log(`[GitHub Issues Panel API] GET /issues - List issues`);
    console.log(`[GitHub Issues Panel API] GET /issues/:issueNumber - Get issue`);
    console.log(`[GitHub Issues Panel API] POST /issues - Create issue`);
    console.log(`[GitHub Issues Panel API] PUT /issues/:issueNumber - Update issue`);
    console.log(`[GitHub Issues Panel API] POST /issues/:issueNumber/comments - Add comment`);
});
