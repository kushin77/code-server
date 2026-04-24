#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-message-transport/index.ts
// @module      collaboration/message-transport
// @description Matrix SDK transport adapter for encrypted collaboration messages
// @owner       backend

import { EventEmitter } from 'node:events'

import {
  CollaborationMessageEncryptionService,
  type CollaborationMessageCiphertext,
  type CollaborationMessageVaultBackup,
} from '../collaboration-message-encryption/index.js'

export interface MatrixRoomStateEvent {
  type: string
  state_key?: string
  content: Record<string, unknown>
}

export interface MatrixRoomCreateRequest {
  name: string
  topic?: string
  invite?: string[]
  preset?: 'private_chat' | 'public_chat' | 'trusted_private_chat'
  is_direct?: boolean
  room_alias_name?: string
  initial_state?: MatrixRoomStateEvent[]
}

export interface MatrixRoomCreateResponse {
  roomId?: string
  room_id?: string
}

export interface MatrixRoomTransportClient {
  createRoom(request: MatrixRoomCreateRequest): Promise<MatrixRoomCreateResponse>
  sendEvent(roomId: string, eventType: string, content: Record<string, unknown>): Promise<unknown>
}

export interface MatrixCollaborationBootstrapOptions {
  roomName: string
  topic?: string
  invite?: string[]
  roomAliasName?: string
  isDirect?: boolean
  encryptionRotationPeriodMs?: number
  encryptionRotationPeriodMsgs?: number
  historyVisibility?: 'shared' | 'invited' | 'joined' | 'world_readable'
}

export interface MatrixCollaborationBootstrapResult {
  roomId: string
  encryptionState: Record<string, unknown>
}

export interface MatrixEncryptedMessagePayload {
  roomId: string
  eventType: string
  content: {
    encrypted: true
    ciphertext: string
    keyId: string
    algorithm: CollaborationMessageCiphertext['algorithm']
    metadata: Record<string, unknown>
  }
}

const DEFAULT_EVENT_TYPE = 'com.code-server.collaboration.message'
const DEFAULT_ENCRYPTION_ROTATION_PERIOD_MS = 7 * 24 * 60 * 60 * 1000
const DEFAULT_ENCRYPTION_ROTATION_PERIOD_MSGS = 100

function asTrimmedString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined
  }

  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : undefined
}

function requireText(value: unknown, field: string): string {
  const text = asTrimmedString(value)
  if (!text) {
    throw new Error(`Missing required field: ${field}`)
  }

  return text
}

function resolveRoomId(response: MatrixRoomCreateResponse): string {
  const roomId = asTrimmedString(response.roomId) ?? asTrimmedString(response.room_id)
  if (!roomId) {
    throw new Error('Matrix room bootstrap did not return a room id')
  }

  return roomId
}

function buildEncryptionState(options: MatrixCollaborationBootstrapOptions): MatrixRoomStateEvent[] {
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
  ]
}

export class MatrixCollaborationTransportService extends EventEmitter {
  constructor(
    private readonly client: MatrixRoomTransportClient,
    private readonly encryption: CollaborationMessageEncryptionService = new CollaborationMessageEncryptionService()
  ) {
    super()
  }

  static restoreFromVaultBackup(
    client: MatrixRoomTransportClient,
    backupBody: string,
    backupKeyMaterial?: string
  ): MatrixCollaborationTransportService {
    const encryption = CollaborationMessageEncryptionService.restoreFromVaultBackup(backupBody, backupKeyMaterial)
    return new MatrixCollaborationTransportService(client, encryption)
  }

  bootstrapEncryptedRoom(options: MatrixCollaborationBootstrapOptions): Promise<MatrixCollaborationBootstrapResult> {
    const roomName = requireText(options.roomName, 'roomName')

    return this.client.createRoom({
      name: roomName,
      topic: asTrimmedString(options.topic),
      invite: options.invite?.map((invitee) => requireText(invitee, 'invite')),
      preset: options.isDirect ? 'private_chat' : 'private_chat',
      is_direct: Boolean(options.isDirect),
      room_alias_name: asTrimmedString(options.roomAliasName),
      initial_state: buildEncryptionState(options),
    }).then((response) => {
      const roomId = resolveRoomId(response)
      const encryptionState = buildEncryptionState(options)[0]?.content ?? {}

      this.emit('matrix-room-bootstrapped', { roomId, roomName, encryptionState })

      return {
        roomId,
        encryptionState,
      }
    })
  }

  sendEncryptedMessage(
    roomId: string,
    message: string,
    metadata: Record<string, unknown> = {},
    eventType = DEFAULT_EVENT_TYPE
  ): Promise<MatrixEncryptedMessagePayload> {
    const normalizedRoomId = requireText(roomId, 'roomId')
    const encrypted = this.encryption.encryptMessage(requireText(message, 'message'), metadata)
    const payload: MatrixEncryptedMessagePayload = {
      roomId: normalizedRoomId,
      eventType,
      content: {
        encrypted: true,
        ciphertext: encrypted.body,
        keyId: encrypted.keyId,
        algorithm: encrypted.algorithm,
        metadata: { ...metadata },
      },
    }

    return this.client.sendEvent(normalizedRoomId, eventType, payload.content).then(() => {
      this.emit('matrix-encrypted-message-sent', {
        roomId: normalizedRoomId,
        keyId: encrypted.keyId,
        eventType,
      })

      return payload
    })
  }

  decryptEncryptedMessage(ciphertextBody: string): { message: string; metadata: Record<string, unknown>; keyId: string } {
    return this.encryption.decryptMessage(ciphertextBody)
  }

  exportVaultBackup(backupKeyMaterial?: string, metadata: Record<string, unknown> = {}): CollaborationMessageVaultBackup {
    return this.encryption.exportVaultBackup(backupKeyMaterial, metadata)
  }
}