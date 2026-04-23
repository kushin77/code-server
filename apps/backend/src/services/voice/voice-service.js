/**
 * @file        apps/backend/src/services/voice/voice-service.ts
 * @module      services/voice
 * @description Voice channel service with WebRTC + LiveKit SFU backend for real-time communication
 *
 */
import { EventEmitter } from 'events';
/**
 * Voice Channel Service
 * Manages real-time voice communication using WebRTC + LiveKit SFU backend
 */
export class VoiceChannelService extends EventEmitter {
    static getInstance(config) {
        if (!this.instance) {
            this.instance = new VoiceChannelService(config);
        }
        return this.instance;
    }
    static reset() {
        this.instance = undefined;
    }
    constructor(config) {
        super();
        this.channels = new Map();
        this.participants = new Map();
        this.recordings = new Map();
        this.auditLogs = new Map();
        this.connectionStats = new Map();
        this.audioLevels = new Map();
        this.config = {
            maxChannelsPerWorkspace: 50,
            maxParticipantsPerChannel: 100,
            maxAuditLogSize: 1000,
            enableNoiseSuppression: true,
            enableEchoCancellation: true,
            enableAutoGainControl: true,
            enableTranscription: false,
            enableRecording: true,
            defaultAudioCodec: 'opus',
            defaultVoiceQuality: 'high',
            livekitUrl: 'wss://livekit.example.com',
            livekitApiKey: 'API_KEY_DEFAULT',
            livekitApiSecret: 'API_SECRET_DEFAULT',
            speakingThreshold: 30,
            silenceTimeout: 5000,
            reconnectTimeout: 5000,
            maxReconnectAttempts: 5,
            ...config,
        };
        this.emit('initialized', { timestamp: Date.now() });
    }
    createVoiceChannel(request, ipAddress, userAgent) {
        try {
            const channelId = `voice-${request.workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const livekitRoomName = `room-${channelId}`;
            const livekitToken = this.generateLiveKitToken(livekitRoomName, request.userId);
            const channel = {
                id: channelId,
                workspaceId: request.workspaceId,
                name: request.channelName,
                description: request.description || '',
                createdAt: Date.now(),
                createdBy: request.userId,
                participants: [],
                livekitRoomName,
                connectionState: 'new',
                activeParticipantCount: 0,
                maxParticipants: request.maxParticipants || 100,
                isRecording: false,
                recordingStartedAt: null,
                transcriptionEnabled: this.config.enableTranscription,
            };
            this.channels.set(channelId, channel);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'create-voice-channel',
                channelId,
                status: 'success',
                details: { channelName: request.channelName },
            });
            this.emit('voice-channel-created', {
                channel,
                timestamp: Date.now(),
            });
            return {
                success: true,
                channelId,
                livekitToken,
                livekitUrl: this.config.livekitUrl,
                channel,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'create-voice-channel',
                channelId: '',
                status: 'failure',
                details: { error: errorMsg },
            });
            return { success: false, channelId: '', livekitToken: '', livekitUrl: '', channel: null, error: errorMsg };
        }
    }
    joinVoiceChannel(request, ipAddress, userAgent) {
        try {
            const channel = this.channels.get(request.channelId);
            if (!channel) {
                throw new Error(`Channel ${request.channelId} not found`);
            }
            if (channel.activeParticipantCount >= channel.maxParticipants) {
                throw new Error('Channel is full');
            }
            const participantId = `part-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const livekitToken = this.generateLiveKitToken(channel.livekitRoomName, request.userId);
            const participant = {
                id: participantId,
                userId: request.userId,
                userEmail: request.userEmail,
                displayName: request.displayName,
                status: 'connecting',
                isMuted: false,
                isDeafened: false,
                joinedAt: Date.now(),
                audioLevel: 0,
                lastAudioLevelUpdate: Date.now(),
                latency: 0,
                bitrate: 0,
                packetLoss: 0,
            };
            this.participants.set(participantId, participant);
            channel.participants.push(participant);
            channel.activeParticipantCount += 1;
            channel.connectionState = 'connecting';
            // Simulate connection establishment (5-50ms)
            setTimeout(() => {
                participant.status = 'connected';
                channel.connectionState = 'connected';
                this.emit('participant-joined', {
                    channelId: request.channelId,
                    participant,
                    timestamp: Date.now(),
                });
            }, Math.random() * 45 + 5);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'join-voice-channel',
                channelId: request.channelId,
                participantId,
                status: 'success',
                details: { displayName: request.displayName },
            });
            return {
                success: true,
                participantId,
                livekitToken,
                livekitUrl: this.config.livekitUrl,
                livekitRoomName: channel.livekitRoomName,
                channel,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'join-voice-channel',
                channelId: request.channelId,
                status: 'failure',
                details: { error: errorMsg },
            });
            return { success: false, participantId: '', livekitToken: '', livekitUrl: '', livekitRoomName: '', channel: null, error: errorMsg };
        }
    }
    leaveVoiceChannel(request, ipAddress, userAgent) {
        try {
            const channel = this.channels.get(request.channelId);
            if (!channel) {
                throw new Error(`Channel ${request.channelId} not found`);
            }
            const participant = this.participants.get(request.participantId);
            if (!participant) {
                throw new Error(`Participant ${request.participantId} not found`);
            }
            participant.status = 'disconnected';
            channel.participants = channel.participants.filter((p) => p.id !== request.participantId);
            channel.activeParticipantCount = Math.max(0, channel.activeParticipantCount - 1);
            this.participants.delete(request.participantId);
            if (channel.activeParticipantCount === 0) {
                channel.connectionState = 'disconnected';
            }
            this.emit('participant-left', {
                channelId: request.channelId,
                participantId: request.participantId,
                timestamp: Date.now(),
            });
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'leave-voice-channel',
                channelId: request.channelId,
                participantId: request.participantId,
                status: 'success',
            });
            return { success: true };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'leave-voice-channel',
                channelId: request.channelId,
                participantId: request.participantId,
                status: 'failure',
                details: { error: errorMsg },
            });
            return { success: false, error: errorMsg };
        }
    }
    muteParticipant(request, ipAddress, userAgent) {
        try {
            const participant = this.participants.get(request.participantId);
            if (!participant) {
                throw new Error(`Participant ${request.participantId} not found`);
            }
            participant.isMuted = request.isMuted;
            const eventType = request.isMuted ? 'participant-muted' : 'participant-unmuted';
            this.emit(eventType, {
                channelId: request.channelId,
                participantId: request.participantId,
                participant,
                timestamp: Date.now(),
            });
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: eventType,
                channelId: request.channelId,
                participantId: request.participantId,
                status: 'success',
            });
            return { success: true, participant };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, participant: null, error: errorMsg };
        }
    }
    deafenParticipant(request, ipAddress, userAgent) {
        try {
            const participant = this.participants.get(request.participantId);
            if (!participant) {
                throw new Error(`Participant ${request.participantId} not found`);
            }
            participant.isDeafened = request.isDeafened;
            const eventType = request.isDeafened ? 'participant-deafened' : 'participant-undeafened';
            this.emit(eventType, {
                channelId: request.channelId,
                participantId: request.participantId,
                participant,
                timestamp: Date.now(),
            });
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: eventType,
                channelId: request.channelId,
                participantId: request.participantId,
                status: 'success',
            });
            return { success: true, participant };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, participant: null, error: errorMsg };
        }
    }
    getVoiceChannel(request) {
        try {
            const channel = this.channels.get(request.channelId) || null;
            return { success: true, channel };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, channel: null, error: errorMsg };
        }
    }
    getParticipants(request) {
        try {
            const channel = this.channels.get(request.channelId);
            if (!channel) {
                throw new Error(`Channel ${request.channelId} not found`);
            }
            return { success: true, participants: channel.participants, count: channel.participants.length };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, participants: [], count: 0, error: errorMsg };
        }
    }
    updateAudioLevel(request) {
        const participant = this.participants.get(request.participantId);
        if (participant) {
            participant.audioLevel = request.level;
            participant.lastAudioLevelUpdate = Date.now();
            const audioLevel = {
                participantId: request.participantId,
                participantName: participant.displayName,
                level: request.level,
                timestamp: Date.now(),
                isSpeaking: request.level > this.config.speakingThreshold,
            };
            this.audioLevels.set(request.participantId, audioLevel);
            this.emit('audio-level-changed', {
                audioLevel,
                timestamp: Date.now(),
            });
        }
    }
    updateConnectionStats(request) {
        const participant = this.participants.get(request.participantId);
        if (participant) {
            participant.latency = request.roundTripTime;
            participant.packetLoss = request.packetLoss;
            participant.bitrate = request.bitrate;
            const stats = {
                connectionDuration: Date.now() - participant.joinedAt,
                roundTripTime: request.roundTripTime,
                averageLatency: request.roundTripTime,
                maxLatency: request.roundTripTime,
                minLatency: request.roundTripTime,
                packetLoss: request.packetLoss,
                bitrate: request.bitrate,
                audioCodec: this.config.defaultAudioCodec,
                noiseSuppressionEnabled: this.config.enableNoiseSuppression,
                echoCancellationEnabled: this.config.enableEchoCancellation,
                autoGainControlEnabled: this.config.enableAutoGainControl,
            };
            this.connectionStats.set(request.participantId, stats);
            this.emit('connection-stats-updated', {
                participantId: request.participantId,
                stats,
                timestamp: Date.now(),
            });
        }
    }
    toggleLocalAudio(request, ipAddress, userAgent) {
        try {
            const participant = this.participants.get(request.participantId);
            if (!participant) {
                throw new Error(`Participant ${request.participantId} not found`);
            }
            const eventType = request.enabled ? 'local-audio-enabled' : 'local-audio-disabled';
            this.emit(eventType, {
                channelId: request.channelId,
                participantId: request.participantId,
                enabled: request.enabled,
                timestamp: Date.now(),
            });
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: eventType,
                channelId: request.channelId,
                participantId: request.participantId,
                status: 'success',
            });
            return { success: true, enabled: request.enabled };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, enabled: false, error: errorMsg };
        }
    }
    startRecording(request, ipAddress, userAgent) {
        try {
            const channel = this.channels.get(request.channelId);
            if (!channel) {
                throw new Error(`Channel ${request.channelId} not found`);
            }
            if (!this.config.enableRecording) {
                throw new Error('Recording is disabled');
            }
            const recordingId = `rec-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const startedAt = Date.now();
            this.recordings.set(recordingId, {
                channelId: request.channelId,
                startedAt,
                recordingId,
            });
            channel.isRecording = true;
            channel.recordingStartedAt = startedAt;
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'start-recording',
                channelId: request.channelId,
                status: 'success',
                details: { recordingId },
            });
            return { success: true, recordingId, startedAt };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, recordingId: '', startedAt: 0, error: errorMsg };
        }
    }
    stopRecording(request, ipAddress, userAgent) {
        try {
            const channel = this.channels.get(request.channelId);
            if (!channel) {
                throw new Error(`Channel ${request.channelId} not found`);
            }
            const recording = Array.from(this.recordings.values()).find((r) => r.channelId === request.channelId);
            if (!recording) {
                throw new Error('No active recording for this channel');
            }
            const duration = Date.now() - recording.startedAt;
            const recordingId = recording.recordingId;
            this.recordings.delete(recordingId);
            channel.isRecording = false;
            channel.recordingStartedAt = null;
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'stop-recording',
                channelId: request.channelId,
                status: 'success',
                details: { recordingId, duration },
            });
            return { success: true, recordingId, duration };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, recordingId: '', duration: 0, error: errorMsg };
        }
    }
    getAuditLog(userId, limit = 100) {
        const logs = this.auditLogs.get(userId) || [];
        return logs.slice(-limit);
    }
    getStatistics() {
        const activeChannels = Array.from(this.channels.values()).filter((c) => c.connectionState === 'connected' || c.connectionState === 'connecting');
        const totalParticipants = this.participants.size;
        const currentParticipants = Array.from(this.participants.values()).filter((p) => p.status === 'connected').length;
        const activeRecordings = Array.from(this.recordings.values()).length;
        let totalLatency = 0;
        let latencyCount = 0;
        let noiseSuppressionCount = 0;
        let echoCancellationCount = 0;
        this.connectionStats.forEach((stats) => {
            totalLatency += stats.roundTripTime;
            latencyCount += 1;
            if (stats.noiseSuppressionEnabled)
                noiseSuppressionCount += 1;
            if (stats.echoCancellationEnabled)
                echoCancellationCount += 1;
        });
        return {
            totalChannels: this.channels.size,
            activeChannels: activeChannels.length,
            totalParticipants,
            currentParticipants,
            totalConnections: this.participants.size,
            failedConnections: Array.from(this.participants.values()).filter((p) => p.status === 'failed').length,
            averageLatency: latencyCount > 0 ? totalLatency / latencyCount : 0,
            totalRecordings: Array.from(this.recordings.values()).length,
            activeRecordings,
            noiseSuppressionUsage: latencyCount > 0 ? (noiseSuppressionCount / latencyCount) * 100 : 0,
            echoCancellationUsage: latencyCount > 0 ? (echoCancellationCount / latencyCount) * 100 : 0,
        };
    }
    updateConfig(config, userId, ipAddress, userAgent) {
        Object.assign(this.config, config);
        this.recordAudit({
            timestamp: Date.now(),
            userId,
            userEmail: 'system@example.com',
            ipAddress,
            userAgent,
            operation: 'update-config',
            channelId: '',
            status: 'success',
            details: { config },
        });
        this.emit('config-updated', { config: this.config, timestamp: Date.now() });
    }
    recordAudit(entry) {
        if (!this.auditLogs.has(entry.userId)) {
            this.auditLogs.set(entry.userId, []);
        }
        const logs = this.auditLogs.get(entry.userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditLogSize) {
            logs.splice(0, logs.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { entry, timestamp: Date.now() });
    }
    generateLiveKitToken(roomName, participantId) {
        // Simulated JWT token generation (in production, use LiveKit SDK)
        const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
        const payload = btoa(JSON.stringify({ room: roomName, participantId, iat: Math.floor(Date.now() / 1000) }));
        const signature = btoa(`${header}.${payload}`);
        return `${header}.${payload}.${signature}`;
    }
    shutdown() {
        this.channels.clear();
        this.participants.clear();
        this.recordings.clear();
        this.auditLogs.clear();
        this.connectionStats.clear();
        this.audioLevels.clear();
        this.emit('shutdown', { timestamp: Date.now() });
    }
}
//# sourceMappingURL=voice-service.js.map