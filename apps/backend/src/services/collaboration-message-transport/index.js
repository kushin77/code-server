// @file        apps/backend/src/services/collaboration-message-transport/index.ts
// @module      collaboration/message-transport
// @description Matrix SDK transport adapter for encrypted collaboration messages
// @owner       backend
import { EventEmitter } from 'node:events';
import { CollaborationMessageEncryptionService, } from '../collaboration-message-encryption/index.js';
const DEFAULT_EVENT_TYPE = 'com.code-server.collaboration.message';
const DEFAULT_ENCRYPTION_ROTATION_PERIOD_MS = 7 * 24 * 60 * 60 * 1000;
const DEFAULT_ENCRYPTION_ROTATION_PERIOD_MSGS = 100;
function asTrimmedString(value) {
    if (typeof value !== 'string') {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function requireText(value, field) {
    const text = asTrimmedString(value);
    if (!text) {
        throw new Error(`Missing required field: ${field}`);
    }
    return text;
}
function resolveRoomId(response) {
    const roomId = asTrimmedString(response.roomId) ?? asTrimmedString(response.room_id);
    if (!roomId) {
        throw new Error('Matrix room bootstrap did not return a room id');
    }
    return roomId;
}
function buildEncryptionState(options) {
    return [
        {
            type: 'm.room.encryption',
            state_key: '',
            content: {
                algorithm: 'm.megolm.v1.aes-sha2',
                rotation_period_ms: options.encryptionRotationPeriodMs ?? DEFAULT_ENCRYPTION_ROTATION_PERIOD_MS,
                rotation_period_msgs: options.encryptionRotationPeriodMsgs ?? DEFAULT_ENCRYPTION_ROTATION_PERIOD_MSGS,
            },
        },
        {
            type: 'm.room.history_visibility',
            state_key: '',
            content: {
                history_visibility: options.historyVisibility ?? 'shared',
            },
        },
    ];
}
export class MatrixCollaborationTransportService extends EventEmitter {
    client;
    encryption;
    constructor(client, encryption = new CollaborationMessageEncryptionService()) {
        super();
        this.client = client;
        this.encryption = encryption;
    }
    static restoreFromVaultBackup(client, backupBody, backupKeyMaterial) {
        const encryption = CollaborationMessageEncryptionService.restoreFromVaultBackup(backupBody, backupKeyMaterial);
        return new MatrixCollaborationTransportService(client, encryption);
    }
    bootstrapEncryptedRoom(options) {
        const roomName = requireText(options.roomName, 'roomName');
        return this.client.createRoom({
            name: roomName,
            topic: asTrimmedString(options.topic),
            invite: options.invite?.map((invitee) => requireText(invitee, 'invite')),
            preset: options.isDirect ? 'private_chat' : 'private_chat',
            is_direct: Boolean(options.isDirect),
            room_alias_name: asTrimmedString(options.roomAliasName),
            initial_state: buildEncryptionState(options),
        }).then((response) => {
            const roomId = resolveRoomId(response);
            const encryptionState = buildEncryptionState(options)[0]?.content ?? {};
            this.emit('matrix-room-bootstrapped', { roomId, roomName, encryptionState });
            return {
                roomId,
                encryptionState,
            };
        });
    }
    sendEncryptedMessage(roomId, message, metadata = {}, eventType = DEFAULT_EVENT_TYPE) {
        const normalizedRoomId = requireText(roomId, 'roomId');
        const encrypted = this.encryption.encryptMessage(requireText(message, 'message'), metadata);
        const payload = {
            roomId: normalizedRoomId,
            eventType,
            content: {
                encrypted: true,
                ciphertext: encrypted.body,
                keyId: encrypted.keyId,
                algorithm: encrypted.algorithm,
                metadata: { ...metadata },
            },
        };
        return this.client.sendEvent(normalizedRoomId, eventType, payload.content).then(() => {
            this.emit('matrix-encrypted-message-sent', {
                roomId: normalizedRoomId,
                keyId: encrypted.keyId,
                eventType,
            });
            return payload;
        });
    }
    decryptEncryptedMessage(ciphertextBody) {
        return this.encryption.decryptMessage(ciphertextBody);
    }
    exportVaultBackup(backupKeyMaterial, metadata = {}) {
        return this.encryption.exportVaultBackup(backupKeyMaterial, metadata);
    }
}