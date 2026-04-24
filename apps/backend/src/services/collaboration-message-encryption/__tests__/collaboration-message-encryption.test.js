import { describe, expect, it } from 'vitest';
import { CollaborationMessageEncryptionService } from '../index';
const encryptionKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
describe('CollaborationMessageEncryptionService', () => {
    it('encrypts and decrypts collaboration payloads without exposing plaintext in the envelope', () => {
        const service = new CollaborationMessageEncryptionService({ keyMaterial: encryptionKey });
        const encrypted = service.encryptMessage('Share this only with the room', {
            channel: 'matrix',
            roomId: '!room:example.org',
        });
        expect(encrypted.algorithm).toBe('aes-256-gcm');
        expect(encrypted.body).not.toContain('Share this only with the room');
        const decrypted = service.decryptMessage(encrypted.body);
        expect(decrypted.message).toBe('Share this only with the room');
        expect(decrypted.metadata).toEqual({ channel: 'matrix', roomId: '!room:example.org' });
        expect(decrypted.keyId).toBe(encrypted.keyId);
    });
    it('rejects tampered ciphertext', () => {
        const service = new CollaborationMessageEncryptionService({ keyMaterial: encryptionKey });
        const encrypted = service.encryptMessage('Forward secrecy matters', { channel: 'matrix' });
        const envelope = JSON.parse(encrypted.body);
        envelope.ciphertext = envelope.ciphertext.slice(0, -2) + 'AA';
        expect(() => service.decryptMessage(JSON.stringify(envelope))).toThrow();
    });
});
//# sourceMappingURL=collaboration-message-encryption.test.js.map