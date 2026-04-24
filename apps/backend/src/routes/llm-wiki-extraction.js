#!/usr/bin/env node
// @file        apps/backend/src/routes/llm-wiki-extraction.ts
// @module      collaboration/llm-wiki-extraction
// @description LLM wiki extraction REST endpoints
// @owner       collab-3.6
// @status      active
import { Router } from 'express';
export function initializeLLMWikiExtractionRoutes(service) {
    const router = Router();
    // POST /api/knowledge - Create knowledge entry
    router.post('/knowledge', async (req, res) => {
        try {
            const { title, content, summary, embedding, authorId, source, sourceType, tags, category } = req.body;
            if (!title || !content || !embedding || !authorId) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            const entry = await service.createKnowledgeEntry(title, content, summary, embedding, authorId, {
                source,
                sourceType,
                tags,
                category,
            });
            res.json(entry);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // POST /api/knowledge/search - Semantic search
    router.post('/knowledge/search', async (req, res) => {
        try {
            const { query, embedding, limit } = req.body;
            if (!query || !embedding) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            const results = await service.searchKnowledge(query, embedding, limit || 10);
            res.json(results);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // GET /api/knowledge/:entryId - Get knowledge entry
    router.get('/knowledge/:entryId', async (req, res) => {
        try {
            const { entryId } = req.params;
            const entry = await service.getKnowledgeEntry(entryId);
            if (!entry) {
                return res.status(404).json({ error: 'Knowledge entry not found' });
            }
            res.json(entry);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // PUT /api/knowledge/:entryId - Update knowledge entry
    router.put('/knowledge/:entryId', async (req, res) => {
        try {
            const { entryId } = req.params;
            const { title, content, summary, embedding, tags, category } = req.body;
            const entry = await service.updateKnowledgeEntry(entryId, {
                title,
                content,
                summary,
                embedding,
                tags,
                category,
            });
            res.json(entry);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // POST /api/knowledge/:entryId/usage - Track knowledge usage
    router.post('/knowledge/:entryId/usage', async (req, res) => {
        try {
            const { entryId } = req.params;
            const { userId, sessionId, context } = req.body;
            if (!userId) {
                return res.status(400).json({ error: 'User ID is required' });
            }
            await service.trackUsage(entryId, userId, sessionId, context);
            res.json({ success: true });
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // POST /api/knowledge/:entryId/feedback - Rate knowledge entry
    router.post('/knowledge/:entryId/feedback', async (req, res) => {
        try {
            const { entryId } = req.params;
            const { userId, rating, helpful, comment } = req.body;
            if (!userId || rating === undefined || helpful === undefined) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            await service.rateFeedback(entryId, userId, rating, helpful, comment);
            res.json({ success: true });
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // POST /api/knowledge/extract - Extract from session
    router.post('/knowledge/extract', async (req, res) => {
        try {
            const { sessionId, content, context, authorId, extractedEntries } = req.body;
            if (!sessionId || !authorId || !extractedEntries) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            const entries = await service.extractFromSession({ sessionId, content, context, authorId }, extractedEntries);
            res.json(entries);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    // GET /api/knowledge-base - Get knowledge base
    router.get('/knowledge-base', async (req, res) => {
        try {
            const { category, author, minViews } = req.query;
            const entries = await service.getKnowledgeBase({
                category: category,
                author: author,
                minViews: minViews ? parseInt(minViews) : undefined,
            });
            res.json(entries);
        }
        catch (error) {
            res.status(500).json({ error: String(error) });
        }
    });
    return router;
}
//# sourceMappingURL=llm-wiki-extraction.js.map