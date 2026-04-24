import { describe, expect, it, vi } from 'vitest'

import { CollaborationMessageEncryptionService } from '../../collaboration-message-encryption'
import { MatrixCollaborationTransportService } from '../index'

const encryptionKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
const backupKey = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210'

function createFakeMatrixClient() {
  return {
    createRoom: vi.fn(async (request: Record<string, unknown>) => ({ roomId: '!room:example.org', request })),
    sendEvent: vi.fn(async () => ({})),
  }
}

describe('MatrixCollaborationTransportService', () => {
  it('bootstraps encrypted rooms with Megolm-compatible state', async () => {
    const client = createFakeMatrixClient()
    const service = new MatrixCollaborationTransportService(
      client,
      new CollaborationMessageEncryptionService({ keyMaterial: encryptionKey })
    )

    const bootstrap = await service.bootstrapEncryptedRoom({
      roomName: 'Shared debug room',
      topic: 'Collaborative debugging',
      invite: ['@alice:example.org'],
      historyVisibility: 'shared',
    })

    expect(bootstrap.roomId).toBe('!room:example.org')
    expect(client.createRoom).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Shared debug room',
        topic: 'Collaborative debugging',
        invite: ['@alice:example.org'],
        preset: 'private_chat',
        initial_state: expect.arrayContaining([
          expect.objectContaining({
            type: 'm.room.encryption',
            state_key: '',
            content: expect.objectContaining({
              algorithm: 'm.megolm.v1.aes-sha2',
            }),
          }),
          expect.objectContaining({
            type: 'm.room.history_visibility',
            state_key: '',
            content: { history_visibility: 'shared' },
          }),
        ]),
      })
    )
  })

  it('sends ciphertext-only payloads through the Matrix client', async () => {
    const client = createFakeMatrixClient()
    const service = new MatrixCollaborationTransportService(
      client,
      new CollaborationMessageEncryptionService({ keyMaterial: encryptionKey })
    )

    const sent = await service.sendEncryptedMessage('!room:example.org', 'Share this only inside the room', {
      sessionId: 'session-1',
      roomId: '!room:example.org',
    })

    expect(client.sendEvent).toHaveBeenCalledWith(
      '!room:example.org',
      'com.code-server.collaboration.message',
      expect.objectContaining({
        encrypted: true,
        ciphertext: expect.any(String),
        keyId: expect.any(String),
        algorithm: 'aes-256-gcm',
        metadata: expect.objectContaining({ sessionId: 'session-1' }),
      })
    )
    expect(JSON.stringify(sent.content)).not.toContain('Share this only inside the room')

    const decrypted = service.decryptEncryptedMessage(sent.content.ciphertext)
    expect(decrypted.message).toBe('Share this only inside the room')
    expect(decrypted.keyId).toBe(sent.content.keyId)
  })

  it('restores the transport encryption path from a vault backup', async () => {
    const client = createFakeMatrixClient()
    const original = new MatrixCollaborationTransportService(
      client,
      new CollaborationMessageEncryptionService({ keyMaterial: encryptionKey })
    )

    const encrypted = await original.sendEncryptedMessage('!room:example.org', 'Recoverable collaboration message', {
      roomId: '!room:example.org',
      scope: 'debug',
    })
    const backup = original.exportVaultBackup(backupKey, { roomId: '!room:example.org' })

    const restored = MatrixCollaborationTransportService.restoreFromVaultBackup(client, backup.body, backupKey)
    const decrypted = restored.decryptEncryptedMessage(encrypted.content.ciphertext)

    expect(decrypted.message).toBe('Recoverable collaboration message')
    expect(restored.exportVaultBackup(backupKey, { roomId: '!room:example.org' }).keyId).toBe(backup.keyId)
  })
})