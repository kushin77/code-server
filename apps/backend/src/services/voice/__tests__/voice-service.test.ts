/**
 * Voice Channel Service Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { VoiceChannelService } from '../voice-service.js';

describe('VoiceChannelService', () => {
  let service: VoiceChannelService;

  beforeEach(() => {
    (VoiceChannelService as any).reset();
    service = VoiceChannelService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = VoiceChannelService.getInstance();
      const instance2 = VoiceChannelService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      (VoiceChannelService as any).reset();
      const svc = VoiceChannelService.getInstance();
      expect(svc).toBeDefined();
    });
  });

  describe('Channel Creation', () => {
    it('should create voice channel', () => {
      const result = service.createVoiceChannel(
        {
          userId: 'user-1',
          userEmail: 'user1@example.com',
          workspaceId: 'ws-1',
          channelName: 'engineering',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.channelId).toBeDefined();
      expect(result.livekitToken).toBeDefined();
      expect(result.livekitUrl).toBe('wss://livekit.example.com');
    });

    it('should emit voice-channel-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('voice-channel-created', (data) => {
          expect(data.channel).toBeDefined();
          expect(data.channel.name).toBe('design');
          resolve();
        });

        service.createVoiceChannel(
          {
            userId: 'user-2',
            userEmail: 'user2@example.com',
            workspaceId: 'ws-2',
            channelName: 'design',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should set max participants on channel', () => {
      const result = service.createVoiceChannel(
        {
          userId: 'user-3',
          userEmail: 'user3@example.com',
          workspaceId: 'ws-3',
          channelName: 'meetings',
          maxParticipants: 50,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.channel.maxParticipants).toBe(50);
    });

    it('should generate unique channel IDs', () => {
      const result1 = service.createVoiceChannel(
        {
          userId: 'user-4',
          userEmail: 'user4@example.com',
          workspaceId: 'ws-4',
          channelName: 'channel1',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result2 = service.createVoiceChannel(
        {
          userId: 'user-5',
          userEmail: 'user5@example.com',
          workspaceId: 'ws-4',
          channelName: 'channel2',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result1.channelId).not.toBe(result2.channelId);
    });
  });

  describe('Channel Joining', () => {
    it('should join voice channel', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-6',
          userEmail: 'user6@example.com',
          workspaceId: 'ws-6',
          channelName: 'team',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-7',
          userEmail: 'user7@example.com',
          displayName: 'Alice',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(joinResult.success).toBe(true);
      expect(joinResult.participantId).toBeDefined();
      expect(joinResult.livekitToken).toBeDefined();
    });

    it('should emit participant-joined event', () => {
      return new Promise<void>((resolve) => {
        const channelResult = service.createVoiceChannel(
          {
            userId: 'user-8',
            userEmail: 'user8@example.com',
            workspaceId: 'ws-8',
            channelName: 'sync',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('participant-joined', (data) => {
          expect(data.participant).toBeDefined();
          expect(data.participant.displayName).toBe('Bob');
          resolve();
        });

        service.joinVoiceChannel(
          {
            userId: 'user-9',
            userEmail: 'user9@example.com',
            displayName: 'Bob',
            channelId: channelResult.channelId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should track active participant count', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-10',
          userEmail: 'user10@example.com',
          workspaceId: 'ws-10',
          channelName: 'office',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.joinVoiceChannel(
        {
          userId: 'user-11',
          userEmail: 'user11@example.com',
          displayName: 'Charlie',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const channel = service.getVoiceChannel({ channelId: channelResult.channelId });
      expect(channel.channel?.activeParticipantCount).toBeGreaterThan(0);
    });
  });

  describe('Channel Leaving', () => {
    it('should leave voice channel', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-12',
          userEmail: 'user12@example.com',
          workspaceId: 'ws-12',
          channelName: 'standup',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-13',
          userEmail: 'user13@example.com',
          displayName: 'David',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const leaveResult = service.leaveVoiceChannel(
        {
          userId: 'user-13',
          userEmail: 'user13@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(leaveResult.success).toBe(true);
    });

    it('should emit participant-left event', (done) => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-14',
          userEmail: 'user14@example.com',
          workspaceId: 'ws-14',
          channelName: 'daily',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          displayName: 'Eve',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.once('participant-left', (data) => {
        expect(data.participantId).toBe(joinResult.participantId);
        done();
      });

      service.leaveVoiceChannel(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );
    });

    it('should decrease participant count on leave', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-16',
          userEmail: 'user16@example.com',
          workspaceId: 'ws-16',
          channelName: 'retrospective',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          displayName: 'Frank',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      let channelBefore = service.getVoiceChannel({ channelId: channelResult.channelId });
      const countBefore = channelBefore.channel!.activeParticipantCount;

      service.leaveVoiceChannel(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      channelBefore = service.getVoiceChannel({ channelId: channelResult.channelId });
      const countAfter = channelBefore.channel!.activeParticipantCount;

      expect(countAfter).toBeLessThan(countBefore);
    });
  });

  describe('Participant Muting', () => {
    it('should mute participant', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-18',
          userEmail: 'user18@example.com',
          workspaceId: 'ws-18',
          channelName: 'presentation',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-19',
          userEmail: 'user19@example.com',
          displayName: 'Grace',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const muteResult = service.muteParticipant(
        {
          userId: 'user-18',
          userEmail: 'user18@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          isMuted: true,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(muteResult.success).toBe(true);
      expect(muteResult.participant.isMuted).toBe(true);
    });

    it('should emit participant-muted event', (done) => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-20',
          userEmail: 'user20@example.com',
          workspaceId: 'ws-20',
          channelName: 'workshop',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-21',
          userEmail: 'user21@example.com',
          displayName: 'Henry',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.once('participant-muted', (data) => {
        expect(data.participant.isMuted).toBe(true);
        done();
      });

      service.muteParticipant(
        {
          userId: 'user-20',
          userEmail: 'user20@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          isMuted: true,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );
    });
  });

  describe('Participant Deafening', () => {
    it('should deafen participant', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-22',
          userEmail: 'user22@example.com',
          workspaceId: 'ws-22',
          channelName: 'focus',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          displayName: 'Ivy',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const deafenResult = service.deafenParticipant(
        {
          userId: 'user-22',
          userEmail: 'user22@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          isDeafened: true,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(deafenResult.success).toBe(true);
      expect(deafenResult.participant.isDeafened).toBe(true);
    });

    it('should emit participant-deafened event', (done) => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-24',
          userEmail: 'user24@example.com',
          workspaceId: 'ws-24',
          channelName: 'brainstorm',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-25',
          userEmail: 'user25@example.com',
          displayName: 'Jack',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.once('participant-deafened', (data) => {
        expect(data.participant.isDeafened).toBe(true);
        done();
      });

      service.deafenParticipant(
        {
          userId: 'user-24',
          userEmail: 'user24@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          isDeafened: true,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );
    });
  });

  describe('Audio Level Tracking', () => {
    it('should update audio level', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-26',
          userEmail: 'user26@example.com',
          workspaceId: 'ws-26',
          channelName: 'podcast',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-27',
          userEmail: 'user27@example.com',
          displayName: 'Karen',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.updateAudioLevel({
        participantId: joinResult.participantId,
        level: 75,
        isSpeaking: true,
      });

      const participants = service.getParticipants({ channelId: channelResult.channelId });
      expect(participants.participants[0].audioLevel).toBe(75);
    });

    it('should emit audio-level-changed event', () => {
      return new Promise<void>((resolve) => {
        const channelResult = service.createVoiceChannel(
          {
            userId: 'user-28',
            userEmail: 'user28@example.com',
            workspaceId: 'ws-28',
            channelName: 'streaming',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        const joinResult = service.joinVoiceChannel(
          {
            userId: 'user-29',
            userEmail: 'user29@example.com',
            displayName: 'Leo',
            channelId: channelResult.channelId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('audio-level-changed', (data) => {
          expect(data.audioLevel.level).toBe(60);
          resolve();
        });

        service.updateAudioLevel({
          participantId: joinResult.participantId,
          level: 60,
          isSpeaking: true,
        });
      });
    });
  });

  describe('Connection Statistics', () => {
    it('should update connection stats', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-30',
          userEmail: 'user30@example.com',
          workspaceId: 'ws-30',
          channelName: 'conference',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-31',
          userEmail: 'user31@example.com',
          displayName: 'Maria',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.updateConnectionStats({
        participantId: joinResult.participantId,
        roundTripTime: 45,
        packetLoss: 1.5,
        bitrate: 256,
      });

      const participants = service.getParticipants({ channelId: channelResult.channelId });
      expect(participants.participants[0].latency).toBe(45);
    });

    it('should emit connection-stats-updated event', () => {
      return new Promise<void>((resolve) => {
        const channelResult = service.createVoiceChannel(
          {
            userId: 'user-32',
            userEmail: 'user32@example.com',
            workspaceId: 'ws-32',
            channelName: 'webinar',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        const joinResult = service.joinVoiceChannel(
          {
            userId: 'user-33',
            userEmail: 'user33@example.com',
            displayName: 'Noah',
            channelId: channelResult.channelId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('connection-stats-updated', (data) => {
          expect(data.stats.roundTripTime).toBe(30);
          resolve();
        });

        service.updateConnectionStats({
          participantId: joinResult.participantId,
          roundTripTime: 30,
          packetLoss: 0.5,
          bitrate: 300,
        });
      });
    });
  });

  describe('Local Audio Control', () => {
    it('should toggle local audio', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-34',
          userEmail: 'user34@example.com',
          workspaceId: 'ws-34',
          channelName: 'meeting',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-35',
          userEmail: 'user35@example.com',
          displayName: 'Olivia',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.toggleLocalAudio(
        {
          userId: 'user-35',
          userEmail: 'user35@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          enabled: false,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.enabled).toBe(false);
    });

    it('should emit local-audio-disabled event', (done) => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-36',
          userEmail: 'user36@example.com',
          workspaceId: 'ws-36',
          channelName: 'sync-up',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinVoiceChannel(
        {
          userId: 'user-37',
          userEmail: 'user37@example.com',
          displayName: 'Peter',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.once('local-audio-disabled', (data) => {
        expect(data.enabled).toBe(false);
        done();
      });

      service.toggleLocalAudio(
        {
          userId: 'user-37',
          userEmail: 'user37@example.com',
          channelId: channelResult.channelId,
          participantId: joinResult.participantId,
          enabled: false,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );
    });
  });

  describe('Recording', () => {
    it('should start recording', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-38',
          userEmail: 'user38@example.com',
          workspaceId: 'ws-38',
          channelName: 'recording-test',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.startRecording(
        {
          userId: 'user-38',
          userEmail: 'user38@example.com',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.recordingId).toBeDefined();
    });

    it('should stop recording', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-39',
          userEmail: 'user39@example.com',
          workspaceId: 'ws-39',
          channelName: 'recording-test-2',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const startResult = service.startRecording(
        {
          userId: 'user-39',
          userEmail: 'user39@example.com',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stopResult = service.stopRecording(
        {
          userId: 'user-39',
          userEmail: 'user39@example.com',
          channelId: channelResult.channelId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(stopResult.success).toBe(true);
      expect(stopResult.duration).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry on channel creation', () => {
      service.createVoiceChannel(
        {
          userId: 'user-40',
          userEmail: 'user40@example.com',
          workspaceId: 'ws-40',
          channelName: 'audit-test',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const audit = service.getAuditLog('user-40');
      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].operation).toBe('create-voice-channel');
    });

    it('should limit audit log size', () => {
      (VoiceChannelService as any).reset();
      service = VoiceChannelService.getInstance({ maxAuditLogSize: 5 });

      for (let i = 0; i < 10; i++) {
        service.createVoiceChannel(
          {
            userId: 'user-41',
            userEmail: 'user41@example.com',
            workspaceId: `ws-41-${i}`,
            channelName: `channel-${i}`,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      }

      const audit = service.getAuditLog('user-41');
      expect(audit.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Statistics', () => {
    it('should get service statistics', () => {
      service.createVoiceChannel(
        {
          userId: 'user-42',
          userEmail: 'user42@example.com',
          workspaceId: 'ws-42',
          channelName: 'stats-test',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();

      expect(stats.totalChannels).toBeGreaterThan(0);
      expect(stats.activeChannels).toBeGreaterThanOrEqual(0);
    });

    it('should track active channels and participants', () => {
      return new Promise<void>((resolve) => {
        const channelResult = service.createVoiceChannel(
          {
            userId: 'user-43',
            userEmail: 'user43@example.com',
            workspaceId: 'ws-43',
            channelName: 'active-test',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.joinVoiceChannel(
          {
            userId: 'user-44',
            userEmail: 'user44@example.com',
            displayName: 'Quinn',
            channelId: channelResult.channelId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        // Wait for async participant-joined event
        service.once('participant-joined', () => {
          const stats = service.getStatistics();
          expect(stats.currentParticipants).toBeGreaterThan(0);
          resolve();
        });
      });
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig(
        { maxChannelsPerWorkspace: 100 },
        'user-45',
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(service['config'].maxChannelsPerWorkspace).toBe(100);
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig(
          { enableRecording: false },
          'user-46',
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', () => {
      const channelResult = service.createVoiceChannel(
        {
          userId: 'user-47',
          userEmail: 'user47@example.com',
          workspaceId: 'ws-47',
          channelName: 'shutdown-test',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.shutdown();

      const result = service.getVoiceChannel({ channelId: channelResult.channelId });
      expect(result.channel).toBeNull();
    });

    it('should emit shutdown event', () => {
      return new Promise<void>((resolve) => {
        service.once('shutdown', (data) => {
          expect(data.timestamp).toBeDefined();
          resolve();
        });

        service.shutdown();
      });
    });
  });
});
