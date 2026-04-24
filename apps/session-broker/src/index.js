#!/usr/bin/env ts-node
// @file        apps/session-broker/src/index.ts
// @module      session-management/broker
// @description Session broker service for per-user/per-session code-server isolation.
//              Routes authenticated users to isolated container contexts with resource quotas
//              and lifecycle management.
//
import express from 'express';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { v4 as uuidv4 } from 'uuid';
import Docker from 'dockerode';
import { Pool as PgPool } from 'pg';
import winston from 'winston';
import Joi from 'joi';
import axios from 'axios';
import cookieParser from 'cookie-parser';
import { APPROVED_SESSION_DATA_PROFILES, DEFAULT_SESSION_DATA_PROFILE, normalizeSessionDataProfile, } from './session-data-profile.js';
import { buildSessionProvenanceManifest, normalizeSessionProvenanceManifest, resolveSessionProvenanceManifest, } from './session-provenance.js';
import { buildSessionDeletionRecord, finalizeDeletionRecord, holdDeletionRecord, isDeletionHoldActive, isDeletionQuarantineExpired, normalizeSessionDeletionRecord, releaseDeletionHold, } from './session-deletion.js';
import { DEFAULT_SESSION_QUEUE_LANE, estimateQueueWaitSeconds, normalizeSessionQueueLane, } from './session-queue.js';
import { ACTIVE_SESSION_STATES, computeSessionAuditEventHash, createSessionAuditEvent, TERMINAL_SESSION_STATES, ensureCorrelationId, isTransitionAllowed, } from './session-policy.js';
import { authorizeBreakGlassTermination, authorizeSessionApproval, authorizeSessionLaunch, authorizeSessionTermination, authorizeSessionView, buildSessionBrokerPolicyMatrix, buildSessionBrokerPrincipal, DEFAULT_SESSION_BROKER_CONFIG, evaluateSessionPublication, isSessionApprovalPending, parseDelimitedValues, } from './session-access-control.js';
import { buildSessionPublicUrl, stripSessionPublicRoutePrefix } from './session-public-route.js';
import { createSessionBrokerTelemetryState, renderSessionBrokerPrometheusMetrics, } from './session-metrics.js';
import { assertReadSafeShadowReplayTraces, buildShadowReplayReport, normalizeShadowReplayMethod, normalizeShadowReplayPath, } from './session-shadow-replay.js';
import RedisSessionStore from './redis-session-store.js';
import { setupGracefulShutdown } from './shutdown.js';
class SessionPolicyError extends Error {
    constructor(statusCode, policyCode, message) {
        super(message);
        this.statusCode = statusCode;
        this.policyCode = policyCode;
    }
}
const readRequiredEnv = (name) => {
    const value = process.env[name];
    if (!value || value.trim() === '') {
        throw new Error(`[session-broker] Missing required environment variable: ${name}`);
    }
    return value.trim();
};
const readPositiveIntegerEnv = (name, fallback) => {
    const value = process.env[name] ?? fallback;
    const parsed = Number.parseInt(value, 10);
    if (!Number.isInteger(parsed) || parsed < 1) {
        throw new Error(`[session-broker] ${name} must be a positive integer`);
    }
    return parsed;
};
const readBooleanEnv = (name, fallback) => {
    const value = (process.env[name] ?? fallback).trim().toLowerCase();
    return ['1', 'true', 'yes', 'on'].includes(value);
};
const readCsvEnv = (name, fallback) => parseDelimitedValues(process.env[name] ?? fallback);
const SESSION_CREATE_RATE_LIMIT_WINDOW_MS = 60000;
const SESSION_CREATE_RATE_LIMIT_MAX = 5;
const sessionCreateRateLimitState = new Map();
const enforceSessionCreateRateLimit = (identity) => {
    const now = Date.now();
    const state = sessionCreateRateLimitState.get(identity);
    if (!state || now - state.windowStartedAt >= SESSION_CREATE_RATE_LIMIT_WINDOW_MS) {
        sessionCreateRateLimitState.set(identity, { windowStartedAt: now, count: 1 });
        return { allowed: true };
    }
    if (state.count >= SESSION_CREATE_RATE_LIMIT_MAX) {
        const retryAfterSeconds = Math.max(1, Math.ceil((SESSION_CREATE_RATE_LIMIT_WINDOW_MS - (now - state.windowStartedAt)) / 1000));
        return { allowed: false, retryAfterSeconds };
    }
    state.count += 1;
    return { allowed: true };
};
const validateRuntimeConfig = () => {
    const sessionPublicDomain = process.env.DEV_SESSION_DOMAIN?.trim() || 'dev.kushnir.cloud';
    const config = {
        logLevel: process.env.LOG_LEVEL || 'info',
        dockerSocket: readRequiredEnv('DOCKER_SOCKET'),
        databaseUrl: readRequiredEnv('DATABASE_URL'),
        codeServerImageId: readRequiredEnv('CODE_SERVER_IMAGE_ID'),
        sessionProxyHost: readRequiredEnv('SESSION_PROXY_HOST'),
        provenanceManifest: buildSessionProvenanceManifest({
            provenanceImageDigest: readRequiredEnv('CODE_SERVER_IMAGE_ID'),
            provenanceAttestationRef: process.env.SESSION_PROVENANCE_ATTESTATION_REF?.trim() || 'rekor://attestations/session-broker@v1',
            provenanceSignerIdentity: process.env.SESSION_PROVENANCE_SIGNER_IDENTITY?.trim() || 'github.com/kushin77/code-server/.github/workflows/verified-build.yml',
            provenanceVerifiedAt: readRequiredEnv('SESSION_PROVENANCE_VERIFIED_AT'),
            provenancePolicyVersion: process.env.SESSION_PROVENANCE_POLICY_VERSION?.trim() || 'v1.0.0',
            provenanceFreshnessHours: readPositiveIntegerEnv('SESSION_PROVENANCE_FRESHNESS_HOURS', '24'),
            provenanceVerificationResult: process.env.SESSION_PROVENANCE_VERIFICATION_RESULT?.trim() || 'verified',
        }),
        sessionStorageRoot: process.env.SESSIONS_ROOT?.trim() || '/var/lib/code-server-sessions',
        sessionApprovalRequired: readBooleanEnv('SESSION_APPROVAL_REQUIRED', 'false'),
        sessionCpuLimit: readRequiredEnv('SESSION_CPU_LIMIT'),
        sessionMemoryLimit: readRequiredEnv('SESSION_MEMORY_LIMIT'),
        sessionStorageLimit: readRequiredEnv('SESSION_STORAGE_LIMIT'),
        sessionMaxConcurrentPerUser: readPositiveIntegerEnv('SESSION_MAX_CONCURRENT_PER_USER', '1'),
        sessionMaxConcurrentPerTeam: readPositiveIntegerEnv('SESSION_MAX_CONCURRENT_PER_TEAM', '3'),
        sessionMaxRuntimeSeconds: readPositiveIntegerEnv('SESSION_MAX_RUNTIME_SECONDS', '28800'),
        sessionMaxInactivitySeconds: readPositiveIntegerEnv('SESSION_MAX_INACTIVITY_SECONDS', '7200'),
        sessionUsageWindowHours: readPositiveIntegerEnv('SESSION_USAGE_WINDOW_HOURS', '24'),
        sessionDeletionQuarantineHours: readPositiveIntegerEnv('SESSION_DELETION_QUARANTINE_HOURS', '24'),
        sessionPublicBaseUrl: process.env.SESSION_PUBLIC_BASE_URL?.trim() || `https://${sessionPublicDomain}`,
        adminGroups: readCsvEnv('SESSION_ADMIN_GROUPS', DEFAULT_SESSION_BROKER_CONFIG.adminGroups.join(',')),
        operatorGroups: readCsvEnv('SESSION_OPERATOR_GROUPS', DEFAULT_SESSION_BROKER_CONFIG.operatorGroups.join(',')),
        approverGroups: readCsvEnv('SESSION_APPROVER_GROUPS', DEFAULT_SESSION_BROKER_CONFIG.approverGroups.join(',')),
        auditorGroups: readCsvEnv('SESSION_AUDITOR_GROUPS', DEFAULT_SESSION_BROKER_CONFIG.auditorGroups.join(',')),
        breakGlassGroups: readCsvEnv('SESSION_BREAK_GLASS_GROUPS', DEFAULT_SESSION_BROKER_CONFIG.breakGlassGroups.join(',')),
    };
    if (!/^postgres(?:ql)?:\/\//.test(config.databaseUrl)) {
        throw new Error('[session-broker] DATABASE_URL must be a PostgreSQL connection string');
    }
    if (!/^\d+(?:\.\d+)?$/.test(config.sessionCpuLimit)) {
        throw new Error('[session-broker] SESSION_CPU_LIMIT must be a numeric CPU quota');
    }
    if (!/^\d+[kKmMgG]$/.test(config.sessionMemoryLimit)) {
        throw new Error('[session-broker] SESSION_MEMORY_LIMIT must use k, m, or g units');
    }
    if (!/^\d+[kKmMgG]$/.test(config.sessionStorageLimit)) {
        throw new Error('[session-broker] SESSION_STORAGE_LIMIT must use k, m, or g units');
    }
    return config;
};
const runtimeConfig = validateRuntimeConfig();
process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection in session-broker', {
        reason: reason instanceof Error ? reason.message : String(reason),
    });
});
const getSessionContainerUrl = (sessionPort) => `http://${runtimeConfig.sessionProxyHost}:${sessionPort}`;
const getSessionPublicUrl = (sessionId) => buildSessionPublicUrl(runtimeConfig.sessionPublicBaseUrl, sessionId);
const proxySessionContainerRequest = async (req, res, session, forwardedPath) => {
    const publicationDecision = evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired);
    if (!publicationDecision.allowed) {
        res.status(publicationDecision.statusCode).json({
            error: publicationDecision.reason,
            policyCode: publicationDecision.policyCode,
            sessionId: session.sessionId,
            approvalRequired: runtimeConfig.sessionApprovalRequired,
            approvalPending: isSessionApprovalPending(session.status, runtimeConfig.sessionApprovalRequired),
        });
        return;
    }
    await manager.updateActivity(session.sessionId);
    res.cookie('_code_server_session_id', session.sessionId, {
        httpOnly: true,
        secure: true,
        sameSite: 'lax',
        maxAge: 86400 * 1000,
    });
    logger.info('Proxying to session container', {
        sessionId: session.sessionId,
        containerPort: session.containerPort,
        path: forwardedPath,
    });
    const targetUrl = `${getSessionContainerUrl(session.containerPort)}${forwardedPath}`;
    try {
        const response = await axios({
            method: req.method,
            url: targetUrl,
            headers: req.headers,
            data: req.method !== 'GET' && req.method !== 'HEAD' ? req.body : undefined,
            validateStatus: () => true,
        });
        res.status(response.status);
        Object.entries(response.headers).forEach(([key, value]) => {
            if (!['content-encoding', 'transfer-encoding'].includes(key.toLowerCase())) {
                res.setHeader(key, value);
            }
        });
        res.send(response.data);
    }
    catch (proxyError) {
        logger.error('Proxy error', {
            sessionId: session.sessionId,
            error: String(proxyError),
        });
        res.status(502).json({ error: 'Failed to proxy request to session container' });
    }
};
// ────────────────────────────────────────────────────────────────────────────
// Logging Setup
// ────────────────────────────────────────────────────────────────────────────
const logger = winston.createLogger({
    level: runtimeConfig.logLevel,
    format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'session-broker.log' })
    ]
});
const sessionBrokerTelemetry = createSessionBrokerTelemetryState();
// ────────────────────────────────────────────────────────────────────────────
// Session Manager Class
// ────────────────────────────────────────────────────────────────────────────
class SessionManager {
    constructor(runtimeConfig) {
        this.sessions = new Map();
        this.sessionEvents = new Map();
        this.sessionEventHashes = new Map();
        this.deletionManifests = new Map();
        this.shadowReplayArtifacts = new Map();
        this.nextPort = 8081; // Start at 8081 (8080 is primary)
        this.useRedis = false;
        // Flag to control session acceptance (checked at route level)
        this.acceptingNewSessions = true;
        this.runtimeConfig = runtimeConfig;
        const socketPath = runtimeConfig.dockerSocket.replace('unix://', '');
        this.docker = new Docker({ socketPath });
        this.db = new PgPool({ connectionString: runtimeConfig.databaseUrl });
        // Check if Redis is available (optional feature flag)
        this.useRedis = process.env.SESSION_USE_REDIS === 'true' || process.env.SESSION_USE_REDIS === '1';
        logger.info('SessionManager initialized', {
            socketPath,
            codeServerImageId: runtimeConfig.codeServerImageId,
            redisEnabled: this.useRedis,
        });
    }
    /**
     * Initialize Redis session store if enabled
     */
    async initializeRedisStore() {
        if (!this.useRedis) {
            logger.info('Redis session store disabled (SESSION_USE_REDIS not set)');
            return;
        }
        try {
            this.redisStore = new RedisSessionStore();
            await this.redisStore.connect();
            logger.info('Redis session store initialized successfully');
        }
        catch (error) {
            logger.error('Failed to initialize Redis session store', { error });
            if (process.env.SESSION_REDIS_REQUIRED === 'true') {
                throw error;
            }
            // Continue with in-memory fallback if Redis is optional
            this.useRedis = false;
        }
    }
    recordSessionEvent(event) {
        const previousEventHash = this.sessionEventHashes.get(event.sessionId);
        const storedEvent = createSessionAuditEvent({
            ...event,
            previousEventHash,
        });
        const trail = this.sessionEvents.get(storedEvent.sessionId) ?? [];
        trail.push(storedEvent);
        this.sessionEvents.set(event.sessionId, trail);
        this.sessionEventHashes.set(storedEvent.sessionId, storedEvent.eventHash);
        const session = this.sessions.get(event.sessionId);
        if (session) {
            session.auditTrail.push(storedEvent);
        }
        // Store in Redis if enabled
        if (this.useRedis && this.redisStore) {
            this.redisStore.storeAuditEvent(event.sessionId, storedEvent).catch((error) => {
                logger.error('Failed to store audit event in Redis', { sessionId: event.sessionId, error });
            });
        }
        return storedEvent;
    }
    getSessionEvents(sessionId) {
        // Try Redis first if enabled
        if (this.useRedis && this.redisStore) {
            try {
                // Note: This should ideally be async, but keeping sync interface for compatibility
                logger.warn('Redis store async operation called from sync context', { sessionId });
            }
            catch (error) {
                logger.error('Error accessing Redis for session events', { sessionId, error });
            }
        }
        const events = this.sessionEvents.get(sessionId) ?? [];
        return [...events];
    }
    getDeletionManifest(sessionId) {
        return this.deletionManifests.get(sessionId);
    }
    getShadowReplayArtifact(sessionId) {
        return this.shadowReplayArtifacts.get(sessionId);
    }
    async getSessionEvidenceBundle(sessionId) {
        let shadowReplayArtifact = this.getShadowReplayArtifact(sessionId) ?? null;
        if (!shadowReplayArtifact) {
            const reportPath = this.getSessionShadowReplayReportPath(sessionId);
            try {
                const raw = await fs.readFile(reportPath, 'utf8');
                const parsed = JSON.parse(raw);
                shadowReplayArtifact = {
                    report: parsed,
                    reportPath,
                };
                this.shadowReplayArtifacts.set(sessionId, shadowReplayArtifact);
            }
            catch {
                shadowReplayArtifact = null;
            }
        }
        return {
            sessionId,
            generatedAt: new Date().toISOString(),
            events: this.getSessionEvents(sessionId),
            deletion: this.getDeletionManifest(sessionId) ?? null,
            shadowReplay: shadowReplayArtifact,
        };
    }
    getApprovalStatus(session) {
        if (!this.runtimeConfig.sessionApprovalRequired) {
            return 'not_required';
        }
        if (session.status === 'testing') {
            return 'pending';
        }
        return 'approved';
    }
    async getQueuedSessions() {
        const result = await this.db.query(`SELECT *
       FROM sessions
       WHERE status = 'queued'
       ORDER BY CASE WHEN queue_lane = 'fast' THEN 0 ELSE 1 END,
                COALESCE(queue_position, 0) ASC,
                created_at ASC`, []);
        return result.rows.map((row) => this.dbRowToSession(row));
    }
    async getQueueState(sessionId) {
        const queuedSessions = await this.getQueuedSessions();
        const index = queuedSessions.findIndex((session) => session.sessionId === sessionId);
        if (index < 0) {
            return null;
        }
        const session = queuedSessions[index];
        const queueLane = session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE;
        return {
            queuePosition: index + 1,
            estimatedWaitSeconds: estimateQueueWaitSeconds(index + 1, queueLane),
            queueLane,
        };
    }
    async getQueuePositionForLane(queueLane) {
        const queuedSessions = await this.getQueuedSessions();
        const nextSession = {
            sessionId: '__pending__',
            queueLane,
            queuedAt: Date.now(),
            sequence: queuedSessions.length + 1,
        };
        return [...queuedSessions.map((session, index) => ({
                sessionId: session.sessionId,
                queueLane: session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                queuedAt: session.queueEnqueuedAt?.getTime() ?? session.createdAt.getTime(),
                sequence: index + 1,
            })), nextSession]
            .sort((left, right) => {
            if (left.queueLane !== right.queueLane) {
                return left.queueLane === 'fast' ? -1 : 1;
            }
            if (left.queuedAt !== right.queuedAt) {
                return left.queuedAt - right.queuedAt;
            }
            return left.sequence - right.sequence;
        })
            .findIndex((entry) => entry.sessionId === '__pending__') + 1;
    }
    async buildQueuedSession(userId, username, email, ttlSeconds, teamId, correlationId, dataProfile, queueLane) {
        const resolvedTeamId = this.resolveTeamId(email, teamId);
        const sessionId = uuidv4();
        const containerName = `code-server-${username}-${sessionId.substring(0, 8)}`;
        const containerPort = this.nextPort++;
        const queuePosition = await this.getQueuePositionForLane(queueLane);
        const provenance = resolveSessionProvenanceManifest({
            provenanceImageDigest: this.runtimeConfig.codeServerImageId,
            provenanceAttestationRef: this.runtimeConfig.provenanceManifest.attestationRef,
            provenanceSignerIdentity: this.runtimeConfig.provenanceManifest.signerIdentity,
            provenanceVerifiedAt: this.runtimeConfig.provenanceManifest.verifiedAt,
            provenancePolicyVersion: this.runtimeConfig.provenanceManifest.policyVersion,
            provenanceFreshnessHours: this.runtimeConfig.provenanceManifest.freshnessHours,
            provenanceVerificationResult: this.runtimeConfig.provenanceManifest.verificationResult,
        });
        const session = {
            sessionId,
            userId,
            teamId: resolvedTeamId,
            username,
            email,
            dataProfile,
            dataProfileValidated: true,
            provenance,
            queueLane,
            queueReason: `queued because ${queueLane === 'fast' ? 'fast lane' : 'standard lane'} capacity was exhausted`,
            queuePosition,
            queueEnqueuedAt: new Date(),
            queueEstimatedWaitSeconds: estimateQueueWaitSeconds(queuePosition, queueLane),
            containerName,
            containerPort,
            baseImageId: this.runtimeConfig.codeServerImageId,
            createdAt: new Date(),
            expiresAt: new Date(Date.now() + ttlSeconds * 1000),
            quotas: {
                cpuLimit: this.runtimeConfig.sessionCpuLimit,
                memoryLimit: this.runtimeConfig.sessionMemoryLimit,
                storageLimit: this.runtimeConfig.sessionStorageLimit,
            },
            status: 'queued',
            lastActivity: new Date(),
            auditTrail: [],
        };
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId,
            actor: userId,
            action: 'create',
            fromStatus: 'requested',
            toStatus: 'queued',
            reason: session.queueReason,
            correlationId,
            details: {
                teamId: resolvedTeamId,
                queueLane,
                queuePosition,
                estimatedWaitSeconds: session.queueEstimatedWaitSeconds,
            },
        }));
        await this.persistSession(session);
        this.sessions.set(sessionId, session);
        return session;
    }
    async provisionSession(session, correlationId) {
        const resolvedCorrelationId = ensureCorrelationId(correlationId);
        if (session.status === 'queued') {
            this.transitionSession(session, 'provisioning', 'queue slot available', resolvedCorrelationId);
        }
        else {
            this.transitionSession(session, 'provisioning', 'creating container', resolvedCorrelationId);
        }
        const containerConfig = this.buildContainerConfig(session);
        const container = await this.docker.createContainer({
            name: session.containerName,
            Hostname: containerConfig.hostname,
            Image: containerConfig.image,
            Env: Object.entries(containerConfig.env).map(([k, v]) => `${k}=${v}`),
            ExposedPorts: {
                '8080/tcp': {}
            },
            HostConfig: {
                PortBindings: {
                    '8080/tcp': [{ HostPort: String(session.containerPort) }]
                },
                Binds: Object.entries(containerConfig.volumes).map(([target, src]) => `${src.bind}:${target}:${src.ro ? 'ro' : 'rw'}`),
                CpuQuota: parseInt(containerConfig.cpuLimit.replace(/^(\d+)\..*$/, '$1000000'), 10),
                Memory: this.parseMemory(containerConfig.memoryLimit)
            }
        });
        session.containerId = container.id;
        await container.start();
        this.transitionSession(session, 'ready', 'container started', resolvedCorrelationId);
        if (this.runtimeConfig.sessionApprovalRequired) {
            this.transitionSession(session, 'testing', 'awaiting approval gate', resolvedCorrelationId);
        }
        await this.persistSession(session);
        this.sessions.set(session.sessionId, session);
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId: session.sessionId,
            actor: session.userId,
            action: 'create',
            fromStatus: 'requested',
            toStatus: session.status,
            reason: session.queueLane ? 'queued session launched' : 'session created',
            correlationId: resolvedCorrelationId,
            details: {
                teamId: session.teamId,
                containerPort: session.containerPort,
                queueLane: session.queueLane,
            },
        }));
        logger.info('Session created successfully', {
            sessionId: session.sessionId,
            containerId: container.id.substring(0, 12),
            containerName: session.containerName,
            containerPort: session.containerPort,
            expiresAt: session.expiresAt,
            queueLane: session.queueLane,
        });
        return session;
    }
    async processQueuedSessions(triggerCorrelationId) {
        const queuedSessions = await this.getQueuedSessions();
        if (queuedSessions.length === 0) {
            return 0;
        }
        let launched = 0;
        for (const queuedSession of queuedSessions) {
            const counts = await this.getSessionCountsForPolicy(queuedSession.userId, queuedSession.teamId);
            if (counts.userCount >= this.runtimeConfig.sessionMaxConcurrentPerUser) {
                continue;
            }
            if (counts.teamCount >= this.runtimeConfig.sessionMaxConcurrentPerTeam) {
                continue;
            }
            try {
                await this.provisionSession(queuedSession, triggerCorrelationId);
                launched += 1;
            }
            catch (error) {
                logger.warn('Failed to launch queued session', {
                    sessionId: queuedSession.sessionId,
                    error: String(error),
                });
            }
        }
        return launched;
    }
    verifyAuditIntegrity(sessionId) {
        const events = this.sessionEvents.get(sessionId) ?? [];
        let previousEventHash;
        for (const event of events) {
            const expectedHash = computeSessionAuditEventHash({
                ...event,
                previousEventHash,
            });
            if (event.eventHash !== expectedHash) {
                return {
                    valid: false,
                    eventCount: events.length,
                    lastEventHash: previousEventHash,
                    reason: `audit hash mismatch for event ${event.eventId}`,
                };
            }
            previousEventHash = event.eventHash;
        }
        return {
            valid: true,
            eventCount: events.length,
            lastEventHash: previousEventHash,
        };
    }
    async approveSession(sessionId, approver, correlationId) {
        const session = await this.getSession(sessionId);
        if (!session) {
            throw new SessionPolicyError(404, 'session_not_found', 'Session not found');
        }
        const approvalDecision = authorizeSessionApproval(approver);
        if (!approvalDecision.allowed) {
            throw new SessionPolicyError(approvalDecision.statusCode, approvalDecision.policyCode, approvalDecision.reason);
        }
        if (!isSessionApprovalPending(session.status, this.runtimeConfig.sessionApprovalRequired)) {
            throw new SessionPolicyError(409, 'approval_not_pending', 'Session does not require approval');
        }
        const resolvedCorrelationId = ensureCorrelationId(correlationId);
        this.transitionSession(session, 'ready', 'approval granted', resolvedCorrelationId);
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId,
            actor: approver.userId,
            action: 'approve',
            fromStatus: 'testing',
            toStatus: 'ready',
            reason: 'approval granted',
            correlationId: resolvedCorrelationId,
            details: {
                approver: approver.username,
                approverEmail: approver.email,
            },
        }));
        await this.persistSession(session);
        return session;
    }
    getSessionStoragePaths(sessionId) {
        const storageRoot = path.join(this.runtimeConfig.sessionStorageRoot, sessionId);
        return {
            storageRoot,
            workspacePath: path.join(storageRoot, 'workspace'),
            profilePath: path.join(storageRoot, 'profile'),
        };
    }
    getSessionEvidenceRoot(sessionId) {
        const { storageRoot } = this.getSessionStoragePaths(sessionId);
        return path.join(storageRoot, 'evidence');
    }
    getSessionShadowReplayReportPath(sessionId) {
        return path.join(this.getSessionEvidenceRoot(sessionId), 'shadow-replay-report.json');
    }
    getSessionQuarantinePath(sessionId) {
        return path.join(this.runtimeConfig.sessionStorageRoot, 'quarantine', sessionId);
    }
    async sessionPathExists(targetPath) {
        try {
            await fs.access(targetPath);
            return true;
        }
        catch {
            return false;
        }
    }
    async quarantineSessionStorage(sessionId) {
        const { storageRoot } = this.getSessionStoragePaths(sessionId);
        const quarantineRoot = this.getSessionQuarantinePath(sessionId);
        const removed = [];
        if (await this.sessionPathExists(storageRoot)) {
            await fs.mkdir(path.dirname(quarantineRoot), { recursive: true });
            await fs.rm(quarantineRoot, { recursive: true, force: true }).catch(() => undefined);
            await fs.rename(storageRoot, quarantineRoot);
            removed.push(storageRoot);
            removed.push(quarantineRoot);
        }
        return removed;
    }
    async purgeQuarantineStorage(sessionId) {
        const { storageRoot } = this.getSessionStoragePaths(sessionId);
        const quarantineRoot = this.getSessionQuarantinePath(sessionId);
        const removed = [];
        if (await this.sessionPathExists(storageRoot)) {
            await fs.rm(storageRoot, { recursive: true, force: true });
            removed.push(storageRoot);
        }
        if (await this.sessionPathExists(quarantineRoot)) {
            await fs.rm(quarantineRoot, { recursive: true, force: true });
            removed.push(quarantineRoot);
        }
        return removed;
    }
    async buildDeletionManifest(session, actor, reason, correlationId, quarantinePhase = 'quarantined', cleanupErrors = [], resourcesRemoved = [], resourcesRemaining = []) {
        const { storageRoot, workspacePath, profilePath } = this.getSessionStoragePaths(session.sessionId);
        const quarantineRoot = this.getSessionQuarantinePath(session.sessionId);
        const currentRemoved = [...resourcesRemoved];
        const currentRemaining = [...resourcesRemaining];
        for (const resourcePath of [workspacePath, profilePath, storageRoot, quarantineRoot]) {
            if (await this.sessionPathExists(resourcePath)) {
                if (!currentRemaining.includes(resourcePath)) {
                    currentRemaining.push(resourcePath);
                }
            }
            else {
                if (!currentRemoved.includes(resourcePath)) {
                    currentRemoved.push(resourcePath);
                }
            }
        }
        if (session.containerId) {
            const containerRef = `container:${session.containerId}`;
            if (!currentRemoved.includes(containerRef)) {
                currentRemoved.push(containerRef);
            }
        }
        const manifest = buildSessionDeletionRecord({
            sessionId: session.sessionId,
            actor,
            reason,
            correlationId,
            quarantineHours: this.runtimeConfig.sessionDeletionQuarantineHours,
            resourcesBefore: {
                containerId: session.containerId,
                containerName: session.containerName,
                storageRoot,
                quarantineRoot,
                workspacePath,
                profilePath,
                sessionRecordPresent: true,
            },
            resourcesRemoved: currentRemoved,
            resourcesRemaining: currentRemaining,
            errors: cleanupErrors,
        });
        return {
            ...manifest,
            status: quarantinePhase,
            residualResourceZero: quarantinePhase !== 'quarantined' && currentRemaining.length === 0,
            purgedAt: quarantinePhase === 'completed' ? new Date().toISOString() : manifest.purgedAt,
        };
    }
    cleanupSessionContainer(containerId) {
        if (!containerId) {
            return Promise.resolve();
        }
        const container = this.docker.getContainer(containerId);
        return container
            .remove({ v: true, force: true })
            .catch((cleanupError) => {
            logger.warn('Partial session cleanup failed', { containerId, error: String(cleanupError) });
        });
    }
    isActiveStatus(status) {
        return ACTIVE_SESSION_STATES.includes(status);
    }
    resolveTeamId(email, teamId) {
        if (teamId && teamId.trim() !== '') {
            return teamId.trim().toLowerCase();
        }
        const domain = email.split('@')[1]?.trim().toLowerCase();
        return domain || 'default-team';
    }
    parseCpuQuota(cpuLimit) {
        const parsed = Number.parseFloat(cpuLimit);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
    }
    getUsageWindowCutoff(windowHours) {
        return new Date(Date.now() - windowHours * 60 * 60 * 1000);
    }
    async getSessionCountsForPolicy(userId, teamId) {
        const userResult = await this.db.query('SELECT COUNT(*)::int AS count FROM sessions WHERE user_id = $1 AND status = ANY($2::text[])', [userId, ACTIVE_SESSION_STATES]);
        const teamResult = await this.db.query(`SELECT COUNT(*)::int AS count
       FROM sessions
       WHERE LOWER(SPLIT_PART(email, '@', 2)) = $1
         AND status = ANY($2::text[])`, [teamId, ACTIVE_SESSION_STATES]);
        return {
            userCount: Number(userResult.rows[0]?.count ?? 0),
            teamCount: Number(teamResult.rows[0]?.count ?? 0),
        };
    }
    async enforceLaunchPolicy(userId, email, ttlSeconds, dataProfile) {
        if (ttlSeconds > this.runtimeConfig.sessionMaxRuntimeSeconds) {
            sessionBrokerTelemetry.launchDenialsTotal += 1;
            sessionBrokerTelemetry.launchDenialsByPolicy.runtime_ttl_exceeded = (sessionBrokerTelemetry.launchDenialsByPolicy.runtime_ttl_exceeded ?? 0) + 1;
            throw new SessionPolicyError(422, 'runtime_ttl_exceeded', `Requested TTL ${ttlSeconds}s exceeds max runtime policy ${this.runtimeConfig.sessionMaxRuntimeSeconds}s`);
        }
        const approvedDataProfile = normalizeSessionDataProfile(dataProfile);
        if (!approvedDataProfile) {
            sessionBrokerTelemetry.launchDenialsTotal += 1;
            sessionBrokerTelemetry.launchDenialsByPolicy.data_profile_not_approved = (sessionBrokerTelemetry.launchDenialsByPolicy.data_profile_not_approved ?? 0) + 1;
            throw new SessionPolicyError(422, 'data_profile_not_approved', `Requested data profile must be one of: ${APPROVED_SESSION_DATA_PROFILES.join(', ')}`);
        }
        return approvedDataProfile;
    }
    normalizeStatus(status) {
        if (!status) {
            return 'failed';
        }
        if (status === 'creating') {
            return 'requested';
        }
        if (status === 'queued') {
            return 'queued';
        }
        if (status === 'running') {
            return 'ready';
        }
        if (status === 'paused') {
            return 'testing';
        }
        if (status === 'terminated') {
            return 'destroyed';
        }
        if (ACTIVE_SESSION_STATES.includes(status) || TERMINAL_SESSION_STATES.includes(status)) {
            return status;
        }
        return 'failed';
    }
    transitionSession(session, nextStatus, reason, correlationId) {
        const previousStatus = session.status;
        if (previousStatus === nextStatus) {
            return session;
        }
        if (!isTransitionAllowed(previousStatus, nextStatus)) {
            const policyError = new SessionPolicyError(409, 'invalid_transition', `Invalid lifecycle transition from ${previousStatus} to ${nextStatus}`);
            this.recordSessionEvent(createSessionAuditEvent({
                sessionId: session.sessionId,
                actor: 'system',
                action: 'deny',
                fromStatus: previousStatus,
                toStatus: nextStatus,
                reason: policyError.message,
                correlationId: ensureCorrelationId(correlationId),
                details: { reason },
            }));
            throw policyError;
        }
        logger.info('Session lifecycle transition', {
            sessionId: session.sessionId,
            userId: session.userId,
            from: previousStatus,
            to: nextStatus,
            reason,
        });
        session.status = nextStatus;
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId: session.sessionId,
            actor: 'system',
            action: 'transition',
            fromStatus: previousStatus,
            toStatus: nextStatus,
            reason,
            correlationId: ensureCorrelationId(correlationId),
        }));
        return session;
    }
    /**
     * Create isolated session for authenticated user
     */
    async createSession(userId, username, email, ttlSeconds = 28800, teamId, correlationId, dataProfile = DEFAULT_SESSION_DATA_PROFILE, priorityLane = DEFAULT_SESSION_QUEUE_LANE, provenanceInput) {
        const approvedDataProfile = await this.enforceLaunchPolicy(userId, email, ttlSeconds, dataProfile);
        const existingSession = await this.getUserActiveSession(userId);
        if (existingSession) {
            logger.info('Returning existing active session', {
                userId,
                sessionId: existingSession.sessionId,
                status: existingSession.status,
            });
            return existingSession;
        }
        const resolvedTeamId = this.resolveTeamId(email, teamId);
        const resolvedCorrelationId = ensureCorrelationId(correlationId);
        const existingQueuedSession = await this.getUserQueuedSession(userId);
        if (existingQueuedSession) {
            logger.info('Returning existing queued session', {
                userId,
                sessionId: existingQueuedSession.sessionId,
                queueLane: existingQueuedSession.queueLane,
                queuePosition: existingQueuedSession.queuePosition,
            });
            return existingQueuedSession;
        }
        const counts = await this.getSessionCountsForPolicy(userId, resolvedTeamId);
        const shouldQueue = counts.userCount >= this.runtimeConfig.sessionMaxConcurrentPerUser || counts.teamCount >= this.runtimeConfig.sessionMaxConcurrentPerTeam;
        if (shouldQueue) {
            const queuedSession = await this.buildQueuedSession(userId, username, email, ttlSeconds, teamId, resolvedCorrelationId, approvedDataProfile, normalizeSessionQueueLane(priorityLane));
            sessionBrokerTelemetry.queuedLaunchesTotal += 1;
            logger.info('Session queued due to quota pressure', {
                sessionId: queuedSession.sessionId,
                userId,
                teamId: resolvedTeamId,
                queueLane: queuedSession.queueLane,
                queuePosition: queuedSession.queuePosition,
                estimatedWaitSeconds: queuedSession.queueEstimatedWaitSeconds,
            });
            return queuedSession;
        }
        const sessionId = uuidv4();
        const containerName = `code-server-${username}-${sessionId.substring(0, 8)}`;
        const containerPort = this.nextPort++;
        const codeServerPassword = crypto.randomBytes(32).toString('hex'); // 64-char hex = 32-byte entropy
        logger.info('Creating session', { sessionId, userId, username, containerPort, queueLane: normalizeSessionQueueLane(priorityLane) });
        const session = {
            sessionId,
            userId,
            teamId: resolvedTeamId,
            username,
            email,
            dataProfile: approvedDataProfile,
            dataProfileValidated: true,
            provenance: resolveSessionProvenanceManifest({
                provenanceImageDigest: this.runtimeConfig.codeServerImageId,
                provenanceAttestationRef: this.runtimeConfig.provenanceManifest.attestationRef,
                provenanceSignerIdentity: this.runtimeConfig.provenanceManifest.signerIdentity,
                provenanceVerifiedAt: this.runtimeConfig.provenanceManifest.verifiedAt,
                provenancePolicyVersion: this.runtimeConfig.provenanceManifest.policyVersion,
                provenanceFreshnessHours: this.runtimeConfig.provenanceManifest.freshnessHours,
                provenanceVerificationResult: this.runtimeConfig.provenanceManifest.verificationResult,
            }, provenanceInput),
            codeServerPassword,
            containerName,
            containerPort,
            baseImageId: this.runtimeConfig.codeServerImageId,
            createdAt: new Date(),
            expiresAt: new Date(Date.now() + ttlSeconds * 1000),
            quotas: {
                cpuLimit: this.runtimeConfig.sessionCpuLimit,
                memoryLimit: this.runtimeConfig.sessionMemoryLimit,
                storageLimit: this.runtimeConfig.sessionStorageLimit,
            },
            status: 'requested',
            lastActivity: new Date(),
            auditTrail: [],
        };
        try {
            return await this.provisionSession(session, resolvedCorrelationId);
        }
        catch (error) {
            logger.error('Failed to create session', { sessionId: session.sessionId, error: String(error) });
            if (session) {
                try {
                    this.transitionSession(session, 'failed', 'session creation failed', resolvedCorrelationId);
                }
                catch (transitionError) {
                    logger.warn('Failed to mark session as failed', {
                        sessionId: session.sessionId,
                        error: String(transitionError),
                    });
                }
                await this.cleanupSessionContainer(session.containerId);
                await this.persistSession(session);
            }
            throw new Error(`Session creation failed: ${error}`);
        }
    }
    async launchSession(userId, username, email, ttlSeconds = 28800, teamId, correlationId, dataProfile = DEFAULT_SESSION_DATA_PROFILE, priorityLane = DEFAULT_SESSION_QUEUE_LANE, provenanceInput) {
        return this.createSession(userId, username, email, ttlSeconds, teamId, correlationId, dataProfile, priorityLane, provenanceInput);
    }
    /**
     * Get existing session by ID
     */
    async getSession(sessionId) {
        // Check memory cache first
        if (this.sessions.has(sessionId)) {
            const session = this.sessions.get(sessionId);
            session.lastActivity = new Date();
            return session;
        }
        // Try Redis if enabled
        if (this.useRedis && this.redisStore) {
            try {
                const redisSession = await this.redisStore.getSession(sessionId);
                if (redisSession) {
                    // Cache in memory for fast subsequent access (cast to proper SessionContext type)
                    const typedSession = redisSession;
                    this.sessions.set(sessionId, typedSession);
                    typedSession.lastActivity = new Date();
                    return typedSession;
                }
            }
            catch (error) {
                logger.warn('Failed to retrieve session from Redis', { sessionId, error: String(error) });
                // Fall through to database query
            }
        }
        // Load from database
        try {
            const result = await this.db.query('SELECT * FROM sessions WHERE session_id = $1', [sessionId]);
            if (result.rows.length > 0) {
                const dbSession = this.dbRowToSession(result.rows[0]);
                this.sessions.set(sessionId, dbSession);
                // Also store in Redis for failover if enabled
                if (this.useRedis && this.redisStore) {
                    this.redisStore.storeSession(sessionId, dbSession).catch((error) => {
                        logger.warn('Failed to store session in Redis', { sessionId, error: String(error) });
                    });
                }
                return dbSession;
            }
        }
        catch (error) {
            logger.error('Database query failed', { sessionId, error: String(error) });
        }
        return null;
    }
    /**
     * Get active session for a user (returns most recent/active one)
     */
    async getUserActiveSession(userId) {
        try {
            const result = await this.db.query(`SELECT * FROM sessions 
         WHERE user_id = $1 AND status = ANY($2::text[])
         ORDER BY last_activity DESC 
         LIMIT 1`, [userId, ACTIVE_SESSION_STATES]);
            if (result.rows.length > 0) {
                const dbSession = this.dbRowToSession(result.rows[0]);
                this.sessions.set(dbSession.sessionId, dbSession);
                return dbSession;
            }
        }
        catch (error) {
            logger.error('Failed to get user session', { userId, error: String(error) });
        }
        return null;
    }
    async getUserQueuedSession(userId) {
        try {
            const result = await this.db.query(`SELECT * FROM sessions
         WHERE user_id = $1 AND status = 'queued'
         ORDER BY queue_enqueued_at ASC NULLS LAST, created_at ASC
         LIMIT 1`, [userId]);
            if (result.rows.length > 0) {
                const dbSession = this.dbRowToSession(result.rows[0]);
                this.sessions.set(dbSession.sessionId, dbSession);
                return dbSession;
            }
        }
        catch (error) {
            logger.error('Failed to get queued session', { userId, error: String(error) });
        }
        return null;
    }
    async getUsageSummary(windowHours = this.runtimeConfig.sessionUsageWindowHours) {
        const cutoff = this.getUsageWindowCutoff(windowHours);
        const result = await this.db.query(`SELECT
         LOWER(SPLIT_PART(email, '@', 2)) AS team_id,
         COUNT(*) FILTER (WHERE status = ANY($2::text[]))::int AS active_sessions,
         COUNT(*)::int AS created_sessions,
         COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_sessions,
         COALESCE(SUM(EXTRACT(EPOCH FROM (LEAST(COALESCE(expires_at, NOW()), NOW()) - created_at))), 0)::bigint AS total_runtime_seconds,
         MAX(last_activity) AS last_activity_at
       FROM sessions
       WHERE created_at >= $1
       GROUP BY team_id
       ORDER BY created_sessions DESC, team_id ASC`, [cutoff, ACTIVE_SESSION_STATES]);
        return result.rows.map((row) => ({
            teamId: row.team_id || 'default-team',
            activeSessions: Number(row.active_sessions ?? 0),
            createdSessions: Number(row.created_sessions ?? 0),
            failedSessions: Number(row.failed_sessions ?? 0),
            totalRuntimeSeconds: Number(row.total_runtime_seconds ?? 0),
            estimatedCpuHours: Number(((Number(row.total_runtime_seconds ?? 0) / 3600) * this.parseCpuQuota(this.runtimeConfig.sessionCpuLimit)).toFixed(2)),
            lastActivityAt: row.last_activity_at ? new Date(row.last_activity_at) : null,
        }));
    }
    async getSessionStatusCounts() {
        try {
            const result = await this.db.query('SELECT status, COUNT(*)::int AS count FROM sessions GROUP BY status ORDER BY status ASC');
            return result.rows.reduce((counts, row) => {
                counts[String(row.status || 'unknown')] = Number(row.count ?? 0);
                return counts;
            }, {});
        }
        catch (error) {
            logger.error('Failed to collect session status counts', { error: String(error) });
            return {};
        }
    }
    async getMetricsSnapshot(windowHours = this.runtimeConfig.sessionUsageWindowHours) {
        const [teams, statusCounts] = await Promise.all([
            this.getUsageSummary(windowHours),
            this.getSessionStatusCounts(),
        ]);
        // Collect Redis metrics if available
        let redisMetrics;
        if (this.redisStore) {
            try {
                redisMetrics = await this.redisStore.getMetrics();
            }
            catch (error) {
                logger.warn('Failed to gather Redis metrics', { error: String(error) });
            }
        }
        return {
            generatedAt: new Date().toISOString(),
            policy: {
                maxConcurrentPerUser: this.runtimeConfig.sessionMaxConcurrentPerUser,
                maxConcurrentPerTeam: this.runtimeConfig.sessionMaxConcurrentPerTeam,
                maxRuntimeSeconds: this.runtimeConfig.sessionMaxRuntimeSeconds,
                maxInactivitySeconds: this.runtimeConfig.sessionMaxInactivitySeconds,
                usageWindowHours: windowHours,
            },
            teams,
            statusCounts,
            telemetry: {
                queuedLaunchesTotal: sessionBrokerTelemetry.queuedLaunchesTotal,
                launchDenialsTotal: sessionBrokerTelemetry.launchDenialsTotal,
                launchDenialsByPolicy: { ...sessionBrokerTelemetry.launchDenialsByPolicy },
                reaperRunsTotal: sessionBrokerTelemetry.reaperRunsTotal,
                reaperFailuresTotal: sessionBrokerTelemetry.reaperFailuresTotal,
                reapedSessionsTotal: sessionBrokerTelemetry.reapedSessionsTotal,
                purgeOperationsTotal: sessionBrokerTelemetry.purgeOperationsTotal,
                reaperLastRunAt: sessionBrokerTelemetry.reaperLastRunAt,
                reaperLastSuccessAt: sessionBrokerTelemetry.reaperLastSuccessAt,
            },
            redis: redisMetrics,
        };
    }
    async getActiveSessionsForReap() {
        const result = await this.db.query('SELECT * FROM sessions WHERE status = ANY($1::text[]) ORDER BY last_activity ASC', [ACTIVE_SESSION_STATES]);
        return result.rows.map((row) => this.dbRowToSession(row));
    }
    async reapExpiredSessions() {
        sessionBrokerTelemetry.reaperRunsTotal += 1;
        sessionBrokerTelemetry.reaperLastRunAt = new Date();
        const now = Date.now();
        const sessions = await this.getActiveSessionsForReap();
        let reaped = 0;
        for (const session of sessions) {
            const runtimeAgeSeconds = Math.floor((now - session.createdAt.getTime()) / 1000);
            const inactivityAgeSeconds = Math.floor((now - session.lastActivity.getTime()) / 1000);
            const expiredByRuntime = runtimeAgeSeconds >= this.runtimeConfig.sessionMaxRuntimeSeconds;
            const expiredByInactivity = inactivityAgeSeconds >= this.runtimeConfig.sessionMaxInactivitySeconds;
            const expiredByTtl = session.expiresAt.getTime() <= now;
            if (!expiredByRuntime && !expiredByInactivity && !expiredByTtl) {
                continue;
            }
            logger.warn('Reaping stale session', {
                sessionId: session.sessionId,
                userId: session.userId,
                teamId: session.teamId,
                expiredByRuntime,
                expiredByInactivity,
                expiredByTtl,
                runtimeAgeSeconds,
                inactivityAgeSeconds,
            });
            try {
                await this.terminateSession(session.sessionId, `ttl-reap-${session.sessionId}`);
                reaped += 1;
            }
            catch (error) {
                sessionBrokerTelemetry.reaperFailuresTotal += 1;
                logger.error('Failed to reap stale session', { sessionId: session.sessionId, error: String(error) });
            }
        }
        sessionBrokerTelemetry.reapedSessionsTotal += reaped;
        sessionBrokerTelemetry.reaperLastSuccessAt = new Date();
        return reaped;
    }
    async sweepResidualSessionStorage() {
        let cleaned = 0;
        try {
            const entries = await fs.readdir(this.runtimeConfig.sessionStorageRoot, { withFileTypes: true });
            for (const entry of entries) {
                if (!entry.isDirectory()) {
                    continue;
                }
                if (entry.name === 'quarantine') {
                    continue;
                }
                const sessionId = entry.name;
                const session = await this.getSession(sessionId);
                const deletionManifest = this.deletionManifests.get(sessionId);
                if (session && this.isActiveStatus(session.status)) {
                    continue;
                }
                if (deletionManifest && deletionManifest.status !== 'completed') {
                    continue;
                }
                const sessionRoot = path.join(this.runtimeConfig.sessionStorageRoot, sessionId);
                try {
                    await fs.rm(sessionRoot, { recursive: true, force: true });
                    cleaned += 1;
                    if (session) {
                        const manifest = await this.buildDeletionManifest(session, 'system', 'residual_storage_gc', `storage-gc-${sessionId}`, 'quarantined', []);
                        this.deletionManifests.set(sessionId, manifest);
                    }
                    logger.info('Residual session storage cleaned', {
                        sessionId,
                        sessionStatus: session?.status || 'unknown',
                        sessionRoot,
                    });
                }
                catch (error) {
                    logger.warn('Residual session storage cleanup failed', {
                        sessionId,
                        sessionRoot,
                        error: String(error),
                    });
                }
            }
        }
        catch (error) {
            logger.warn('Residual storage sweep unavailable', {
                storageRoot: this.runtimeConfig.sessionStorageRoot,
                error: String(error),
            });
        }
        return cleaned;
    }
    /**
     * Terminate session and clean up container
     */
    async terminateSession(sessionId, correlationId) {
        const session = this.sessions.get(sessionId);
        if (!session) {
            const dbSession = await this.getSession(sessionId);
            if (!dbSession) {
                logger.warn('Session not found for termination', { sessionId });
                return;
            }
            this.sessions.set(sessionId, dbSession);
            return this.terminateSession(sessionId, `db-reload-${sessionId}`);
        }
        if (TERMINAL_SESSION_STATES.includes(session.status)) {
            logger.info('Session already terminated', { sessionId, status: session.status });
            return;
        }
        logger.info('Terminating session', { sessionId, containerId: session.containerId });
        try {
            this.transitionSession(session, 'teardown_pending', 'termination requested', correlationId);
            const cleanupErrors = [];
            const removedResources = [];
            if (session.containerId) {
                const container = this.docker.getContainer(session.containerId);
                // Stop container
                try {
                    await container.stop({ t: 10 });
                }
                catch (error) {
                    cleanupErrors.push(`container stop failed: ${String(error)}`);
                    logger.warn('Container stop failed during teardown', { sessionId, error: String(error) });
                }
                // Remove container
                try {
                    await container.remove({ v: true });
                }
                catch (error) {
                    cleanupErrors.push(`container remove failed: ${String(error)}`);
                    logger.warn('Container remove failed during teardown', { sessionId, error: String(error) });
                }
            }
            try {
                const quarantinedPaths = await this.quarantineSessionStorage(sessionId);
                removedResources.push(...quarantinedPaths);
                if (quarantinedPaths.length === 0) {
                    cleanupErrors.push('session storage already absent');
                }
            }
            catch (error) {
                cleanupErrors.push(`storage quarantine failed: ${String(error)}`);
                logger.warn('Session storage quarantine failed during teardown', { sessionId, error: String(error) });
            }
            const manifest = await this.buildDeletionManifest(session, 'system', 'quarantine_pending_purge', ensureCorrelationId(correlationId), cleanupErrors.length > 0 ? 'partial' : 'quarantined', cleanupErrors, removedResources);
            this.deletionManifests.set(sessionId, manifest);
            session.expiresAt = new Date(manifest.quarantineUntil);
            await this.persistSession(session);
            await this.processQueuedSessions(correlationId);
            this.recordSessionEvent(createSessionAuditEvent({
                sessionId,
                actor: 'system',
                action: 'terminate',
                fromStatus: 'teardown_pending',
                toStatus: 'teardown_pending',
                reason: cleanupErrors.length > 0 ? 'quarantined with cleanup warnings' : 'quarantined pending purge',
                correlationId: ensureCorrelationId(correlationId),
                details: {
                    cleanupErrors,
                    manifestChecksum: manifest.checksum,
                    quarantineUntil: manifest.quarantineUntil,
                    quarantineRoot: manifest.quarantineRoot,
                },
            }));
            logger.info('Session quarantined successfully', { sessionId, quarantineUntil: manifest.quarantineUntil });
        }
        catch (error) {
            logger.error('Failed to terminate session', { sessionId, error: String(error) });
            throw error;
        }
    }
    async holdSessionDeletion(sessionId, actor, reason, correlationId) {
        const manifest = this.deletionManifests.get(sessionId);
        const session = this.sessions.get(sessionId) ?? await this.getSession(sessionId);
        if (!session || !manifest) {
            throw new SessionPolicyError(404, 'session_deletion_not_found', 'Session deletion record not found');
        }
        const updated = holdDeletionRecord(manifest, {
            actor,
            reason,
            correlationId: ensureCorrelationId(correlationId),
        });
        this.deletionManifests.set(sessionId, updated);
        await this.persistSession(session);
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId,
            actor,
            action: 'cleanup',
            fromStatus: 'teardown_pending',
            toStatus: 'teardown_pending',
            reason: `deletion hold applied: ${reason}`,
            correlationId: ensureCorrelationId(correlationId),
            details: {
                hold: true,
                holdReason: reason,
                holdAppliedBy: actor,
                manifestChecksum: updated.checksum,
            },
        }));
        return updated;
    }
    async releaseSessionDeletionHold(sessionId, actor, reason, correlationId) {
        const manifest = this.deletionManifests.get(sessionId);
        const session = this.sessions.get(sessionId) ?? await this.getSession(sessionId);
        if (!session || !manifest) {
            throw new SessionPolicyError(404, 'session_deletion_not_found', 'Session deletion record not found');
        }
        const updated = releaseDeletionHold(manifest, {
            actor,
            reason,
            correlationId: ensureCorrelationId(correlationId),
        });
        this.deletionManifests.set(sessionId, updated);
        await this.persistSession(session);
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId,
            actor,
            action: 'cleanup',
            fromStatus: 'teardown_pending',
            toStatus: 'teardown_pending',
            reason: `deletion hold released: ${reason}`,
            correlationId: ensureCorrelationId(correlationId),
            details: {
                hold: false,
                holdReason: reason,
                holdAppliedBy: actor,
                manifestChecksum: updated.checksum,
            },
        }));
        return updated;
    }
    async purgeQuarantinedSession(sessionId, actor, reason, correlationId, force = false) {
        const session = this.sessions.get(sessionId) ?? await this.getSession(sessionId);
        if (!session) {
            throw new SessionPolicyError(404, 'session_not_found', 'Session not found');
        }
        const manifest = this.deletionManifests.get(sessionId);
        if (!manifest) {
            throw new SessionPolicyError(404, 'session_deletion_not_found', 'Session deletion record not found');
        }
        if (isDeletionHoldActive(manifest) && !force) {
            throw new SessionPolicyError(409, 'deletion_hold_active', 'Session deletion is on hold');
        }
        if (!force && !isDeletionQuarantineExpired(manifest)) {
            throw new SessionPolicyError(409, 'quarantine_not_expired', 'Session deletion quarantine has not expired');
        }
        const removedResources = await this.purgeQuarantineStorage(sessionId);
        const finalized = finalizeDeletionRecord(manifest, {
            actor,
            reason: force ? `${reason} (forced purge)` : reason,
            correlationId: ensureCorrelationId(correlationId),
        }, removedResources, []);
        this.deletionManifests.set(sessionId, finalized);
        this.transitionSession(session, 'destroyed', 'quarantine purged', ensureCorrelationId(correlationId));
        await this.persistSession(session);
        this.sessions.delete(sessionId);
        // Also delete from Redis if enabled
        if (this.useRedis && this.redisStore) {
            this.redisStore.deleteSession(sessionId, session.userId).catch((error) => {
                logger.warn('Failed to delete session from Redis', { sessionId, error: String(error) });
            });
        }
        sessionBrokerTelemetry.purgeOperationsTotal += 1;
        this.recordSessionEvent(createSessionAuditEvent({
            sessionId,
            actor,
            action: 'cleanup',
            fromStatus: 'teardown_pending',
            toStatus: 'destroyed',
            reason: force ? `forced purge: ${reason}` : `purged after quarantine: ${reason}`,
            correlationId: ensureCorrelationId(correlationId),
            details: {
                force,
                manifestChecksum: finalized.checksum,
                residualResourceZero: finalized.residualResourceZero,
                quarantineRoot: finalized.quarantineRoot,
            },
        }));
        return finalized;
    }
    async reconcileQuarantinedSessions(correlationId) {
        let purged = 0;
        const quarantinedRows = await this.db.query('SELECT * FROM sessions WHERE status = $1', ['teardown_pending']);
        for (const row of quarantinedRows.rows) {
            const session = this.dbRowToSession(row);
            if (!this.deletionManifests.has(session.sessionId)) {
                const { storageRoot, workspacePath, profilePath } = this.getSessionStoragePaths(session.sessionId);
                const quarantineRoot = this.getSessionQuarantinePath(session.sessionId);
                const resourcesRemoved = [];
                const resourcesRemaining = [];
                for (const resourcePath of [workspacePath, profilePath, storageRoot, quarantineRoot]) {
                    if (await this.sessionPathExists(resourcePath)) {
                        resourcesRemaining.push(resourcePath);
                    }
                    else {
                        resourcesRemoved.push(resourcePath);
                    }
                }
                if (session.containerId) {
                    resourcesRemoved.push(`container:${session.containerId}`);
                }
                const rehydratedManifest = buildSessionDeletionRecord({
                    sessionId: session.sessionId,
                    actor: 'system',
                    reason: 'rehydrated quarantine manifest',
                    correlationId: correlationId ?? `quarantine-reconcile-${session.sessionId}`,
                    quarantineHours: this.runtimeConfig.sessionDeletionQuarantineHours,
                    quarantineUntil: session.expiresAt.toISOString(),
                    resourcesBefore: {
                        containerId: session.containerId,
                        containerName: session.containerName,
                        storageRoot,
                        quarantineRoot,
                        workspacePath,
                        profilePath,
                        sessionRecordPresent: true,
                    },
                    resourcesRemoved,
                    resourcesRemaining,
                });
                this.deletionManifests.set(session.sessionId, {
                    ...rehydratedManifest,
                    status: 'quarantined',
                    residualResourceZero: false,
                });
            }
        }
        for (const [sessionId, manifest] of this.deletionManifests.entries()) {
            if (!isDeletionQuarantineExpired(manifest) || isDeletionHoldActive(manifest)) {
                continue;
            }
            try {
                await this.purgeQuarantinedSession(sessionId, 'system', 'quarantine expired', correlationId ?? `quarantine-reconcile-${sessionId}`);
                purged += 1;
            }
            catch (error) {
                logger.warn('Quarantined session purge failed', {
                    sessionId,
                    error: String(error),
                });
            }
        }
        return purged;
    }
    /**
     * List all active sessions for a user
     */
    async listUserSessions(userId) {
        try {
            const result = await this.db.query('SELECT * FROM sessions WHERE user_id = $1 AND status = ANY($2::text[]) ORDER BY created_at DESC', [userId, ACTIVE_SESSION_STATES]);
            return result.rows.map((row) => this.dbRowToSession(row));
        }
        catch (error) {
            logger.error('Failed to list user sessions', { userId, error: String(error) });
            return [];
        }
    }
    /**
     * Update session activity timestamp
     */
    async updateActivity(sessionId) {
        const session = this.sessions.get(sessionId);
        if (session) {
            session.lastActivity = new Date();
            await this.persistSession(session);
        }
    }
    async runShadowReplay(sessionId, actor, traces, maxLatencyRegressionMs, correlationId) {
        const session = await this.getSession(sessionId);
        if (!session) {
            throw new SessionPolicyError(404, 'session_not_found', 'Session not found');
        }
        if (!['ready', 'testing'].includes(session.status)) {
            throw new SessionPolicyError(409, 'shadow_replay_lifecycle_invalid', `Shadow replay is only allowed for ready/testing sessions (current status: ${session.status})`);
        }
        try {
            assertReadSafeShadowReplayTraces(traces);
        }
        catch (error) {
            throw new SessionPolicyError(422, 'shadow_replay_invalid_trace', String(error.message));
        }
        const observations = [];
        for (const trace of traces) {
            const method = normalizeShadowReplayMethod(trace.method);
            const normalizedPath = normalizeShadowReplayPath(trace.path);
            const targetUrl = `${getSessionContainerUrl(session.containerPort)}${normalizedPath}`;
            const startedAt = process.hrtime.bigint();
            const response = await axios({
                method,
                url: targetUrl,
                headers: trace.headers,
                timeout: 15000,
                maxRedirects: 0,
                validateStatus: () => true,
            });
            const durationNs = process.hrtime.bigint() - startedAt;
            const latencyMs = Number(durationNs / 1000000n);
            observations.push({
                status: response.status,
                latencyMs,
            });
        }
        const report = buildShadowReplayReport(sessionId, traces, observations, maxLatencyRegressionMs);
        const reportPath = this.getSessionShadowReplayReportPath(sessionId);
        await fs.mkdir(path.dirname(reportPath), { recursive: true });
        await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
        const artifact = {
            report,
            reportPath,
        };
        this.shadowReplayArtifacts.set(sessionId, artifact);
        const resolvedCorrelationId = ensureCorrelationId(correlationId);
        this.recordSessionEvent({
            sessionId,
            actor: actor.userId,
            action: 'shadow_replay',
            fromStatus: session.status,
            toStatus: session.status,
            reason: 'shadow replay completed',
            correlationId: resolvedCorrelationId,
            details: {
                totalRequests: report.totalRequests,
                statusMismatchCount: report.statusMismatchCount,
                latencyRegressionCount: report.latencyRegressionCount,
                maxLatencyRegressionMs: report.maxLatencyRegressionMs,
                reportPath,
            },
        });
        await this.persistSession(session);
        return artifact;
    }
    // ────────────────────────────────────────────────────────────────────────
    // Private Helper Methods
    // ────────────────────────────────────────────────────────────────────────
    buildContainerConfig(session) {
        const { workspacePath, profilePath } = this.getSessionStoragePaths(session.sessionId);
        return {
            image: session.baseImageId,
            hostname: session.containerName,
            cpuLimit: session.quotas.cpuLimit,
            memoryLimit: session.quotas.memoryLimit,
            portMapping: { host: session.containerPort, container: 8080 },
            volumes: {
                '/home/coder/workspace': {
                    bind: workspacePath,
                    ro: false
                },
                '/home/coder/.local/share/code-server': {
                    bind: profilePath,
                    ro: false
                }
            },
            env: {
                PASSWORD: session.codeServerPassword || crypto.randomBytes(32).toString('hex'),
                SUDO_PASSWORD: session.codeServerPassword || crypto.randomBytes(32).toString('hex'),
                SESSION_DATA_PROFILE: session.dataProfile,
                SESSION_DATA_PROFILE_VALIDATED: String(session.dataProfileValidated),
                SESSION_PROVENANCE_MANIFEST_VERSION: session.provenance.manifestVersion,
                SESSION_PROVENANCE_IMAGE_DIGEST: session.provenance.imageDigest,
                SESSION_PROVENANCE_ATTESTATION_REF: session.provenance.attestationRef,
                SESSION_PROVENANCE_SIGNER_IDENTITY: session.provenance.signerIdentity,
                SESSION_PROVENANCE_VERIFIED_AT: session.provenance.verifiedAt,
                SESSION_PROVENANCE_VERIFICATION_RESULT: session.provenance.verificationResult,
                SESSION_PROVENANCE_POLICY_VERSION: session.provenance.policyVersion,
                SESSION_PROVENANCE_FRESHNESS_HOURS: String(session.provenance.freshnessHours),
                SESSION_PROVENANCE_SESSION_FINGERPRINT: session.provenance.sessionFingerprint,
                SERVICE_URL: 'https://open-vsx.org/vscode/gallery',
                ITEM_URL: 'https://open-vsx.org/vscode/item',
                CS_DISABLE_FILE_DOWNLOADS: 'false',
                NODE_OPTIONS: '--max-old-space-size=2048',
                SESSION_ID: session.sessionId,
                USER_ID: session.userId,
                USERNAME: session.username,
                USER_EMAIL: session.email,
                CONTAINER_NAME: session.containerName,
                EXPIRES_AT: session.expiresAt.toISOString()
            }
        };
    }
    parseMemory(memStr) {
        const match = memStr.match(/^(\d+)([kmg])$/i);
        if (!match)
            return 4 * 1024 * 1024 * 1024; // Default 4g
        const [, value, unit] = match;
        const bytes = parseInt(value, 10);
        switch (unit.toLowerCase()) {
            case 'k': return bytes * 1024;
            case 'm': return bytes * 1024 * 1024;
            case 'g': return bytes * 1024 * 1024 * 1024;
            default: return bytes;
        }
    }
    async persistSession(session) {
        try {
            const deletionManifest = this.deletionManifests.get(session.sessionId);
            await this.db.query(`INSERT INTO sessions (session_id, user_id, username, email, data_profile, data_profile_validated, provenance_manifest, provenance_verified, provenance_image_digest, provenance_attestation_ref, provenance_signer_identity, provenance_verified_at, provenance_policy_version, deletion_manifest, queue_lane, queue_reason, queue_position, queue_enqueued_at, queue_estimated_wait_seconds, container_id, container_name,
         container_port, created_at, expires_at, status, last_activity, quotas, base_image_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12, $13, $14::jsonb, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28)
         ON CONFLICT (session_id) DO UPDATE SET
         status = $25, last_activity = $26, container_id = $20, data_profile = $5, data_profile_validated = $6, provenance_manifest = $7::jsonb, provenance_verified = $8, provenance_image_digest = $9, provenance_attestation_ref = $10, provenance_signer_identity = $11, provenance_verified_at = $12, provenance_policy_version = $13, deletion_manifest = $14::jsonb, queue_lane = $15, queue_reason = $16, queue_position = $17, queue_enqueued_at = $18, queue_estimated_wait_seconds = $19, quotas = $27, base_image_id = $28, expires_at = $24`, [
                session.sessionId,
                session.userId,
                session.username,
                session.email,
                session.dataProfile,
                session.dataProfileValidated,
                JSON.stringify(session.provenance),
                true,
                session.provenance.imageDigest,
                session.provenance.attestationRef,
                session.provenance.signerIdentity,
                session.provenance.verifiedAt,
                session.provenance.policyVersion,
                deletionManifest ? JSON.stringify(deletionManifest) : null,
                session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                session.queueReason ?? null,
                session.queuePosition ?? null,
                session.queueEnqueuedAt ?? null,
                session.queueEstimatedWaitSeconds ?? null,
                session.containerId || null,
                session.containerName,
                session.containerPort,
                session.createdAt,
                session.expiresAt,
                session.status,
                session.lastActivity,
                JSON.stringify(session.quotas),
                session.baseImageId
            ]);
            // Also persist to Redis if enabled (for cross-host failover)
            if (this.useRedis && this.redisStore) {
                this.redisStore.storeSession(session.sessionId, session).catch((error) => {
                    logger.warn('Failed to store session in Redis', { sessionId: session.sessionId, error: String(error) });
                });
            }
        }
        catch (error) {
            logger.error('Failed to persist session', { sessionId: session.sessionId, error: String(error) });
        }
    }
    dbRowToSession(row) {
        const status = this.normalizeStatus(row.status);
        const deletionManifest = row.deletion_manifest ? normalizeSessionDeletionRecord(row.deletion_manifest) : null;
        if (deletionManifest) {
            this.deletionManifests.set(row.session_id, deletionManifest);
        }
        return {
            sessionId: row.session_id,
            userId: row.user_id,
            teamId: this.resolveTeamId(row.email),
            username: row.username,
            email: row.email,
            dataProfile: normalizeSessionDataProfile(row.data_profile) ?? DEFAULT_SESSION_DATA_PROFILE,
            dataProfileValidated: row.data_profile_validated ?? true,
            provenance: normalizeSessionProvenanceManifest(row.provenance_manifest) ?? { ...this.runtimeConfig.provenanceManifest },
            queueLane: normalizeSessionQueueLane(row.queue_lane),
            queueReason: row.queue_reason ?? undefined,
            queuePosition: row.queue_position ?? undefined,
            queueEnqueuedAt: row.queue_enqueued_at ? new Date(row.queue_enqueued_at) : undefined,
            queueEstimatedWaitSeconds: row.queue_estimated_wait_seconds ?? undefined,
            containerName: row.container_name,
            containerId: row.container_id,
            containerPort: row.container_port,
            baseImageId: row.base_image_id,
            createdAt: new Date(row.created_at),
            expiresAt: new Date(row.expires_at),
            quotas: row.quotas || {},
            status,
            lastActivity: new Date(row.last_activity),
            auditTrail: [],
        };
    }
    /**
     * Stop accepting new session requests
     * Used during graceful shutdown to prevent new sessions from starting
     */
    stopAcceptingNewSessions() {
        logger.info('Session manager stopped accepting new sessions');
        // This will be enforced at the route handler level by checking this flag
        this.acceptingNewSessions = false;
    }
    /**
     * Notify all active sessions that the server is shutting down
     * Sessions can save their state before forced termination
     */
    async notifyShutdown() {
        const activeSessions = Array.from(this.sessions.values()).filter((s) => !TERMINAL_SESSION_STATES.includes(s.status));
        logger.info('Notifying sessions of shutdown', { count: activeSessions.length });
        // In a real implementation, this would send WebSocket notifications
        // For now, we just log the notification
        const notifyPromises = activeSessions.map(async (session) => {
            try {
                logger.debug('Shutdown notification sent to session', { sessionId: session.sessionId });
                // In production, send via WebSocket/HTTP to session container
                // await notifySessionViaWebSocket(session.sessionId, 'shutdown_warning');
            }
            catch (error) {
                logger.warn('Failed to notify session', {
                    sessionId: session.sessionId,
                    error: error instanceof Error ? error.message : String(error),
                });
            }
        });
        await Promise.allSettled(notifyPromises);
    }
    /**
     * Wait for active sessions to save their state
     * Respects the maxWaitMs timeout - does not wait indefinitely
     */
    async waitForSessionsToSave(maxWaitMs) {
        const deadline = Date.now() + maxWaitMs;
        const checkInterval = 500; // ms
        while (Date.now() < deadline) {
            const activeSessions = Array.from(this.sessions.values()).filter((s) => !TERMINAL_SESSION_STATES.includes(s.status));
            if (activeSessions.length === 0) {
                logger.info('All sessions have terminated');
                return;
            }
            const remainingMs = deadline - Date.now();
            logger.debug('Waiting for sessions to save', {
                activeCount: activeSessions.length,
                remainingMs,
            });
            await new Promise((resolve) => setTimeout(resolve, Math.min(checkInterval, remainingMs)));
        }
        const remainingSessions = Array.from(this.sessions.values()).filter((s) => !TERMINAL_SESSION_STATES.includes(s.status));
        if (remainingSessions.length > 0) {
            logger.warn('Timeout waiting for sessions to save', {
                activeCount: remainingSessions.length,
                timeoutMs: maxWaitMs,
            });
        }
    }
    /**
     * Get list of active sessions for monitoring/shutdown purposes
     */
    listActiveSessions() {
        return Array.from(this.sessions.values())
            .filter((s) => !TERMINAL_SESSION_STATES.includes(s.status))
            .map((s) => ({
            id: s.sessionId,
            containerId: s.containerId,
        }));
    }
    /**
     * Stop all managed containers during shutdown
     * Gives containers time to stop gracefully before force-killing
     */
    async stopAllManagedContainers(options = {}) {
        const timeout = options.timeout ?? 10;
        const containers = await this.listManagedContainers();
        logger.info('Stopping managed containers', { count: containers.length, timeout });
        const stopPromises = containers.map(async (container) => {
            try {
                await container.stop({ t: timeout });
                logger.debug('Stopped container', { containerId: container.id.substring(0, 12) });
            }
            catch (error) {
                // If stop fails, try to kill
                try {
                    await container.kill();
                    logger.warn('Killed container after stop failed', {
                        containerId: container.id.substring(0, 12),
                    });
                }
                catch (killError) {
                    logger.error('Failed to stop/kill container', {
                        containerId: container.id.substring(0, 12),
                        error: killError instanceof Error ? killError.message : String(killError),
                    });
                }
            }
        });
        await Promise.allSettled(stopPromises);
        logger.info('Container shutdown complete');
    }
    /**
     * Get list of containers managed by this session broker
     */
    async listManagedContainers() {
        try {
            const containers = await this.docker.listContainers({
                filters: {
                    label: ['managed-by=session-broker'],
                },
            });
            return containers.map((c) => this.docker.getContainer(c.Id));
        }
        catch (error) {
            logger.error('Failed to list managed containers', {
                error: error instanceof Error ? error.message : String(error),
            });
            return [];
        }
    }
    /**
     * Close database connections and cleanup resources
     * Called at the end of graceful shutdown
     */
    async close() {
        logger.info('Closing session manager resources');
        try {
            if (this.redisStore) {
                await this.redisStore.close();
                logger.info('Redis session store closed');
            }
        }
        catch (error) {
            logger.warn('Error closing Redis store', {
                error: error instanceof Error ? error.message : String(error),
            });
        }
        try {
            await this.db.end();
            logger.info('Database connections closed');
        }
        catch (error) {
            logger.warn('Error closing database connections', {
                error: error instanceof Error ? error.message : String(error),
            });
        }
    }
    /**
     * Check if session manager is accepting new sessions
     * Returns false during graceful shutdown
     */
    isAcceptingNewSessions() {
        return this.acceptingNewSessions;
    }
}
// ────────────────────────────────────────────────────────────────────────────
// Express Application Setup
// ────────────────────────────────────────────────────────────────────────────
const app = express();
const manager = new SessionManager(runtimeConfig);
app.use(express.json());
app.use(cookieParser());
const authCallbackSchema = Joi.object({
    email: Joi.string().email().required(),
    username: Joi.string().trim().min(1).max(128).required()
});
const sessionIdSchema = Joi.string().uuid().required();
const userIdSchema = Joi.string().trim().min(1).max(128).required();
const shadowReplayTraceSchema = Joi.object({
    method: Joi.string().trim().uppercase().valid('GET', 'HEAD', 'OPTIONS').required(),
    path: Joi.string().trim().min(1).required(),
    baselineStatus: Joi.number().integer().min(100).max(599).required(),
    baselineLatencyMs: Joi.number().min(0).required(),
    headers: Joi.object().pattern(Joi.string(), Joi.string()).optional(),
}).required();
const shadowReplayRequestSchema = Joi.object({
    traces: Joi.array().items(shadowReplayTraceSchema).min(1).max(500).required(),
    maxLatencyRegressionMs: Joi.number().min(0).max(10000).default(50),
}).required();
const getAuthUser = (req) => {
    // Check for X-Auth-Request headers set by oauth2-proxy
    const email = req.headers['x-auth-request-email'];
    const user = req.headers['x-auth-request-user'];
    const preferredUsername = req.headers['x-auth-request-preferred-username'] || user;
    const rawGroups = req.headers['x-auth-request-groups'];
    if (!email || !user) {
        return null;
    }
    return buildSessionBrokerPrincipal({
        userId: user || email.split('@')[0],
        username: preferredUsername || email.split('@')[0],
        email,
        groups: Array.isArray(rawGroups) ? rawGroups.join(',') : rawGroups,
    }, {
        adminGroups: runtimeConfig.adminGroups,
        operatorGroups: runtimeConfig.operatorGroups,
        approverGroups: runtimeConfig.approverGroups,
        auditorGroups: runtimeConfig.auditorGroups,
        breakGlassGroups: runtimeConfig.breakGlassGroups,
    });
};
const requireAuthUser = (req, res) => {
    const authUser = req.authUser;
    if (!authUser) {
        res.status(401).json({ error: 'Authentication required' });
        return null;
    }
    return authUser;
};
const denyLifecycleAction = (res, decision) => {
    sessionBrokerTelemetry.launchDenialsTotal += 1;
    sessionBrokerTelemetry.launchDenialsByPolicy[decision.policyCode] = (sessionBrokerTelemetry.launchDenialsByPolicy[decision.policyCode] ?? 0) + 1;
    res.status(decision.statusCode).json({
        error: decision.reason,
        policyCode: decision.policyCode,
    });
};
// Middleware: Check auth and extract user info
app.use((req, res, next) => {
    // Skip auth for health checks, oauth2 routes, metrics, and public endpoints
    if (req.path === '/health' || req.path === '/metrics' || req.path.startsWith('/oauth2') || req.path === '/ping') {
        return next();
    }
    const authUser = getAuthUser(req);
    if (authUser) {
        req.authUser = authUser;
    }
    const rawCorrelationId = req.headers['x-correlation-id'];
    const correlationId = Array.isArray(rawCorrelationId) ? rawCorrelationId[0] : rawCorrelationId;
    req.correlationId = ensureCorrelationId(correlationId);
    next();
});
app.use((req, res, next) => {
    if (req.path === '/health' || req.path === '/metrics' || req.path.startsWith('/oauth2') || req.path === '/ping') {
        return next();
    }
    const authUser = req.authUser;
    if (!authUser) {
        return res.status(401).json({ error: 'Authentication required' });
    }
    return next();
});
// ────────────────────────────────────────────────────────────────────────────
// Request Logging Middleware
// ────────────────────────────────────────────────────────────────────────────
app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
        const duration = Date.now() - start;
        const logEntry = {
            method: req.method,
            path: req.path,
            statusCode: res.statusCode,
            duration: `${duration}ms`,
            ip: req.ip
        };
        const sessionId = req.cookies._code_server_session_id;
        const authUser = req.authUser;
        if (authUser) {
            logEntry.userId = authUser.userId;
            logEntry.username = authUser.username;
            logEntry.email = authUser.email;
        }
        if (sessionId) {
            logEntry.sessionId = sessionId;
        }
        const correlationId = req.correlationId;
        if (correlationId) {
            logEntry.correlationId = correlationId;
        }
        // Log different levels based on status code
        if (res.statusCode >= 500) {
            logger.error('Activity: Server Error', logEntry);
        }
        else if (res.statusCode >= 400) {
            logger.warn('Activity: Client Error', logEntry);
        }
        else {
            logger.info('Activity', logEntry);
        }
    });
    next();
});
// ────────────────────────────────────────────────────────────────────────────
// Routes
// ────────────────────────────────────────────────────────────────────────────
/**
 * Public session route for scoped ephemeral links.
 */
app.use('/s/:sessionId', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const viewDecision = authorizeSessionView(authUser, session.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        logger.info('Routing public session URL', {
            sessionId: session.sessionId,
            user: authUser.username,
            path: req.originalUrl,
        });
        return proxySessionContainerRequest(req, res, session, stripSessionPublicRoutePrefix(req.originalUrl, session.sessionId));
    }
    catch (error) {
        if (error instanceof SessionPolicyError) {
            return res.status(error.statusCode).json({ error: error.message, policyCode: error.policyCode });
        }
        res.status(500).json({ error: 'Failed to route public session request' });
    }
});
/**
 * POST /sessions
 * Create new isolated session for authenticated user
 */
app.post('/sessions', async (req, res) => {
    const authUser = requireAuthUser(req, res);
    if (!authUser) {
        return;
    }
    const rateLimitKey = authUser.email || req.ip || 'anonymous';
    const rateLimitDecision = enforceSessionCreateRateLimit(rateLimitKey);
    if (!rateLimitDecision.allowed) {
        if (typeof rateLimitDecision.retryAfterSeconds === 'number') {
            res.setHeader('Retry-After', String(rateLimitDecision.retryAfterSeconds));
        }
        return res.status(429).json({
            error: 'Too many session creation attempts, retry after 60 seconds',
            retryAfterSeconds: rateLimitDecision.retryAfterSeconds ?? 60,
        });
    }
    const provenanceSchema = Joi.object({
        manifestVersion: Joi.string().valid('v1').required(),
        imageDigest: Joi.string().pattern(/^sha256:[a-f0-9]{64}$/i).required(),
        attestationRef: Joi.string().trim().min(1).required(),
        signerIdentity: Joi.string().trim().min(1).required(),
        verifiedAt: Joi.string().isoDate().required(),
        verificationResult: Joi.string().valid('verified', 'rejected').default('verified'),
        policyVersion: Joi.string().trim().min(1).required(),
        freshnessHours: Joi.number().integer().min(1).required(),
        sessionFingerprint: Joi.string().pattern(/^sha256:[a-f0-9]{64}$/i).optional(),
    }).required();
    const schema = Joi.object({
        userId: Joi.string().uuid().required(),
        username: Joi.string().alphanum().min(3).max(32).required(),
        email: Joi.string().email().required(),
        ttlSeconds: Joi.number().min(3600).max(86400).default(28800),
        teamId: Joi.string().trim().min(1).max(128).optional(),
        dataProfile: Joi.string().valid(...APPROVED_SESSION_DATA_PROFILES).required(),
        priorityLane: Joi.string().valid('fast', 'standard').default('standard'),
        provenance: provenanceSchema,
    });
    const { error, value } = schema.validate(req.body);
    if (error) {
        return res.status(400).json({ error: error.message });
    }
    try {
        const targetUserId = value.userId === authUser.userId ? authUser.userId : value.userId;
        const launchDecision = authorizeSessionLaunch(authUser, targetUserId);
        if (!launchDecision.allowed) {
            return denyLifecycleAction(res, launchDecision);
        }
        const effectiveUsername = targetUserId === authUser.userId ? authUser.username : value.username;
        const effectiveEmail = targetUserId === authUser.userId ? authUser.email : value.email;
        const correlationId = req.correlationId;
        const session = await manager.launchSession(targetUserId, effectiveUsername, effectiveEmail, value.ttlSeconds, value.teamId, correlationId, value.dataProfile, value.priorityLane, value.provenance);
        res.status(session.status === 'queued' ? 202 : 201).json({
            sessionId: session.sessionId,
            containerPort: session.containerPort,
            containerName: session.containerName,
            url: getSessionContainerUrl(session.containerPort),
            publicUrl: getSessionPublicUrl(session.sessionId),
            expiresAt: session.expiresAt,
            status: session.status,
            teamId: session.teamId,
            dataProfile: session.dataProfile,
            dataProfileValidated: session.dataProfileValidated,
            provenance: session.provenance,
            evidenceBundleUrl: `/sessions/${session.sessionId}/evidence`,
            queue: session.status === 'queued' ? {
                lane: session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                position: session.queuePosition ?? null,
                estimatedWaitSeconds: session.queueEstimatedWaitSeconds ?? null,
                reason: session.queueReason ?? null,
                enqueuedAt: session.queueEnqueuedAt ?? null,
            } : null,
        });
    }
    catch (error) {
        if (error instanceof SessionPolicyError) {
            logger.warn('Session launch denied by policy', {
                policyCode: error.policyCode,
                message: error.message,
                userId: value.userId,
                email: value.email,
            });
            return res.status(error.statusCode).json({
                error: error.message,
                policyCode: error.policyCode,
            });
        }
        logger.error('Session creation API error', { error: String(error) });
        res.status(500).json({ error: 'Failed to create session' });
    }
});
/**
 * GET /usage/summary
 * Provide usage telemetry for dashboards and FinOps review.
 */
app.get('/usage/summary', async (req, res) => {
    try {
        const requestedWindow = typeof req.query.windowHours === 'string' ? Number.parseInt(req.query.windowHours, 10) : runtimeConfig.sessionUsageWindowHours;
        if (!Number.isInteger(requestedWindow) || requestedWindow < 1) {
            return res.status(400).json({ error: 'Invalid windowHours' });
        }
        const teams = await manager.getUsageSummary(requestedWindow);
        res.json({
            windowHours: requestedWindow,
            policy: {
                maxConcurrentPerUser: runtimeConfig.sessionMaxConcurrentPerUser,
                maxConcurrentPerTeam: runtimeConfig.sessionMaxConcurrentPerTeam,
                maxRuntimeSeconds: runtimeConfig.sessionMaxRuntimeSeconds,
                maxInactivitySeconds: runtimeConfig.sessionMaxInactivitySeconds,
            },
            teams,
        });
    }
    catch (error) {
        logger.error('Usage summary error', { error: String(error) });
        res.status(500).json({ error: 'Failed to retrieve usage summary' });
    }
});
/**
 * GET /sessions
 * List all active sessions (for debugging, metrics, and operator access)
 * Scope: Authenticated operators and system components
 */
app.get('/sessions', async (req, res) => {
    try {
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        // Authorization check: only operators and admins can view all sessions
        const viewDecision = authorizeSessionView(authUser, undefined);
        if (!viewDecision.allowed) {
            return res.status(viewDecision.statusCode).json({
                error: viewDecision.reason,
                code: viewDecision.policyCode,
            });
        }
        // Get all sessions (from Redis if enabled, otherwise from memory)
        let sessions = [];
        if (manager['useRedis'] && manager['redisStore']) {
            try {
                const redisSessions = await manager['redisStore'].getAllSessions();
                sessions = redisSessions;
            }
            catch (error) {
                logger.error('Failed to retrieve sessions from Redis', { error });
                // Fallback to in-memory sessions
                sessions = Array.from(manager['sessions'].values());
            }
        }
        else {
            sessions = Array.from(manager['sessions'].values());
        }
        // Filter and sanitize for response
        const response = {
            sessionCount: sessions.length,
            sessions: sessions.map((s) => ({
                id: s.sessionId,
                userId: s.userId,
                containerId: s.containerId,
                status: s.status,
                createdAt: s.createdAt,
                lastActivity: s.lastActivity,
            })),
        };
        res.json(response);
    }
    catch (error) {
        logger.error('Failed to list sessions', { error: String(error) });
        res.status(500).json({ error: 'Failed to list sessions' });
    }
});
/**
 * GET /sessions/:sessionId/redis
 * Query raw Redis entry for a specific session (operator only, troubleshooting)
 */
app.get('/sessions/:sessionId/redis', async (req, res) => {
    try {
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        // Authorization check: only operators can view raw Redis entries
        if (!authUser.roles.includes('operator') && !authUser.roles.includes('admin')) {
            return res.status(403).json({
                error: 'Only operators and admins can view Redis entries',
            });
        }
        const { sessionId } = req.params;
        const sessionIdValidation = sessionIdSchema.validate(sessionId);
        if (sessionIdValidation.error) {
            return res.status(400).json({ error: sessionIdValidation.error.message });
        }
        if (!manager['useRedis'] || !manager['redisStore']) {
            return res.status(503).json({
                error: 'Redis session store is not enabled',
            });
        }
        const sessionData = await manager['redisStore'].getSession(sessionId);
        if (!sessionData) {
            return res.status(404).json({ error: 'Session not found in Redis' });
        }
        res.json({
            sessionId,
            data: sessionData,
            source: 'redis-sentinel',
        });
    }
    catch (error) {
        logger.error('Failed to query Redis session', { error: String(error) });
        res.status(500).json({ error: 'Failed to query session' });
    }
});
app.post('/oauth2/callback', async (req, res) => {
    try {
        // Extract and validate user info from oauth2-proxy headers.
        const authUser = getAuthUser(req);
        if (!authUser) {
            logger.warn('oauth2 callback missing auth identity');
            return res.status(400).json({ error: 'Missing authentication headers' });
        }
        req.authUser = authUser;
        const { error, value } = authCallbackSchema.validate({
            email: req.headers['x-auth-request-email'],
            username: req.headers['x-auth-request-user']
        });
        if (error) {
            logger.warn('oauth2 callback validation failed', { error: error.message });
            return res.status(400).json({ error: 'Missing authentication headers' });
        }
        // Create session for the newly authenticated user
        const userId = authUser.userId;
        const correlationId = req.correlationId;
        let session = await manager.getUserActiveSession(userId);
        if (!session) {
            logger.info('Creating session on oauth2 callback', { userId, email: authUser.email });
            session = await manager.createSession(userId, authUser.username, authUser.email, 86400, undefined, correlationId, DEFAULT_SESSION_DATA_PROFILE);
        }
        else {
            logger.info('Session already exists for user', { userId, sessionId: session.sessionId });
        }
        res.json({
            sessionId: session.sessionId,
            containerPort: session.containerPort,
            url: evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired).allowed
                ? getSessionContainerUrl(session.containerPort)
                : null,
            publicUrl: getSessionPublicUrl(session.sessionId),
            status: session.status,
            dataProfile: session.dataProfile,
            dataProfileValidated: session.dataProfileValidated,
            provenance: session.provenance,
            evidenceBundleUrl: `/sessions/${session.sessionId}/evidence`,
            queue: session.status === 'queued' ? {
                lane: session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                position: session.queuePosition ?? null,
                estimatedWaitSeconds: session.queueEstimatedWaitSeconds ?? null,
                reason: session.queueReason ?? null,
                enqueuedAt: session.queueEnqueuedAt ?? null,
            } : null,
            approval: {
                required: runtimeConfig.sessionApprovalRequired,
                state: isSessionApprovalPending(session.status, runtimeConfig.sessionApprovalRequired) ? 'pending' : 'approved',
            },
        });
    }
    catch (error) {
        logger.error('OAuth2 callback error', { error: String(error) });
        res.status(500).json({ error: 'Failed to create session' });
    }
});
/**
 * POST /oauth2/logout (Phase 2 Integration)
 * Clean up user's session on logout
 * Called by oauth2-proxy sign_out flow
 */
app.post('/oauth2/logout', async (req, res) => {
    try {
        const authUser = req.authUser;
        const rawSessionId = req.body?.sessionId ?? req.headers['x-session-id'];
        const sessionId = Array.isArray(rawSessionId) ? rawSessionId[0] : rawSessionId;
        const { error } = sessionIdSchema.validate(sessionId);
        if (error) {
            return res.status(400).json({ error: 'Missing session ID' });
        }
        if (sessionId) {
            const session = await manager.getSession(sessionId);
            if (!session) {
                return res.status(404).json({ error: 'Session not found' });
            }
            if (!authUser) {
                return res.status(401).json({ error: 'Authentication required' });
            }
            const terminationDecision = authorizeSessionTermination(authUser, session.userId);
            if (!terminationDecision.allowed) {
                return denyLifecycleAction(res, terminationDecision);
            }
            logger.info('Terminating session on logout', { sessionId });
            await manager.terminateSession(sessionId, req.correlationId);
        }
        res.status(204).send();
    }
    catch (error) {
        logger.error('Logout error', { error: String(error) });
        res.status(500).json({ error: 'Failed to logout' });
    }
});
/**
 * GET /sessions/:sessionId
 * Retrieve session details and status
 */
app.get('/sessions/:sessionId', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const viewDecision = authorizeSessionView(authUser, session.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        res.json({
            sessionId: session.sessionId,
            status: session.status,
            containerPort: session.containerPort,
            containerName: session.containerName,
            url: evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired).allowed
                ? getSessionContainerUrl(session.containerPort)
                : null,
            publicUrl: getSessionPublicUrl(session.sessionId),
            expiresAt: session.expiresAt,
            lastActivity: session.lastActivity,
            quotas: session.quotas,
            dataProfile: session.dataProfile,
            dataProfileValidated: session.dataProfileValidated,
            provenance: session.provenance,
            evidenceBundleUrl: `/sessions/${session.sessionId}/evidence`,
            queue: session.status === 'queued' ? {
                lane: session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                position: session.queuePosition ?? null,
                estimatedWaitSeconds: session.queueEstimatedWaitSeconds ?? null,
                reason: session.queueReason ?? null,
                enqueuedAt: session.queueEnqueuedAt ?? null,
            } : null,
            lifecycle: {
                state: session.status,
                active: ACTIVE_SESSION_STATES.includes(session.status),
                terminal: TERMINAL_SESSION_STATES.includes(session.status),
                provenance: session.provenance,
                approval: isSessionApprovalPending(session.status, runtimeConfig.sessionApprovalRequired) ? 'pending' : 'approved',
            }
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve session' });
    }
});
/**
 * GET /sessions/:sessionId/status
 * Retrieve session lifecycle status
 */
app.get('/sessions/:sessionId/status', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const viewDecision = authorizeSessionView(authUser, session.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        const deletionManifest = manager.getDeletionManifest(req.params.sessionId);
        res.json({
            sessionId: session.sessionId,
            state: session.status,
            active: ACTIVE_SESSION_STATES.includes(session.status),
            terminal: TERMINAL_SESSION_STATES.includes(session.status),
            containerName: session.containerName,
            publicUrl: getSessionPublicUrl(session.sessionId),
            expiresAt: session.expiresAt,
            lastActivity: session.lastActivity,
            dataProfile: session.dataProfile,
            dataProfileValidated: session.dataProfileValidated,
            provenance: session.provenance,
            queue: session.status === 'queued' ? {
                lane: session.queueLane ?? DEFAULT_SESSION_QUEUE_LANE,
                position: session.queuePosition ?? null,
                estimatedWaitSeconds: session.queueEstimatedWaitSeconds ?? null,
                reason: session.queueReason ?? null,
                enqueuedAt: session.queueEnqueuedAt ?? null,
            } : null,
            deletion: deletionManifest ?? null,
            nextActions: session.status === 'destroyed'
                ? []
                : deletionManifest
                    ? deletionManifest.hold
                        ? ['release-hold', 'purge-force']
                        : ['hold', 'purge']
                    : ['cancel', 'destroy'],
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve session status' });
    }
});
/**
 * POST /sessions/:sessionId/cancel
 * Request deterministic teardown for a session
 */
app.post('/sessions/:sessionId/cancel', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const terminationDecision = authorizeSessionTermination(authUser, session.userId);
        if (!terminationDecision.allowed) {
            return denyLifecycleAction(res, terminationDecision);
        }
        await manager.terminateSession(req.params.sessionId, req.correlationId);
        res.status(202).json({
            sessionId: req.params.sessionId,
            state: 'teardown_pending',
            message: 'Session quarantine requested',
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to cancel session' });
    }
});
/**
 * POST /sessions/:sessionId/destroy
 * Force session destruction (alias for cancel/destroy contract)
 */
app.post('/sessions/:sessionId/destroy', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const terminationDecision = authorizeSessionTermination(authUser, session.userId);
        if (!terminationDecision.allowed) {
            return denyLifecycleAction(res, terminationDecision);
        }
        await manager.terminateSession(req.params.sessionId, req.correlationId);
        res.status(202).json({
            sessionId: req.params.sessionId,
            state: 'teardown_pending',
            message: 'Session quarantine requested',
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to destroy session' });
    }
});
/**
 * POST /sessions/:sessionId/deletion/release
 * Release a held session deletion for normal purge reconciliation.
 */
app.post('/sessions/:sessionId/deletion/release', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const terminationDecision = authorizeSessionTermination(authUser, session.userId);
        if (!terminationDecision.allowed) {
            return denyLifecycleAction(res, terminationDecision);
        }
        const reason = typeof req.body?.reason === 'string' && req.body.reason.trim() !== ''
            ? req.body.reason.trim()
            : 'manual release';
        const manifest = await manager.releaseSessionDeletionHold(req.params.sessionId, authUser.userId, reason, req.correlationId);
        res.status(200).json({
            sessionId: req.params.sessionId,
            deletion: manifest,
        });
    }
    catch (error) {
        if (error instanceof SessionPolicyError) {
            return res.status(error.statusCode).json({ error: error.message, policyCode: error.policyCode });
        }
        res.status(500).json({ error: 'Failed to release session deletion hold' });
    }
});
/**
 * POST /sessions/:sessionId/deletion/purge
 * Force or reconcile hard purge for a quarantined session.
 */
app.post('/sessions/:sessionId/deletion/purge', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const breakGlassDecision = authorizeBreakGlassTermination(authUser, session.userId);
        const terminationDecision = breakGlassDecision.allowed ? breakGlassDecision : authorizeSessionTermination(authUser, session.userId);
        if (!terminationDecision.allowed) {
            return denyLifecycleAction(res, terminationDecision);
        }
        const reason = typeof req.body?.reason === 'string' && req.body.reason.trim() !== ''
            ? req.body.reason.trim()
            : 'manual purge';
        const force = req.body?.force === true || breakGlassDecision.allowed;
        const manifest = await manager.purgeQuarantinedSession(req.params.sessionId, authUser.userId, reason, req.correlationId, force);
        res.status(200).json({
            sessionId: req.params.sessionId,
            deletion: manifest,
        });
    }
    catch (error) {
        if (error instanceof SessionPolicyError) {
            return res.status(error.statusCode).json({ error: error.message, policyCode: error.policyCode });
        }
        res.status(500).json({ error: 'Failed to purge session deletion' });
    }
});
/**
 * GET /users/:userId/sessions
 * List all active sessions for a user
 */
app.get('/users/:userId/sessions', async (req, res) => {
    try {
        const { error } = userIdSchema.validate(req.params.userId);
        if (error) {
            return res.status(400).json({ error: 'Invalid user ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const viewDecision = authorizeSessionView(authUser, req.params.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        const sessions = await manager.listUserSessions(req.params.userId);
        res.json({
            userId: req.params.userId,
            sessions: sessions.map(s => ({
                sessionId: s.sessionId,
                status: s.status,
                containerPort: s.containerPort,
                publicUrl: getSessionPublicUrl(s.sessionId),
                createdAt: s.createdAt,
                expiresAt: s.expiresAt,
                lastActivity: s.lastActivity,
                dataProfile: s.dataProfile,
                dataProfileValidated: s.dataProfileValidated,
                provenance: s.provenance,
            }))
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to list sessions' });
    }
});
/**
 * PUT /sessions/:sessionId/activity
 * Update session activity timestamp (keep-alive)
 */
app.put('/sessions/:sessionId/activity', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const viewDecision = authorizeSessionView(authUser, session.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        await manager.updateActivity(req.params.sessionId);
        res.status(204).send();
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to update activity' });
    }
});
/**
 * GET /sessions/:sessionId/events
 * Retrieve the audit trail for a session lifecycle.
 */
app.get('/sessions/:sessionId/events', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const evidenceDecision = authorizeSessionView(authUser, session.userId);
        if (!evidenceDecision.allowed) {
            return denyLifecycleAction(res, evidenceDecision);
        }
        res.json({
            sessionId: session.sessionId,
            events: manager.getSessionEvents(req.params.sessionId),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve session audit trail' });
    }
});
/**
 * POST /sessions/:sessionId/shadow-replay
 * Execute read-safe shadow replay against an active ephemeral session.
 */
app.post('/sessions/:sessionId/shadow-replay', async (req, res) => {
    try {
        const { error: sessionIdError } = sessionIdSchema.validate(req.params.sessionId);
        if (sessionIdError) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const viewDecision = authorizeSessionView(authUser, session.userId);
        if (!viewDecision.allowed) {
            return denyLifecycleAction(res, viewDecision);
        }
        const { error: payloadError, value } = shadowReplayRequestSchema.validate(req.body);
        if (payloadError) {
            return res.status(400).json({ error: payloadError.message });
        }
        const artifact = await manager.runShadowReplay(req.params.sessionId, authUser, value.traces, value.maxLatencyRegressionMs, req.correlationId);
        return res.status(200).json({
            sessionId: req.params.sessionId,
            report: artifact.report,
            evidenceBundle: {
                reportPath: artifact.reportPath,
            },
        });
    }
    catch (error) {
        if (error instanceof SessionPolicyError) {
            return res.status(error.statusCode).json({ error: error.message, policyCode: error.policyCode });
        }
        return res.status(500).json({ error: 'Failed to execute shadow replay' });
    }
});
/**
 * GET /sessions/:sessionId/evidence
 * Retrieve evidence bundle for a session lifecycle.
 */
app.get('/sessions/:sessionId/evidence', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const evidenceDecision = authorizeSessionView(authUser, session.userId);
        if (!evidenceDecision.allowed) {
            return denyLifecycleAction(res, evidenceDecision);
        }
        const bundle = await manager.getSessionEvidenceBundle(req.params.sessionId);
        return res.status(200).json(bundle);
    }
    catch (error) {
        return res.status(500).json({ error: 'Failed to retrieve session evidence bundle' });
    }
});
/**
 * GET /sessions/:sessionId/deletion
 * Retrieve the deletion manifest for a session.
 */
app.get('/sessions/:sessionId/deletion', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const manifest = manager.getDeletionManifest(req.params.sessionId);
        if (!manifest) {
            return res.status(404).json({ error: 'Deletion manifest not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const evidenceDecision = authorizeSessionView(authUser, session.userId);
        if (!evidenceDecision.allowed) {
            return denyLifecycleAction(res, evidenceDecision);
        }
        res.json(manifest);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve deletion manifest' });
    }
});
/**
 * GET /sessions/:sessionId/approval
 * Retrieve approval and audit status for a session.
 */
app.get('/sessions/:sessionId/approval', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const evidenceDecision = authorizeSessionView(authUser, session.userId);
        if (!evidenceDecision.allowed) {
            return denyLifecycleAction(res, evidenceDecision);
        }
        const integrity = manager.verifyAuditIntegrity(req.params.sessionId);
        const publication = evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired);
        res.json({
            sessionId: session.sessionId,
            approvalRequired: runtimeConfig.sessionApprovalRequired,
            approvalPending: isSessionApprovalPending(session.status, runtimeConfig.sessionApprovalRequired),
            publicationAllowed: publication.allowed,
            publicationPolicyCode: publication.policyCode,
            policyMatrix: buildSessionBrokerPolicyMatrix(),
            audit: integrity,
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve approval state' });
    }
});
/**
 * POST /sessions/:sessionId/approve
 * Approve publication of a pending session.
 */
app.post('/sessions/:sessionId/approve', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const approvalDecision = authorizeSessionApproval(authUser);
        if (!approvalDecision.allowed) {
            return denyLifecycleAction(res, approvalDecision);
        }
        const session = await manager.approveSession(req.params.sessionId, authUser, req.correlationId);
        res.status(200).json({
            sessionId: session.sessionId,
            status: session.status,
            approval: 'approved',
            publication: evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to approve session' });
    }
});
/**
 * POST /sessions/:sessionId/break-glass
 * Emergency termination path with explicit reason code.
 */
app.post('/sessions/:sessionId/break-glass', async (req, res) => {
    try {
        const { error } = sessionIdSchema.validate(req.params.sessionId);
        if (error) {
            return res.status(400).json({ error: 'Invalid session ID' });
        }
        const session = await manager.getSession(req.params.sessionId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        const authUser = requireAuthUser(req, res);
        if (!authUser) {
            return;
        }
        const reasonCode = typeof req.body?.reasonCode === 'string' ? req.body.reasonCode : '';
        const breakGlassDecision = authorizeBreakGlassTermination(authUser, session.userId, reasonCode);
        if (!breakGlassDecision.allowed) {
            return denyLifecycleAction(res, breakGlassDecision);
        }
        await manager.terminateSession(req.params.sessionId, req.correlationId);
        res.status(202).json({
            sessionId: req.params.sessionId,
            state: 'destroyed',
            policyCode: 'break_glass_allowed',
            reasonCode,
            message: 'Break-glass termination requested',
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to execute break-glass termination' });
    }
});
/**
 * GET /metrics
 * Prometheus exposition for session FinOps and lifecycle telemetry.
 */
app.get('/metrics', async (req, res) => {
    try {
        const snapshot = await manager.getMetricsSnapshot();
        res.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
        res.send(renderSessionBrokerPrometheusMetrics(snapshot));
    }
    catch (error) {
        logger.error('Metrics export error', { error: String(error) });
        res.status(500).type('text/plain').send('# session broker metrics unavailable\n');
    }
});
/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});
/**
 * Default route handler (Phase 2 Integration)
 * Routes authenticated requests to user's isolated session container
 * Redirects unauthenticated requests to oauth2-proxy for authentication
 */
app.all('*', async (req, res) => {
    try {
        const authUser = req.authUser;
        // Redirect unauthenticated requests to oauth2-proxy
        if (!authUser) {
            logger.warn('Unauthenticated request', { path: req.path, ip: req.ip });
            const forwardedProto = (req.get('x-forwarded-proto') || req.protocol).split(',')[0].trim();
            const returnUrl = `${forwardedProto}://${req.get('host')}${req.originalUrl}`;
            // Preserve the original destination so oauth2-proxy can return users to the requested page.
            return res.redirect(`/oauth2/start?rd=${encodeURIComponent(returnUrl)}`);
        }
        logger.info('Authenticated request', {
            path: req.path,
            user: authUser.username,
            email: authUser.email
        });
        // Get or create session for authenticated user
        let session = await manager.getUserActiveSession(authUser.userId);
        if (!session) {
            // Create new session
            logger.info('Creating new session', { userId: authUser.userId });
            session = await manager.createSession(authUser.userId, authUser.username, authUser.email, 86400, // 24 hour TTL
            undefined, req.correlationId, DEFAULT_SESSION_DATA_PROFILE);
        }
        const publicationDecision = evaluateSessionPublication(session.status, runtimeConfig.sessionApprovalRequired);
        if (!publicationDecision.allowed) {
            return res.status(publicationDecision.statusCode).json({
                error: publicationDecision.reason,
                policyCode: publicationDecision.policyCode,
                sessionId: session.sessionId,
                approvalRequired: runtimeConfig.sessionApprovalRequired,
                approvalPending: isSessionApprovalPending(session.status, runtimeConfig.sessionApprovalRequired),
            });
        }
        // Update last activity
        await manager.updateActivity(session.sessionId);
        // Set session cookie
        res.cookie('_code_server_session_id', session.sessionId, {
            httpOnly: true,
            secure: true,
            sameSite: 'lax',
            maxAge: 86400 * 1000
        });
        logger.info('Proxying to session container', {
            sessionId: session.sessionId,
            containerPort: session.containerPort,
            path: req.path
        });
        // Proxy request to the user's session container
        const targetUrl = `${getSessionContainerUrl(session.containerPort)}${req.path}${req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : ''}`;
        // Use axios for simpler proxying
        try {
            const response = await axios({
                method: req.method,
                url: targetUrl,
                headers: req.headers,
                data: req.method !== 'GET' && req.method !== 'HEAD' ? req.body : undefined,
                validateStatus: () => true // Accept all status codes
            });
            res.status(response.status);
            Object.entries(response.headers).forEach(([key, value]) => {
                if (!['content-encoding', 'transfer-encoding'].includes(key.toLowerCase())) {
                    res.setHeader(key, value);
                }
            });
            res.send(response.data);
        }
        catch (proxyError) {
            logger.error('Proxy error', {
                sessionId: session.sessionId,
                targetUrl,
                error: String(proxyError)
            });
            res.status(503).json({ error: 'Session unavailable' });
        }
    }
    catch (error) {
        logger.error('Request handler error', { error: String(error), path: req.path });
        res.status(500).json({ error: 'Internal server error' });
    }
});
// ────────────────────────────────────────────────────────────────────────────
// Server Startup
// ────────────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
const server = app.listen(PORT, async () => {
    logger.info(`Session broker listening on port ${PORT}`);
    // Set up graceful shutdown handlers
    setupGracefulShutdown({
        sessionManager: {
            stopAcceptingNewSessions: () => manager.stopAcceptingNewSessions(),
            notifyShutdown: () => manager.notifyShutdown(),
            waitForSessionsToSave: (ms) => manager.waitForSessionsToSave(ms),
            close: () => manager.close(),
            listActiveSessions: () => manager.listActiveSessions(),
        },
        containerManager: {
            stopAllContainers: (opts) => manager.stopAllManagedContainers(opts),
        },
        logger,
        server: {
            close: () => new Promise((resolve, reject) => {
                server.close((err) => {
                    if (err)
                        reject(err);
                    else
                        resolve();
                });
            }),
        },
    });
    // Initialize Redis session store if enabled
    try {
        await manager.initializeRedisStore();
    }
    catch (error) {
        logger.error('Redis store initialization failed', { error: String(error) });
        if (process.env.SESSION_REDIS_REQUIRED === 'true') {
            process.exit(1);
        }
    }
    void manager.reapExpiredSessions().catch((error) => {
        logger.error('Initial stale-session sweep failed', { error: String(error) });
    });
    void manager.sweepResidualSessionStorage().catch((error) => {
        logger.error('Initial residual-storage sweep failed', { error: String(error) });
    });
    void manager.reconcileQuarantinedSessions().catch((error) => {
        logger.error('Initial quarantined-session reconciliation failed', { error: String(error) });
    });
    const sweepIntervalMs = Math.max(30000, Math.floor(runtimeConfig.sessionMaxInactivitySeconds * 250));
    const sweepTimer = setInterval(() => {
        void manager.reapExpiredSessions().catch((error) => {
            logger.error('Scheduled stale-session sweep failed', { error: String(error) });
        });
        void manager.sweepResidualSessionStorage().catch((error) => {
            logger.error('Scheduled residual-storage sweep failed', { error: String(error) });
        });
        void manager.reconcileQuarantinedSessions().catch((error) => {
            logger.error('Scheduled quarantined-session reconciliation failed', { error: String(error) });
        });
    }, sweepIntervalMs);
    sweepTimer.unref?.();
});
//# sourceMappingURL=index.js.map