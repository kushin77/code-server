#!/usr/bin/env node
// @file        apps/backend/src/services/debug-session-collaboration/index.ts
// @module      backend/services/debug-session-collaboration
// @description Collaborative debugging session service and DAP relay routes
// @owner       backend
import axios from 'axios';
import { randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { Router } from 'express';
import { extractTraceHeaders, getTracer, withSpan } from '../../lib/tracing.js';
import { getLogger } from '../../lib/logger.js';
function nowIso() {
    return new Date().toISOString();
}
function cloneSession(session) {
    return {
        ...session,
        participants: session.participants.map((participant) => ({ ...participant })),
        breakpoints: session.breakpoints.map((breakpoint) => ({ ...breakpoint })),
        variables: session.variables.map((variable) => ({ ...variable })),
        stepEvents: session.stepEvents.map((stepEvent) => ({ ...stepEvent })),
        relayMessages: session.relayMessages.map((relayMessage) => ({ ...relayMessage, message: { ...relayMessage.message } })),
    };
}
function normalizeText(value, fallback = '') {
    return typeof value === 'string' ? value.trim() : fallback;
}
function normalizeNumber(value, fallback = 0) {
    const parsed = typeof value === 'number' ? value : Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}
function normalizeBreakpoint(breakpoint) {
    return {
        id: normalizeText(breakpoint.id, randomUUID()),
        filePath: breakpoint.filePath.trim(),
        line: normalizeNumber(breakpoint.line, 1),
        column: breakpoint.column ? normalizeNumber(breakpoint.column) : undefined,
        condition: normalizeText(breakpoint.condition) || undefined,
        hitCondition: normalizeText(breakpoint.hitCondition) || undefined,
        logMessage: normalizeText(breakpoint.logMessage) || undefined,
        verified: breakpoint.verified ?? true,
    };
}
function normalizeVariable(variable) {
    return {
        scope: variable.scope.trim(),
        name: variable.name.trim(),
        value: String(variable.value),
        type: normalizeText(variable.type) || undefined,
        variablesReference: variable.variablesReference ? normalizeNumber(variable.variablesReference) : undefined,
    };
}
function normalizeActor(actor) {
    return normalizeText(actor);
}
export class DebugSessionCollaborationService extends EventEmitter {
    logger = getLogger('DebugSessionCollaborationService');
    sessions = new Map();
    createSession(input) {
        const actor = normalizeActor(input.actor);
        const workspaceId = normalizeText(input.workspaceId);
        if (!actor) {
            throw new Error('Debug session actor is required');
        }
        if (!workspaceId) {
            throw new Error('Debug session workspaceId is required');
        }
        const timestamp = nowIso();
        const session = {
            sessionId: randomUUID(),
            workspaceId,
            debuggerName: normalizeText(input.debuggerName, 'Debugger'),
            debuggerProgram: normalizeText(input.debuggerProgram),
            debuggerCwd: normalizeText(input.debuggerCwd),
            owner: actor,
            relayTarget: normalizeText(input.relayTarget) || undefined,
            participants: [
                {
                    actor,
                    role: 'owner',
                    joinedAt: timestamp,
                    lastSeenAt: timestamp,
                },
            ],
            breakpoints: [],
            variables: [],
            stepEvents: [],
            relayMessages: [],
            relaySequence: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
        };
        this.sessions.set(session.sessionId, session);
        this.logger.info('Created collaborative debug session', { sessionId: session.sessionId, workspaceId });
        this.emit('debug-session-created', cloneSession(session));
        return cloneSession(session);
    }
    listSessions(workspaceId) {
        const normalizedWorkspaceId = normalizeText(workspaceId);
        return Array.from(this.sessions.values())
            .filter((session) => (normalizedWorkspaceId ? session.workspaceId === normalizedWorkspaceId : true))
            .map((session) => cloneSession(session));
    }
    getSession(sessionId) {
        return cloneSession(this.requireSession(sessionId));
    }
    joinSession(sessionId, actor, role = 'collaborator') {
        const session = this.requireSession(sessionId);
        const participantActor = normalizeActor(actor);
        if (!participantActor) {
            throw new Error('Debug session actor is required');
        }
        const timestamp = nowIso();
        const participant = session.participants.find((entry) => entry.actor === participantActor);
        if (participant) {
            participant.lastSeenAt = timestamp;
            participant.role = participant.role === 'owner' ? 'owner' : role;
        }
        else {
            session.participants.push({
                actor: participantActor,
                role,
                joinedAt: timestamp,
                lastSeenAt: timestamp,
            });
        }
        session.updatedAt = timestamp;
        this.emit('debug-session-joined', cloneSession(session));
        return cloneSession(session);
    }
    leaveSession(sessionId, actor) {
        const session = this.requireSession(sessionId);
        const participantActor = normalizeActor(actor);
        if (!participantActor) {
            throw new Error('Debug session actor is required');
        }
        session.participants = session.participants.filter((participant) => participant.actor !== participantActor);
        if (session.owner === participantActor && session.participants.length > 0) {
            session.owner = session.participants[0].actor;
            session.participants[0].role = 'owner';
        }
        session.updatedAt = nowIso();
        this.emit('debug-session-left', cloneSession(session));
        return cloneSession(session);
    }
    updateBreakpoints(sessionId, input) {
        const session = this.requireParticipant(sessionId, input.actor);
        session.breakpoints = input.breakpoints.map((breakpoint) => normalizeBreakpoint(breakpoint));
        session.updatedAt = nowIso();
        this.emit('debug-breakpoints-updated', cloneSession(session));
        return cloneSession(session);
    }
    updateVariables(sessionId, input) {
        const session = this.requireParticipant(sessionId, input.actor);
        session.variables = input.variables.map((variable) => normalizeVariable(variable));
        session.updatedAt = nowIso();
        this.emit('debug-variables-updated', cloneSession(session));
        return cloneSession(session);
    }
    recordStep(sessionId, input) {
        const session = this.requireParticipant(sessionId, input.actor);
        const timestamp = nowIso();
        session.stepEvents = [
            ...session.stepEvents,
            {
                id: randomUUID(),
                actor: normalizeActor(input.actor),
                action: input.action,
                note: normalizeText(input.note) || undefined,
                timestamp,
            },
        ];
        session.updatedAt = timestamp;
        this.emit('debug-step-recorded', cloneSession(session));
        return cloneSession(session);
    }
    async relayDapMessage(sessionId, input) {
        return withSpan(getTracer('backend/services/debug-session-collaboration'), 'debug-session.relay-dap', {
            'collab.session_id': sessionId,
        }, async (span) => {
            const session = this.requireParticipant(sessionId, input.actor);
            const timestamp = nowIso();
            const sequence = session.relaySequence + 1;
            const relayTarget = normalizeText(input.relayTarget) || session.relayTarget;
            const relayMessage = {
                id: randomUUID(),
                sequence,
                actor: normalizeActor(input.actor),
                message: { ...input.message },
                relayTarget: relayTarget || undefined,
                forwarded: false,
                timestamp,
            };
            span.setAttribute('collab.relay_sequence', sequence);
            span.setAttribute('collab.relay_target_present', Boolean(relayTarget));
            if (relayTarget) {
                try {
                    const response = await axios.post(relayTarget, {
                        sessionId,
                        actor: relayMessage.actor,
                        message: relayMessage.message,
                        timestamp,
                    }, {
                        headers: extractTraceHeaders(),
                    });
                    relayMessage.forwarded = (response.status ?? 200) < 400;
                }
                catch (error) {
                    this.logger.warn('Failed to relay debug protocol message', { sessionId, relayTarget, error });
                    throw new Error(`Failed to relay debug protocol message to ${relayTarget}`);
                }
            }
            session.relayTarget = relayTarget || session.relayTarget;
            session.relaySequence = sequence;
            session.relayMessages = [...session.relayMessages, relayMessage];
            session.updatedAt = timestamp;
            this.emit('debug-dap-relayed', cloneSession(session));
            span.setAttribute('collab.forwarded', relayMessage.forwarded);
            return cloneSession(session);
        });
    }
    listRelayMessages(sessionId, actor, sinceSequence = 0) {
        const session = this.requireParticipant(sessionId, actor);
        const normalizedSinceSequence = Math.max(0, normalizeNumber(sinceSequence, 0));
        const messages = session.relayMessages
            .filter((relayMessage) => relayMessage.sequence > normalizedSinceSequence)
            .map((relayMessage) => ({ ...relayMessage, message: { ...relayMessage.message } }));
        return {
            sessionId: session.sessionId,
            relayTarget: session.relayTarget,
            latestSequence: session.relaySequence,
            messages,
        };
    }
    requireSession(sessionId) {
        const session = this.sessions.get(normalizeText(sessionId));
        if (!session) {
            throw new Error(`Unknown debug session: ${sessionId}`);
        }
        return session;
    }
    requireParticipant(sessionId, actor) {
        const session = this.requireSession(sessionId);
        const normalizedActor = normalizeActor(actor);
        const participant = session.participants.find((entry) => entry.actor === normalizedActor);
        if (!participant) {
            throw new Error(`Actor ${normalizedActor} is not part of debug session ${sessionId}`);
        }
        participant.lastSeenAt = nowIso();
        session.updatedAt = participant.lastSeenAt;
        return session;
    }
}
function sendError(response, error) {
    const message = error instanceof Error ? error.message : 'Unexpected debug collaboration error';
    const statusCode = message.startsWith('Unknown debug session') ? 404 : 400;
    return response.status(statusCode).json({ error: message });
}
function requireRequestText(value, fallback = '') {
    const normalized = normalizeText(value, fallback);
    if (!normalized) {
        throw new Error('Required field is missing');
    }
    return normalized;
}
export async function initializeDebugSessionCollaborationRoutes(service) {
    const router = Router();
    router.get('/api/debug-sessions', (request, response) => {
        const workspaceId = normalizeText(request.query.workspaceId);
        response.json({ sessions: service.listSessions(workspaceId || undefined) });
    });
    router.post('/api/debug-sessions', (request, response) => {
        try {
            const session = service.createSession({
                workspaceId: requireRequestText(request.body?.workspaceId),
                actor: requireRequestText(request.body?.actor),
                debuggerName: requireRequestText(request.body?.debuggerName, 'Debugger'),
                debuggerProgram: requireRequestText(request.body?.debuggerProgram),
                debuggerCwd: requireRequestText(request.body?.debuggerCwd),
                relayTarget: normalizeText(request.body?.relayTarget) || undefined,
            });
            response.status(201).json(session);
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.get('/api/debug-sessions/:sessionId', (request, response) => {
        try {
            response.json(service.getSession(request.params.sessionId));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.get('/api/debug-sessions/:sessionId/relay/messages', (request, response) => {
        try {
            const actor = requireRequestText(request.query.actor);
            const since = normalizeNumber(request.query.since, 0);
            response.json(service.listRelayMessages(request.params.sessionId, actor, since));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.post('/api/debug-sessions/:sessionId/join', (request, response) => {
        try {
            const session = service.joinSession(request.params.sessionId, requireRequestText(request.body?.actor), normalizeText(request.body?.role) || 'collaborator');
            response.json(session);
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.post('/api/debug-sessions/:sessionId/leave', (request, response) => {
        try {
            response.json(service.leaveSession(request.params.sessionId, requireRequestText(request.body?.actor)));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.put('/api/debug-sessions/:sessionId/breakpoints', (request, response) => {
        try {
            response.json(service.updateBreakpoints(request.params.sessionId, {
                actor: requireRequestText(request.body?.actor),
                breakpoints: Array.isArray(request.body?.breakpoints) ? request.body.breakpoints : [],
            }));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.put('/api/debug-sessions/:sessionId/variables', (request, response) => {
        try {
            response.json(service.updateVariables(request.params.sessionId, {
                actor: requireRequestText(request.body?.actor),
                variables: Array.isArray(request.body?.variables) ? request.body.variables : [],
            }));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.post('/api/debug-sessions/:sessionId/step', (request, response) => {
        try {
            response.json(service.recordStep(request.params.sessionId, {
                actor: requireRequestText(request.body?.actor),
                action: normalizeText(request.body?.action),
                note: normalizeText(request.body?.note) || undefined,
            }));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    router.post('/api/debug-sessions/:sessionId/relay', async (request, response) => {
        try {
            response.json(await service.relayDapMessage(request.params.sessionId, {
                actor: requireRequestText(request.body?.actor),
                message: typeof request.body?.message === 'object' && request.body.message ? request.body.message : {},
                relayTarget: normalizeText(request.body?.relayTarget) || undefined,
            }));
        }
        catch (error) {
            sendError(response, error);
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map