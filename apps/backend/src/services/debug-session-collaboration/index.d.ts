#!/usr/bin/env node
import { EventEmitter } from 'node:events';
import { Router } from 'express';
export type DebugSessionParticipantRole = 'owner' | 'collaborator' | 'observer';
export type DebugStepAction = 'continue' | 'next' | 'stepIn' | 'stepOut' | 'pause';
export interface DebugBreakpoint {
    id: string;
    filePath: string;
    line: number;
    column?: number;
    condition?: string;
    hitCondition?: string;
    logMessage?: string;
    verified: boolean;
}
export interface DebugVariableSnapshot {
    scope: string;
    name: string;
    value: string;
    type?: string;
    variablesReference?: number;
}
export interface DebugSessionParticipant {
    actor: string;
    role: DebugSessionParticipantRole;
    joinedAt: string;
    lastSeenAt: string;
}
export interface DebugStepEvent {
    id: string;
    actor: string;
    action: DebugStepAction;
    note?: string;
    timestamp: string;
}
export interface DebugRelayMessage {
    id: string;
    sequence: number;
    actor: string;
    message: Record<string, unknown>;
    relayTarget?: string;
    forwarded: boolean;
    timestamp: string;
}
export interface DebugRelaySyncResult {
    sessionId: string;
    relayTarget?: string;
    latestSequence: number;
    messages: DebugRelayMessage[];
}
export interface DebugSessionRecord {
    sessionId: string;
    workspaceId: string;
    debuggerName: string;
    debuggerProgram: string;
    debuggerCwd: string;
    owner: string;
    relayTarget?: string;
    participants: DebugSessionParticipant[];
    breakpoints: DebugBreakpoint[];
    variables: DebugVariableSnapshot[];
    stepEvents: DebugStepEvent[];
    relayMessages: DebugRelayMessage[];
    relaySequence: number;
    createdAt: string;
    updatedAt: string;
}
export interface CreateDebugSessionInput {
    workspaceId: string;
    actor: string;
    debuggerName: string;
    debuggerProgram: string;
    debuggerCwd: string;
    relayTarget?: string;
}
export interface UpdateDebugBreakpointsInput {
    actor: string;
    breakpoints: Array<Partial<DebugBreakpoint> & Pick<DebugBreakpoint, 'filePath' | 'line'>>;
}
export interface UpdateDebugVariablesInput {
    actor: string;
    variables: Array<Partial<DebugVariableSnapshot> & Pick<DebugVariableSnapshot, 'scope' | 'name' | 'value'>>;
}
export interface RecordDebugStepInput {
    actor: string;
    action: DebugStepAction;
    note?: string;
}
export interface RelayDebugMessageInput {
    actor: string;
    message: Record<string, unknown>;
    relayTarget?: string;
}
export declare class DebugSessionCollaborationService extends EventEmitter {
    private logger;
    private sessions;
    createSession(input: CreateDebugSessionInput): DebugSessionRecord;
    listSessions(workspaceId?: string): DebugSessionRecord[];
    getSession(sessionId: string): DebugSessionRecord;
    joinSession(sessionId: string, actor: string, role?: DebugSessionParticipantRole): DebugSessionRecord;
    leaveSession(sessionId: string, actor: string): DebugSessionRecord;
    updateBreakpoints(sessionId: string, input: UpdateDebugBreakpointsInput): DebugSessionRecord;
    updateVariables(sessionId: string, input: UpdateDebugVariablesInput): DebugSessionRecord;
    recordStep(sessionId: string, input: RecordDebugStepInput): DebugSessionRecord;
    relayDapMessage(sessionId: string, input: RelayDebugMessageInput): Promise<DebugSessionRecord>;
    listRelayMessages(sessionId: string, actor: string, sinceSequence?: number): DebugRelaySyncResult;
    private requireSession;
    private requireParticipant;
}
export declare function initializeDebugSessionCollaborationRoutes(service: DebugSessionCollaborationService): Promise<Router>;
//# sourceMappingURL=index.d.ts.map