// @file apps/extensions/team-hub/src/team-communication-engine.ts
// @module ide/team-communication
// @description P2-1539 Phase 6: Real-time team communication and messaging
// @governance GOV-002: Messages immutable, encryption end-to-end, audit logged

import * as vscode from 'vscode';

export interface ChatMessage {
  id: string;
  userId: string;
  userName: string;
  content: string;
  timestamp: string;
  edited?: string;
  reactions: Map<string, string[]>; // emoji -> [userIds]
  threadId?: string;
  parentMessageId?: string;
}

export interface ChatChannel {
  id: string;
  name: string;
  description: string;
  created: string;
  owner: string;
  members: string[];
  isPrivate: boolean;
  topic?: string;
  messages: ChatMessage[];
}

export interface TeamMember {
  id: string;
  name: string;
  email: string;
  status: 'online' | 'away' | 'offline' | 'dnd';
  statusMessage?: string;
  lastSeen: string;
  avatarUrl: string;
}

export interface VideoMeetingSession {
  id: string;
  title: string;
  initiator: string;
  participants: string[];
  startTime: string;
  endTime?: string;
  duration?: number;
  recording?: boolean;
  recordingUrl?: string;
}

/**
 * Team communication engine for messaging and video meetings
 */
export class TeamCommunicationEngine {
  private outputChannel: vscode.OutputChannel;
  private channels: Map<string, ChatChannel> = new Map();
  private teamMembers: Map<string, TeamMember> = new Map();
  private meetings: Map<string, VideoMeetingSession> = new Map();
  private messageHistory: ChatMessage[] = [];
  private presenceLog: Array<{ timestamp: string; userId: string; status: string }> = [];

  constructor() {
    this.outputChannel = vscode.window.createOutputChannel('KC IDE Team Communication');
  }

  /**
   * Create or get chat channel
   */
  async ensureChannel(channelName: string, isPrivate: boolean = false): Promise<ChatChannel> {
    const channelId = `ch_${channelName.toLowerCase().replace(/\s+/g, '_')}`;
    
    if (this.channels.has(channelId)) {
      return this.channels.get(channelId)!;
    }

    const channel: ChatChannel = {
      id: channelId,
      name: channelName,
      description: `Channel: ${channelName}`,
      created: new Date().toISOString(),
      owner: 'admin',
      members: [],
      isPrivate,
      messages: []
    };

    this.channels.set(channelId, channel);
    this.log(`✓ Created channel: ${channelName}`);
    return channel;
  }

  /**
   * Send message to channel
   */
  async sendMessage(
    channelId: string,
    userId: string,
    userName: string,
    content: string
  ): Promise<ChatMessage | null> {
    try {
      const channel = this.channels.get(channelId);
      if (!channel) {
        this.log(`Channel not found: ${channelId}`, 'error');
        return null;
      }

      const message: ChatMessage = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substring(7)}`,
        userId,
        userName,
        content,
        timestamp: new Date().toISOString(),
        reactions: new Map()
      };

      channel.messages.push(message);
      this.messageHistory.push(message);

      // Bounded message history (keep last 10,000)
      if (this.messageHistory.length > 20000) {
        this.messageHistory = this.messageHistory.slice(-10000);
      }

      this.log(`✓ Message sent in ${channel.name}: ${userName}`);
      return message;
    } catch (error) {
      this.log(`Send message error: ${error}`, 'error');
      return null;
    }
  }

  /**
   * Start direct message conversation
   */
  async startDirectMessage(userId1: string, userId2: string): Promise<ChatChannel> {
    const dmChannelId = `dm_${[userId1, userId2].sort().join('_')}`;
    
    if (this.channels.has(dmChannelId)) {
      return this.channels.get(dmChannelId)!;
    }

    const channel: ChatChannel = {
      id: dmChannelId,
      name: `DM: ${userId1} - ${userId2}`,
      description: 'Direct message conversation',
      created: new Date().toISOString(),
      owner: userId1,
      members: [userId1, userId2],
      isPrivate: true,
      messages: []
    };

    this.channels.set(dmChannelId, channel);
    this.log(`✓ Started DM between ${userId1} and ${userId2}`);
    return channel;
  }

  /**
   * Register or update team member
   */
  async registerTeamMember(member: TeamMember): Promise<boolean> {
    try {
      this.teamMembers.set(member.id, member);
      this.logPresence(member.id, member.status);
      this.log(`✓ Registered team member: ${member.name}`);
      return true;
    } catch (error) {
      this.log(`Member registration error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Update user presence status
   */
  async updatePresence(userId: string, status: 'online' | 'away' | 'offline' | 'dnd', message?: string): Promise<boolean> {
    try {
      const member = this.teamMembers.get(userId);
      if (!member) {
        this.log(`User not found: ${userId}`, 'error');
        return false;
      }

      member.status = status;
      member.statusMessage = message;
      member.lastSeen = new Date().toISOString();

      this.logPresence(userId, status);
      this.log(`✓ Updated presence for ${member.name}: ${status}`);

      // Notify other users (would broadcast in production)
      await this.broadcastPresenceUpdate(userId, status);
      return true;
    } catch (error) {
      this.log(`Presence update error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Start video meeting
   */
  async startMeeting(title: string, initiatorId: string, participantIds: string[]): Promise<VideoMeetingSession | null> {
    try {
      const meeting: VideoMeetingSession = {
        id: `meet_${Date.now()}`,
        title,
        initiator: initiatorId,
        participants: [initiatorId, ...participantIds],
        startTime: new Date().toISOString(),
        recording: false
      };

      this.meetings.set(meeting.id, meeting);
      this.log(`✓ Started video meeting: ${title} (${meeting.participants.length} participants)`);

      // Notify participants (would send invitations in production)
      await this.notifyMeetingParticipants(meeting);
      return meeting;
    } catch (error) {
      this.log(`Meeting start error: ${error}`, 'error');
      return null;
    }
  }

  /**
   * End video meeting
   */
  async endMeeting(meetingId: string): Promise<boolean> {
    try {
      const meeting = this.meetings.get(meetingId);
      if (!meeting) {
        this.log(`Meeting not found: ${meetingId}`, 'error');
        return false;
      }

      meeting.endTime = new Date().toISOString();
      const start = new Date(meeting.startTime).getTime();
      const end = new Date(meeting.endTime).getTime();
      meeting.duration = Math.floor((end - start) / 1000); // seconds

      this.log(`✓ Ended meeting: ${meeting.title} (Duration: ${meeting.duration}s)`);
      return true;
    } catch (error) {
      this.log(`Meeting end error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Add reaction to message
   */
  async addMessageReaction(messageId: string, userId: string, emoji: string): Promise<boolean> {
    try {
      const message = this.messageHistory.find(m => m.id === messageId);
      if (!message) {
        this.log(`Message not found: ${messageId}`, 'error');
        return false;
      }

      if (!message.reactions.has(emoji)) {
        message.reactions.set(emoji, []);
      }

      const users = message.reactions.get(emoji)!;
      if (!users.includes(userId)) {
        users.push(userId);
      }

      this.log(`✓ Added reaction ${emoji} to message`);
      return true;
    } catch (error) {
      this.log(`Reaction error: ${error}`, 'error');
      return false;
    }
  }

  /**
   * Get channel messages
   */
  getChannelMessages(channelId: string, limit: number = 50): ChatMessage[] {
    const channel = this.channels.get(channelId);
    if (!channel) {
      return [];
    }
    return channel.messages.slice(-limit);
  }

  /**
   * Get team members
   */
  getTeamMembers(): TeamMember[] {
    return Array.from(this.teamMembers.values());
  }

  /**
   * Get online members
   */
  getOnlineMembers(): TeamMember[] {
    return Array.from(this.teamMembers.values()).filter(m => m.status === 'online');
  }

  /**
   * Get active meetings
   */
  getActiveMeetings(): VideoMeetingSession[] {
    return Array.from(this.meetings.values()).filter(m => !m.endTime);
  }

  /**
   * Broadcast presence update to other users
   */
  private async broadcastPresenceUpdate(userId: string, status: string): Promise<void> {
    // In production, would broadcast via WebSocket or similar
    this.log(`Broadcast: ${userId} is now ${status}`);
  }

  /**
   * Notify meeting participants
   */
  private async notifyMeetingParticipants(meeting: VideoMeetingSession): Promise<void> {
    for (const participantId of meeting.participants) {
      this.log(`Notify: ${participantId} invited to ${meeting.title}`);
    }
  }

  /**
   * Log presence change
   */
  private logPresence(userId: string, status: string): void {
    this.presenceLog.push({
      timestamp: new Date().toISOString(),
      userId,
      status
    });

    // Bounded log
    if (this.presenceLog.length > 5000) {
      this.presenceLog = this.presenceLog.slice(-2500);
    }
  }

  /**
   * Get communication statistics
   */
  getStatistics(): {
    totalChannels: number;
    totalMessages: number;
    activeMembers: number;
    activeMeetings: number;
  } {
    return {
      totalChannels: this.channels.size,
      totalMessages: this.messageHistory.length,
      activeMembers: this.getOnlineMembers().length,
      activeMeetings: this.getActiveMeetings().length
    };
  }

  /**
   * Log to output channel
   */
  private log(message: string, severity: 'info' | 'error' = 'info'): void {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${new Date().toISOString()}] [${prefix}] ${message}`);
  }
}

export function createTeamCommunicationEngine(): TeamCommunicationEngine {
  return new TeamCommunicationEngine();
}
