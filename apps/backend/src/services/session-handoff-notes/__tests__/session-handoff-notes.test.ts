import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SessionHandOffNotesService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn()
  })
}));

describe('SessionHandOffNotesService', () => {
  let service: SessionHandOffNotesService;
  let mockPool: any;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn()
    };

    mockPool = {
      connect: vi.fn().mockResolvedValue(mockClient)
    };

    service = new SessionHandOffNotesService(mockPool);
  });

  it('initializes handoff tables', async () => {
    for (let i = 0; i < 6; i++) {
      mockClient.query.mockResolvedValueOnce({});
    }

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('session_handoff_notes'));
    expect(mockClient.release).toHaveBeenCalled();
  });

  it('records a handoff note', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: 'note-1',
        session_id: 'session-1',
        status: 'done',
        note: 'Completed the API',
        next_action: null,
        posted: false,
        created_at: new Date()
      }]
    });

    const note = await service.recordNote('session-1', 'done', 'Completed the API');

    expect(note.id).toBe('note-1');
    expect(note.status).toBe('done');
  });

  it('lists notes for a session', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'note-1',
          session_id: 'session-1',
          status: 'done',
          note: 'Completed the API',
          next_action: null,
          posted: false,
          created_at: new Date()
        }
      ]
    });

    const notes = await service.listNotes('session-1');

    expect(notes).toHaveLength(1);
    expect(notes[0].note).toBe('Completed the API');
  });

  it('generates a handoff draft', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [
        { status: 'done', note: 'API done', next_action: null },
        { status: 'in-progress', note: 'Testing routes', next_action: null },
        { status: 'blocked', note: 'Waiting on review', next_action: null },
        { status: 'next', note: 'Ship docs', next_action: 'Publish release notes' }
      ]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    const draft = await service.generateHandOffDraft('session-1');

    expect(draft.done).toContain('API done');
    expect(draft.inProgress).toContain('Testing routes');
    expect(draft.blocked).toContain('Waiting on review');
    expect(draft.next).toContain('Publish release notes');
  });

  it('gets latest draft', async () => {
    mockClient.query.mockResolvedValueOnce({
      rows: [{
        session_id: 'session-1',
        summary: 'Session session-1 hand-off',
        draft: {
          done: ['API done'],
          inProgress: ['Testing routes'],
          blocked: [],
          next: ['Ship docs']
        },
        created_at: new Date()
      }]
    });

    const draft = await service.getLatestDraft('session-1');

    expect(draft?.done).toContain('API done');
    expect(draft?.next).toContain('Ship docs');
  });

  it('marks a note posted', async () => {
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.markNotePosted('note-1');

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE session_handoff_notes SET posted = TRUE'),
      expect.any(Array)
    );
  });

  it('acknowledges a session', async () => {
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.acknowledgeSession('session-1', 'user-1');

    expect(mockClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO session_handoff_acknowledgements'),
      expect.any(Array)
    );
  });

  it('returns null for missing draft', async () => {
    mockClient.query.mockResolvedValueOnce({ rows: [] });

    const draft = await service.getLatestDraft('missing');

    expect(draft).toBeNull();
  });

  it('emits handoff-note-recorded event', async () => {
    let emittedEvent: any;
    service.on('handoff-note-recorded', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [{
        id: 'note-1',
        session_id: 'session-1',
        status: 'next',
        note: 'Ship docs',
        next_action: 'Publish release notes',
        posted: false,
        created_at: new Date()
      }]
    });

    await service.recordNote('session-1', 'next', 'Ship docs', 'Publish release notes');

    expect(emittedEvent.id).toBe('note-1');
  });

  it('emits handoff-draft-generated event', async () => {
    let emittedEvent: any;
    service.on('handoff-draft-generated', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({
      rows: [
        { status: 'done', note: 'API done', next_action: null }
      ]
    });
    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.generateHandOffDraft('session-1');

    expect(emittedEvent.sessionId).toBe('session-1');
  });

  it('emits handoff-note-posted event', async () => {
    let emittedEvent: any;
    service.on('handoff-note-posted', event => {
      emittedEvent = event;
    });

    mockClient.query.mockResolvedValueOnce({ rowCount: 1 });

    await service.markNotePosted('note-1');

    expect(emittedEvent.noteId).toBe('note-1');
  });
});
