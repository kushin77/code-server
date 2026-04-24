import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class SessionHandOffNotesService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('SessionHandOffNotesService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS session_handoff_notes (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL,
          status VARCHAR(32) NOT NULL CHECK (status IN ('done', 'in-progress', 'blocked', 'next')),
          note TEXT NOT NULL,
          next_action TEXT,
          posted BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS session_handoff_drafts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL UNIQUE,
          summary TEXT NOT NULL,
          draft JSONB NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS session_handoff_acknowledgements (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL,
          user_id VARCHAR(255) NOT NULL,
          acknowledged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_session_handoff_notes_session ON session_handoff_notes(session_id, created_at DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_session_handoff_drafts_session ON session_handoff_drafts(session_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_session_handoff_ack_session ON session_handoff_acknowledgements(session_id)`);
        }
        finally {
            client.release();
        }
    }
    async recordNote(sessionId, status, note, nextAction = null) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          INSERT INTO session_handoff_notes (session_id, status, note, next_action)
          VALUES ($1, $2, $3, $4)
          RETURNING id, session_id, status, note, next_action, posted, created_at
        `, [sessionId, status, note, nextAction]);
            const row = result.rows[0];
            const record = {
                id: row.id,
                sessionId: row.session_id,
                status: row.status,
                note: row.note,
                nextAction: row.next_action,
                posted: row.posted,
                createdAt: row.created_at
            };
            this.emit('handoff-note-recorded', record);
            return record;
        }
        finally {
            client.release();
        }
    }
    async listNotes(sessionId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT id, session_id, status, note, next_action, posted, created_at
          FROM session_handoff_notes
          WHERE session_id = $1
          ORDER BY created_at ASC
        `, [sessionId]);
            return result.rows.map(row => ({
                id: row.id,
                sessionId: row.session_id,
                status: row.status,
                note: row.note,
                nextAction: row.next_action,
                posted: row.posted,
                createdAt: row.created_at
            }));
        }
        finally {
            client.release();
        }
    }
    async generateHandOffDraft(sessionId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT status, note, next_action
          FROM session_handoff_notes
          WHERE session_id = $1
          ORDER BY created_at ASC
        `, [sessionId]);
            const done = [];
            const inProgress = [];
            const blocked = [];
            const next = [];
            for (const row of result.rows) {
                if (row.status === 'done')
                    done.push(row.note);
                if (row.status === 'in-progress')
                    inProgress.push(row.note);
                if (row.status === 'blocked')
                    blocked.push(row.note);
                if (row.status === 'next')
                    next.push(row.next_action || row.note);
            }
            const summaryLines = [
                `Session ${sessionId} hand-off`,
                `Done: ${done.length}`,
                `In progress: ${inProgress.length}`,
                `Blocked: ${blocked.length}`,
                `Next: ${next.length}`
            ];
            const summary = summaryLines.join('\n');
            const draft = {
                sessionId,
                summary,
                done,
                inProgress,
                blocked,
                next,
                createdAt: new Date()
            };
            await client.query(`
          INSERT INTO session_handoff_drafts (session_id, summary, draft)
          VALUES ($1, $2, $3)
          ON CONFLICT (session_id)
          DO UPDATE SET summary = EXCLUDED.summary, draft = EXCLUDED.draft, created_at = CURRENT_TIMESTAMP
        `, [sessionId, summary, JSON.stringify(draft)]);
            this.emit('handoff-draft-generated', draft);
            return draft;
        }
        finally {
            client.release();
        }
    }
    async getLatestDraft(sessionId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT session_id, summary, draft, created_at FROM session_handoff_drafts WHERE session_id = $1`, [sessionId]);
            if (result.rows.length === 0)
                return null;
            const row = result.rows[0];
            const draft = row.draft || {};
            return {
                sessionId: row.session_id,
                summary: row.summary,
                done: draft.done || [],
                inProgress: draft.inProgress || [],
                blocked: draft.blocked || [],
                next: draft.next || [],
                createdAt: row.created_at
            };
        }
        finally {
            client.release();
        }
    }
    async markNotePosted(noteId) {
        const client = await this.pool.connect();
        try {
            await client.query(`UPDATE session_handoff_notes SET posted = TRUE WHERE id = $1`, [noteId]);
            this.emit('handoff-note-posted', { noteId });
        }
        finally {
            client.release();
        }
    }
    async acknowledgeSession(sessionId, userId) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO session_handoff_acknowledgements (session_id, user_id) VALUES ($1, $2)`, [sessionId, userId]);
        }
        finally {
            client.release();
        }
    }
}
export async function initializeSessionHandOffNotesRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('SessionHandOffNotesRoutes');
    router.post('/api/session-handoff/notes', async (req, res) => {
        try {
            const { sessionId, status, note, nextAction } = req.body;
            const created = await service.recordNote(sessionId, status, note, nextAction || null);
            res.json(created);
        }
        catch (error) {
            logger.error('Failed to record handoff note', error);
            res.status(500).json({ error: 'Failed to record handoff note' });
        }
    });
    router.get('/api/session-handoff/notes/:sessionId', async (req, res) => {
        try {
            const notes = await service.listNotes(req.params.sessionId);
            res.json(notes);
        }
        catch (error) {
            logger.error('Failed to list handoff notes', error);
            res.status(500).json({ error: 'Failed to list handoff notes' });
        }
    });
    router.post('/api/session-handoff/draft/:sessionId', async (req, res) => {
        try {
            const draft = await service.generateHandOffDraft(req.params.sessionId);
            res.json(draft);
        }
        catch (error) {
            logger.error('Failed to generate handoff draft', error);
            res.status(500).json({ error: 'Failed to generate handoff draft' });
        }
    });
    router.get('/api/session-handoff/draft/:sessionId', async (req, res) => {
        try {
            const draft = await service.getLatestDraft(req.params.sessionId);
            if (!draft) {
                res.status(404).json({ error: 'Handoff draft not found' });
                return;
            }
            res.json(draft);
        }
        catch (error) {
            logger.error('Failed to get handoff draft', error);
            res.status(500).json({ error: 'Failed to get handoff draft' });
        }
    });
    router.post('/api/session-handoff/post/:noteId', async (req, res) => {
        try {
            await service.markNotePosted(req.params.noteId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to mark note posted', error);
            res.status(500).json({ error: 'Failed to mark note posted' });
        }
    });
    router.post('/api/session-handoff/acknowledge/:sessionId', async (req, res) => {
        try {
            const { userId } = req.body;
            await service.acknowledgeSession(req.params.sessionId, userId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to acknowledge session', error);
            res.status(500).json({ error: 'Failed to acknowledge session' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map