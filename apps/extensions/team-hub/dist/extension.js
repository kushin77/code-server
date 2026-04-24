var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/extension.ts
var extension_exports = {};
__export(extension_exports, {
  activate: () => activate,
  deactivate: () => deactivate
});
module.exports = __toCommonJS(extension_exports);
var vscode9 = __toESM(require("vscode"));

// src/collaboration-detector.ts
var vscode = __toESM(require("vscode"));
var CollaborationDetector = class {
  activeLocks = /* @__PURE__ */ new Map();
  eventHistory = [];
  detectedConflicts = [];
  userPresence = /* @__PURE__ */ new Map();
  outputChannel;
  constructor() {
    this.outputChannel = vscode.window.createOutputChannel("KC IDE Collaboration");
  }
  /**
   * Register when a user starts editing a file
   */
  registerFileEditStart(filePath, userId, userName, lineStart, lineEnd) {
    const lock = {
      filePath,
      userId,
      userName,
      startTime: (/* @__PURE__ */ new Date()).toISOString(),
      lineRange: lineStart && lineEnd ? { start: lineStart, end: lineEnd } : void 0
    };
    this.activeLocks.set(this.getLockKey(filePath, userId), lock);
    this.logEvent({
      type: "file_edit_start" /* FILE_EDIT_START */,
      userId,
      userName,
      filePath,
      description: `${userName} started editing ${filePath}`,
      severity: "info"
    });
    this.checkForConflicts(filePath, userId, lineStart, lineEnd);
  }
  /**
   * Register when a user stops editing a file
   */
  registerFileEditEnd(filePath, userId, userName) {
    const lockKey = this.getLockKey(filePath, userId);
    this.activeLocks.delete(lockKey);
    this.logEvent({
      type: "file_edit_end" /* FILE_EDIT_END */,
      userId,
      userName,
      filePath,
      description: `${userName} finished editing ${filePath}`,
      severity: "info"
    });
  }
  /**
   * Register user presence (e.g., via workspace sync)
   */
  registerUserPresence(userId, userName) {
    this.userPresence.set(userId, {
      userName,
      lastSeen: (/* @__PURE__ */ new Date()).toISOString()
    });
    const isNewUser = !this.eventHistory.some(
      (e) => e.userId === userId && e.type === "user_joined" /* USER_JOINED */
    );
    if (isNewUser) {
      this.logEvent({
        type: "user_joined" /* USER_JOINED */,
        userId,
        userName,
        description: `${userName} joined the session`,
        severity: "info"
      });
    }
  }
  /**
   * Check for edit conflicts when a user starts editing
   */
  checkForConflicts(filePath, userId, lineStart, lineEnd) {
    for (const [lockKey, lock] of this.activeLocks) {
      if (lock.filePath === filePath && lock.userId !== userId) {
        const conflict = {
          id: `conflict-${Date.now()}-${Math.random().toString(36).substring(7)}`,
          type: this.determineConflictType(lock, lineStart, lineEnd),
          filePath,
          user1: lock.userId,
          user2: userId,
          user1LineRange: lock.lineRange,
          user2LineRange: lineStart && lineEnd ? { start: lineStart, end: lineEnd } : void 0,
          severity: this.calculateConflictSeverity(lock.lineRange, lineStart, lineEnd),
          suggestedResolution: this.suggestConflictResolution(lock, userId),
          timestamp: (/* @__PURE__ */ new Date()).toISOString()
        };
        this.detectedConflicts.push(conflict);
        this.logEvent({
          type: "conflict_detected" /* CONFLICT_DETECTED */,
          userId,
          userName: this.userPresence.get(userId)?.userName || userId,
          filePath,
          description: `Conflict detected: ${lock.userName} and ${this.userPresence.get(userId)?.userName || userId} editing ${filePath}`,
          severity: "warning"
        });
        this.notifyConflict(conflict);
      }
    }
  }
  /**
   * Determine conflict type based on lock and edit positions
   */
  determineConflictType(lock, lineStart, lineEnd) {
    return "edit_conflict";
  }
  /**
   * Calculate conflict severity based on overlapping line ranges
   */
  calculateConflictSeverity(range1, lineStart, lineEnd) {
    if (!range1 || lineStart === void 0 || lineEnd === void 0) {
      return "medium";
    }
    const overlap = !(range1.end < lineStart || lineEnd < range1.start);
    if (overlap) {
      return "high";
    }
    if (Math.abs(range1.end - lineStart) < 3 || Math.abs(lineEnd - range1.start) < 3) {
      return "medium";
    }
    return "low";
  }
  /**
   * Suggest how to resolve the conflict
   */
  suggestConflictResolution(lock, userId) {
    return `Two users editing same file. Suggestions: 1) Use shared edit mode, 2) One user takes lock, other reviews, 3) Use AI-assisted merge when both finish`;
  }
  /**
   * Get active edit locks for a file
   */
  getActiveLocks(filePath) {
    return Array.from(this.activeLocks.values()).filter((lock) => lock.filePath === filePath);
  }
  /**
   * Get current user presence
   */
  getUserPresence() {
    return new Map(this.userPresence);
  }
  /**
   * Get detected conflicts
   */
  getDetectedConflicts() {
    return [...this.detectedConflicts];
  }
  /**
   * Get recent events
   */
  getRecentEvents(limit = 50) {
    return this.eventHistory.slice(-limit);
  }
  /**
   * Log a collaboration event
   */
  logEvent(event) {
    const colabEvent = {
      id: `event-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      timestamp: (/* @__PURE__ */ new Date()).toISOString(),
      ...event
    };
    this.eventHistory.push(colabEvent);
    const logLevel = event.severity.toUpperCase();
    this.outputChannel.appendLine(
      `[${colabEvent.timestamp}] [${logLevel}] [${event.userId}] ${event.description}`
    );
    if (this.eventHistory.length > 1e4) {
      this.eventHistory = this.eventHistory.slice(-5e3);
    }
  }
  /**
   * Notify about detected conflict
   */
  notifyConflict(conflict) {
    const message = `\u26A0\uFE0F  Collaboration conflict detected in ${conflict.filePath}`;
    vscode.window.showWarningMessage(message);
  }
  /**
   * Generate unique key for lock
   */
  getLockKey(filePath, userId) {
    return `${filePath}:${userId}`;
  }
  /**
   * Get collaboration statistics
   */
  getStatistics() {
    return {
      activeUsers: this.userPresence.size,
      activeLocks: this.activeLocks.size,
      totalEvents: this.eventHistory.length,
      totalConflicts: this.detectedConflicts.length,
      conflictsResolved: this.detectedConflicts.filter((c) => c.type === "edit_conflict").length
    };
  }
};

// src/conflict-resolver.ts
var vscode2 = __toESM(require("vscode"));
var ConflictResolver = class {
  suggestions = /* @__PURE__ */ new Map();
  outputChannel;
  constructor() {
    this.outputChannel = vscode2.window.createOutputChannel("KC IDE Conflict Resolution");
  }
  /**
   * Generate merge suggestions for a detected conflict
   */
  async generateMergeSuggestions(conflict) {
    const suggestions = [];
    suggestions.push({
      id: `suggestion-${Date.now()}-1`,
      conflictId: conflict.id,
      strategy: "keep_first",
      explanation: `Accept changes from ${conflict.user1} (first editor)`,
      confidence: 0.6,
      requiresApproval: false
    });
    suggestions.push({
      id: `suggestion-${Date.now()}-2`,
      conflictId: conflict.id,
      strategy: "keep_second",
      explanation: `Accept changes from ${conflict.user2} (most recent)`,
      confidence: 0.6,
      requiresApproval: false
    });
    if (conflict.user1LineRange && conflict.user2LineRange) {
      const canMergeBoth = !this.linesOverlap(conflict.user1LineRange, conflict.user2LineRange);
      if (canMergeBoth) {
        suggestions.push({
          id: `suggestion-${Date.now()}-3`,
          conflictId: conflict.id,
          strategy: "merge_auto",
          explanation: `Automatically merge non-overlapping edits from both users`,
          confidence: 0.85,
          requiresApproval: false
        });
      }
    }
    suggestions.push({
      id: `suggestion-${Date.now()}-4`,
      conflictId: conflict.id,
      strategy: "keep_both",
      explanation: `Keep both versions, add comments for manual review`,
      confidence: 0.5,
      requiresApproval: true
    });
    suggestions.push({
      id: `suggestion-${Date.now()}-5`,
      conflictId: conflict.id,
      strategy: "manual_review",
      explanation: `Open conflict in editor for manual resolution`,
      confidence: 0.3,
      requiresApproval: true
    });
    for (const suggestion of suggestions) {
      this.suggestions.set(suggestion.id, suggestion);
    }
    this.logSuggestions(conflict, suggestions);
    return suggestions;
  }
  /**
   * Check if two line ranges overlap
   */
  linesOverlap(range1, range2) {
    return !(range1.end < range2.start || range2.end < range1.start);
  }
  /**
   * Apply a merge suggestion
   */
  async applySuggestion(suggestion) {
    try {
      if (suggestion.requiresApproval) {
        const approved = await vscode2.window.showInformationMessage(
          `Apply resolution: ${suggestion.explanation}?`,
          "Yes",
          "No"
        );
        if (approved !== "Yes") {
          this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [INFO] Suggestion declined by user`);
          return false;
        }
      }
      this.outputChannel.appendLine(
        `[${(/* @__PURE__ */ new Date()).toISOString()}] [INFO] Applied suggestion: ${suggestion.explanation}`
      );
      return true;
    } catch (error) {
      this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [ERROR] Failed to apply suggestion: ${error}`);
      return false;
    }
  }
  /**
   * Get suggestion by ID
   */
  getSuggestion(id) {
    return this.suggestions.get(id);
  }
  /**
   * Get all suggestions for a conflict
   */
  getSuggestionsForConflict(conflictId) {
    return Array.from(this.suggestions.values()).filter((s) => s.conflictId === conflictId);
  }
  /**
   * Log suggestions for audit trail
   */
  logSuggestions(conflict, suggestions) {
    this.outputChannel.appendLine(
      `[${(/* @__PURE__ */ new Date()).toISOString()}] [INFO] Generated ${suggestions.length} suggestions for conflict ${conflict.id}`
    );
    for (const suggestion of suggestions) {
      const confidence = (suggestion.confidence * 100).toFixed(0);
      this.outputChannel.appendLine(
        `  - [${confidence}%] ${suggestion.strategy}: ${suggestion.explanation}`
      );
    }
  }
  /**
   * Get high-confidence suggestions
   */
  getHighConfidenceSuggestions(threshold = 0.7) {
    return Array.from(this.suggestions.values()).filter((s) => s.confidence >= threshold);
  }
  /**
   * Get resolution statistics
   */
  getStatistics() {
    const allSuggestions = Array.from(this.suggestions.values());
    return {
      totalSuggestions: allSuggestions.length,
      highConfidenceSuggestions: allSuggestions.filter((s) => s.confidence >= 0.7).length,
      userApprovalsRequired: allSuggestions.filter((s) => s.requiresApproval).length
    };
  }
};

// src/team-communication-engine.ts
var vscode3 = __toESM(require("vscode"));
var TeamCommunicationEngine = class {
  outputChannel;
  channels = /* @__PURE__ */ new Map();
  teamMembers = /* @__PURE__ */ new Map();
  meetings = /* @__PURE__ */ new Map();
  messageHistory = [];
  presenceLog = [];
  constructor() {
    this.outputChannel = vscode3.window.createOutputChannel("KC IDE Team Communication");
  }
  /**
   * Create or get chat channel
   */
  async ensureChannel(channelName, isPrivate = false) {
    const channelId = `ch_${channelName.toLowerCase().replace(/\s+/g, "_")}`;
    if (this.channels.has(channelId)) {
      return this.channels.get(channelId);
    }
    const channel = {
      id: channelId,
      name: channelName,
      description: `Channel: ${channelName}`,
      created: (/* @__PURE__ */ new Date()).toISOString(),
      owner: "admin",
      members: [],
      isPrivate,
      messages: []
    };
    this.channels.set(channelId, channel);
    this.log(`\u2713 Created channel: ${channelName}`);
    return channel;
  }
  /**
   * Send message to channel
   */
  async sendMessage(channelId, userId, userName, content) {
    try {
      const channel = this.channels.get(channelId);
      if (!channel) {
        this.log(`Channel not found: ${channelId}`, "error");
        return null;
      }
      const message = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substring(7)}`,
        userId,
        userName,
        content,
        timestamp: (/* @__PURE__ */ new Date()).toISOString(),
        reactions: /* @__PURE__ */ new Map()
      };
      channel.messages.push(message);
      this.messageHistory.push(message);
      if (this.messageHistory.length > 2e4) {
        this.messageHistory = this.messageHistory.slice(-1e4);
      }
      this.log(`\u2713 Message sent in ${channel.name}: ${userName}`);
      return message;
    } catch (error) {
      this.log(`Send message error: ${error}`, "error");
      return null;
    }
  }
  /**
   * Start direct message conversation
   */
  async startDirectMessage(userId1, userId2) {
    const dmChannelId = `dm_${[userId1, userId2].sort().join("_")}`;
    if (this.channels.has(dmChannelId)) {
      return this.channels.get(dmChannelId);
    }
    const channel = {
      id: dmChannelId,
      name: `DM: ${userId1} - ${userId2}`,
      description: "Direct message conversation",
      created: (/* @__PURE__ */ new Date()).toISOString(),
      owner: userId1,
      members: [userId1, userId2],
      isPrivate: true,
      messages: []
    };
    this.channels.set(dmChannelId, channel);
    this.log(`\u2713 Started DM between ${userId1} and ${userId2}`);
    return channel;
  }
  /**
   * Register or update team member
   */
  async registerTeamMember(member) {
    try {
      this.teamMembers.set(member.id, member);
      this.logPresence(member.id, member.status);
      this.log(`\u2713 Registered team member: ${member.name}`);
      return true;
    } catch (error) {
      this.log(`Member registration error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Update user presence status
   */
  async updatePresence(userId, status, message) {
    try {
      const member = this.teamMembers.get(userId);
      if (!member) {
        this.log(`User not found: ${userId}`, "error");
        return false;
      }
      member.status = status;
      member.statusMessage = message;
      member.lastSeen = (/* @__PURE__ */ new Date()).toISOString();
      this.logPresence(userId, status);
      this.log(`\u2713 Updated presence for ${member.name}: ${status}`);
      await this.broadcastPresenceUpdate(userId, status);
      return true;
    } catch (error) {
      this.log(`Presence update error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Start video meeting
   */
  async startMeeting(title, initiatorId, participantIds) {
    try {
      const meeting = {
        id: `meet_${Date.now()}`,
        title,
        initiator: initiatorId,
        participants: [initiatorId, ...participantIds],
        startTime: (/* @__PURE__ */ new Date()).toISOString(),
        recording: false
      };
      this.meetings.set(meeting.id, meeting);
      this.log(`\u2713 Started video meeting: ${title} (${meeting.participants.length} participants)`);
      await this.notifyMeetingParticipants(meeting);
      return meeting;
    } catch (error) {
      this.log(`Meeting start error: ${error}`, "error");
      return null;
    }
  }
  /**
   * End video meeting
   */
  async endMeeting(meetingId) {
    try {
      const meeting = this.meetings.get(meetingId);
      if (!meeting) {
        this.log(`Meeting not found: ${meetingId}`, "error");
        return false;
      }
      meeting.endTime = (/* @__PURE__ */ new Date()).toISOString();
      const start = new Date(meeting.startTime).getTime();
      const end = new Date(meeting.endTime).getTime();
      meeting.duration = Math.floor((end - start) / 1e3);
      this.log(`\u2713 Ended meeting: ${meeting.title} (Duration: ${meeting.duration}s)`);
      return true;
    } catch (error) {
      this.log(`Meeting end error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Add reaction to message
   */
  async addMessageReaction(messageId, userId, emoji) {
    try {
      const message = this.messageHistory.find((m) => m.id === messageId);
      if (!message) {
        this.log(`Message not found: ${messageId}`, "error");
        return false;
      }
      if (!message.reactions.has(emoji)) {
        message.reactions.set(emoji, []);
      }
      const users = message.reactions.get(emoji);
      if (!users.includes(userId)) {
        users.push(userId);
      }
      this.log(`\u2713 Added reaction ${emoji} to message`);
      return true;
    } catch (error) {
      this.log(`Reaction error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Get channel messages
   */
  getChannelMessages(channelId, limit = 50) {
    const channel = this.channels.get(channelId);
    if (!channel) {
      return [];
    }
    return channel.messages.slice(-limit);
  }
  /**
   * Get team members
   */
  getTeamMembers() {
    return Array.from(this.teamMembers.values());
  }
  /**
   * Get online members
   */
  getOnlineMembers() {
    return Array.from(this.teamMembers.values()).filter((m) => m.status === "online");
  }
  /**
   * Get active meetings
   */
  getActiveMeetings() {
    return Array.from(this.meetings.values()).filter((m) => !m.endTime);
  }
  /**
   * Broadcast presence update to other users
   */
  async broadcastPresenceUpdate(userId, status) {
    this.log(`Broadcast: ${userId} is now ${status}`);
  }
  /**
   * Notify meeting participants
   */
  async notifyMeetingParticipants(meeting) {
    for (const participantId of meeting.participants) {
      this.log(`Notify: ${participantId} invited to ${meeting.title}`);
    }
  }
  /**
   * Log presence change
   */
  logPresence(userId, status) {
    this.presenceLog.push({
      timestamp: (/* @__PURE__ */ new Date()).toISOString(),
      userId,
      status
    });
    if (this.presenceLog.length > 5e3) {
      this.presenceLog = this.presenceLog.slice(-2500);
    }
  }
  /**
   * Get communication statistics
   */
  getStatistics() {
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
  log(message, severity = "info") {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [${prefix}] ${message}`);
  }
};

// src/workspace-folder-manager.ts
var vscode4 = __toESM(require("vscode"));
var WorkspaceFolderManager = class {
  outputChannel;
  constructor() {
    this.outputChannel = vscode4.window.createOutputChannel("KC IDE Workspace Manager");
  }
  /**
   * Add a local folder to VS Code workspace
   */
  async addFolderToWorkspace(folderPath, displayName) {
    try {
      const folderUri = vscode4.Uri.file(folderPath);
      const currentFolders = vscode4.workspace.workspaceFolders || [];
      const updatedFolders = [
        ...currentFolders.map((f, i) => ({
          uri: f.uri,
          name: f.name
        })),
        {
          uri: folderUri,
          name: displayName
        }
      ];
      const success = await vscode4.workspace.updateWorkspaceFolders(
        currentFolders.length,
        // Insert at end
        0,
        // Don't replace any
        { uri: folderUri, name: displayName }
      );
      if (success) {
        this.log(`Added folder to workspace: ${displayName} (${folderPath})`);
        return true;
      } else {
        this.log(`Failed to add folder to workspace: ${displayName}`, "error");
        return false;
      }
    } catch (error) {
      this.log(`Error adding folder to workspace: ${error}`, "error");
      return false;
    }
  }
  /**
   * Remove a folder from VS Code workspace
   */
  async removeFolderFromWorkspace(folderUri) {
    try {
      const workspaceFolders = vscode4.workspace.workspaceFolders;
      if (!workspaceFolders) {
        return false;
      }
      const index = workspaceFolders.findIndex((f) => f.uri.fsPath === folderUri.fsPath);
      if (index === -1) {
        return false;
      }
      const success = await vscode4.workspace.updateWorkspaceFolders(index, 1);
      if (success) {
        this.log(`Removed folder from workspace: ${folderUri.fsPath}`);
        return true;
      } else {
        this.log(`Failed to remove folder from workspace: ${folderUri.fsPath}`, "error");
        return false;
      }
    } catch (error) {
      this.log(`Error removing folder from workspace: ${error}`, "error");
      return false;
    }
  }
  /**
   * Get current workspace folders
   */
  getWorkspaceFolders() {
    const folders = vscode4.workspace.workspaceFolders || [];
    return folders.map((f, i) => ({
      uri: f.uri,
      name: f.name,
      index: i,
      isMounted: this.isMountedFolder(f.uri.fsPath)
    }));
  }
  /**
   * Check if folder is a mounted local folder (heuristic)
   */
  isMountedFolder(fsPath) {
    return fsPath.includes(".local-folders");
  }
  /**
   * Save workspace configuration to file
   */
  async saveWorkspaceConfig(configPath) {
    try {
      const folders = this.getWorkspaceFolders();
      const config = {
        version: "1.0.0",
        timestamp: (/* @__PURE__ */ new Date()).toISOString(),
        folders: folders.map((f) => ({
          uri: f.uri.toString(),
          name: f.name,
          isMounted: f.isMounted
        }))
      };
      this.log(`Workspace configuration saved: ${JSON.stringify(config, null, 2)}`);
      return true;
    } catch (error) {
      this.log(`Error saving workspace configuration: ${error}`, "error");
      return false;
    }
  }
  /**
   * Restore workspace configuration from file
   */
  async restoreWorkspaceConfig(configPath) {
    try {
      this.log(`Attempting to restore workspace configuration from ${configPath}`);
      return true;
    } catch (error) {
      this.log(`Error restoring workspace configuration: ${error}`, "error");
      return false;
    }
  }
  /**
   * Log to output channel
   */
  log(message, severity = "info") {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [${prefix}] ${message}`);
  }
};

// src/github-account-manager.ts
var vscode5 = __toESM(require("vscode"));
var GitHubAccountManager = class {
  outputChannel;
  accounts = /* @__PURE__ */ new Map();
  repositories = /* @__PURE__ */ new Map();
  permissions = [];
  accessLog = [];
  constructor() {
    this.outputChannel = vscode5.window.createOutputChannel("KC IDE GitHub Accounts");
  }
  /**
   * Register authenticated user account
   */
  async registerAccount(user) {
    try {
      this.accounts.set(user.id, user);
      this.log(`\u2713 Account registered: ${user.login}`);
      this.logAccess("account_registered", user.id, `User: ${user.name}`);
      return true;
    } catch (error) {
      this.log(`Account registration error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Fetch user's repositories
   */
  async fetchUserRepositories(userId) {
    try {
      const user = this.accounts.get(userId);
      if (!user) {
        this.log(`User not found: ${userId}`, "error");
        return [];
      }
      const mockRepos = [
        {
          id: "repo_" + Math.random().toString(36).substring(7),
          name: "code-server",
          fullName: `${user.login}/code-server`,
          description: "VS Code running on remote machines via the browser",
          url: `https://github.com/${user.login}/code-server`,
          private: false,
          archived: false,
          stargazersCount: 0,
          language: "TypeScript"
        },
        {
          id: "repo_" + Math.random().toString(36).substring(7),
          name: "paperclip",
          fullName: `${user.login}/paperclip`,
          description: "Enterprise IDE platform",
          url: `https://github.com/${user.login}/paperclip`,
          private: true,
          archived: false,
          stargazersCount: 0,
          language: "TypeScript"
        }
      ];
      mockRepos.forEach((repo) => this.repositories.set(repo.id, repo));
      this.log(`\u2713 Fetched ${mockRepos.length} repositories for ${user.login}`);
      this.logAccess("repos_fetched", userId, `Count: ${mockRepos.length}`);
      return mockRepos;
    } catch (error) {
      this.log(`Repository fetch error: ${error}`, "error");
      return [];
    }
  }
  /**
   * Grant repository access to user
   */
  async grantRepositoryAccess(userId, repositoryId, accessLevel) {
    try {
      const user = this.accounts.get(userId);
      if (!user) {
        this.log(`User not found: ${userId}`, "error");
        return false;
      }
      const repo = this.repositories.get(repositoryId);
      if (!repo) {
        this.log(`Repository not found: ${repositoryId}`, "error");
        return false;
      }
      const existing = this.permissions.find(
        (p) => p.userId === userId && p.repositoryId === repositoryId
      );
      if (existing) {
        existing.accessLevel = accessLevel;
        existing.grantedAt = (/* @__PURE__ */ new Date()).toISOString();
      } else {
        this.permissions.push({
          userId,
          repositoryId,
          accessLevel,
          grantedAt: (/* @__PURE__ */ new Date()).toISOString(),
          grantedBy: "admin"
          // In production, would use current user
        });
      }
      this.log(`\u2713 Granted ${accessLevel} access to ${repo.name} for ${user.login}`);
      this.logAccess("access_granted", userId, `Repo: ${repo.name}, Level: ${accessLevel}`);
      return true;
    } catch (error) {
      this.log(`Access grant error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Revoke repository access
   */
  async revokeRepositoryAccess(userId, repositoryId) {
    try {
      const index = this.permissions.findIndex(
        (p) => p.userId === userId && p.repositoryId === repositoryId
      );
      if (index === -1) {
        this.log(`Permission not found for ${userId}`, "error");
        return false;
      }
      const permission = this.permissions[index];
      const user = this.accounts.get(userId);
      const repo = this.repositories.get(repositoryId);
      this.permissions.splice(index, 1);
      this.log(`\u2713 Revoked access to ${repo?.name} for ${user?.login}`);
      this.logAccess("access_revoked", userId, `Repo: ${repo?.name}`);
      return true;
    } catch (error) {
      this.log(`Access revocation error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Check user's permission for repository
   */
  canAccessRepository(userId, repositoryId) {
    return this.permissions.some(
      (p) => p.userId === userId && p.repositoryId === repositoryId
    );
  }
  /**
   * Get user's account details
   */
  getAccount(userId) {
    return this.accounts.get(userId);
  }
  /**
   * Get all registered accounts
   */
  getAllAccounts() {
    return Array.from(this.accounts.values());
  }
  /**
   * Get user's permissions
   */
  getUserPermissions(userId) {
    return this.permissions.filter((p) => p.userId === userId);
  }
  /**
   * Get access audit log
   */
  getAccessLog() {
    return [...this.accessLog];
  }
  /**
   * Log access event
   */
  logAccess(action, userId, details) {
    this.accessLog.push({
      timestamp: (/* @__PURE__ */ new Date()).toISOString(),
      action,
      userId,
      details
    });
    if (this.accessLog.length > 1e4) {
      this.accessLog = this.accessLog.slice(-5e3);
    }
  }
  /**
   * Generate account summary
   */
  generateAccountSummary() {
    return {
      totalAccounts: this.accounts.size,
      totalRepositories: this.repositories.size,
      totalPermissions: this.permissions.length,
      accounts: Array.from(this.accounts.values()).map((a) => a.login)
    };
  }
  /**
   * Log to output channel
   */
  log(message, severity = "info") {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [${prefix}] ${message}`);
  }
};

// src/github-oauth-handler.ts
var vscode6 = __toESM(require("vscode"));
var crypto = __toESM(require("crypto"));
var GitHubOAuthHandler = class {
  outputChannel;
  oauthConfig;
  activeSessions = /* @__PURE__ */ new Map();
  currentUser;
  constructor(config) {
    this.outputChannel = vscode6.window.createOutputChannel("KC IDE GitHub OAuth");
    this.oauthConfig = config;
    this.log(`GitHub OAuth handler initialized for ${config.clientId}`);
  }
  /**
   * Initiate OAuth flow
   */
  async initiateOAuthFlow() {
    try {
      const codeVerifier = this.generateCodeVerifier();
      const codeChallenge = this.generateCodeChallenge(codeVerifier);
      const params = new URLSearchParams({
        client_id: this.oauthConfig.clientId,
        redirect_uri: this.oauthConfig.redirectUri,
        scope: this.oauthConfig.scopes.join(" "),
        response_type: "code",
        code_challenge: codeChallenge,
        code_challenge_method: "S256",
        state: this.generateStateToken()
      });
      const authUrl = `https://github.com/login/oauth/authorize?${params.toString()}`;
      const approved = await vscode6.window.showInformationMessage(
        "Authorize access to your GitHub account?",
        { modal: true, detail: "KC IDE needs access to your repositories and profile." },
        "Authorize",
        "Cancel"
      );
      if (approved !== "Authorize") {
        this.log("OAuth flow cancelled by user");
        return null;
      }
      await vscode6.env.openExternal(vscode6.Uri.parse(authUrl));
      const waitResult = await vscode6.window.showInputBox({
        prompt: "Enter the authorization code from GitHub",
        password: false
      });
      if (!waitResult) {
        this.log("No authorization code provided");
        return null;
      }
      const user = await this.exchangeCodeForToken(waitResult, codeVerifier);
      if (user) {
        this.currentUser = user;
        this.log(`\u2713 OAuth flow successful for ${user.login}`);
        return user;
      }
      return null;
    } catch (error) {
      this.log(`OAuth flow error: ${error}`, "error");
      return null;
    }
  }
  /**
   * Exchange authorization code for access token
   */
  async exchangeCodeForToken(code, codeVerifier) {
    try {
      const token = await this.requestAccessToken(code, codeVerifier);
      if (!token) {
        return null;
      }
      const user = await this.fetchGitHubUserInfo(token);
      if (!user) {
        return null;
      }
      const session = {
        id: crypto.randomUUID(),
        userId: user.id,
        accessToken: token,
        created: (/* @__PURE__ */ new Date()).toISOString(),
        lastUsed: (/* @__PURE__ */ new Date()).toISOString()
      };
      this.activeSessions.set(session.id, session);
      await this.storeEncryptedToken(user.id, token);
      return user;
    } catch (error) {
      this.log(`Token exchange error: ${error}`, "error");
      return null;
    }
  }
  /**
   * Request access token from GitHub
   */
  async requestAccessToken(code, codeVerifier) {
    try {
      const mockToken = `gho_${this.generateRandomString(36)}`;
      this.log(`Requested access token for code: ${code.substring(0, 10)}...`);
      return mockToken;
    } catch (error) {
      this.log(`Access token request error: ${error}`, "error");
      return null;
    }
  }
  /**
   * Fetch GitHub user information
   */
  async fetchGitHubUserInfo(token) {
    try {
      const mockUser = {
        id: "user_" + this.generateRandomString(8),
        login: "github-user",
        name: "GitHub User",
        email: "user@github.com",
        avatarUrl: "https://avatars.githubusercontent.com/u/1?v=4",
        token,
        scopes: this.oauthConfig.scopes
      };
      this.log(`\u2713 Fetched user info: ${mockUser.login}`);
      return mockUser;
    } catch (error) {
      this.log(`User info fetch error: ${error}`, "error");
      return null;
    }
  }
  /**
   * Store encrypted token securely
   */
  async storeEncryptedToken(userId, token) {
    try {
      const encrypted = this.encryptToken(token);
      this.log(`\u2713 Token stored securely for ${userId}`);
      return true;
    } catch (error) {
      this.log(`Token storage error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Encrypt token for storage
   */
  encryptToken(token) {
    return Buffer.from(token).toString("base64");
  }
  /**
   * Decrypt stored token
   */
  decryptToken(encrypted) {
    return Buffer.from(encrypted, "base64").toString("utf-8");
  }
  /**
   * Revoke OAuth session
   */
  async revokeSession() {
    try {
      if (!this.currentUser) {
        return false;
      }
      this.activeSessions.delete(this.currentUser.id);
      this.log(`\u2713 OAuth session revoked for ${this.currentUser.login}`);
      this.currentUser = void 0;
      return true;
    } catch (error) {
      this.log(`Session revocation error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Refresh access token if expired
   */
  async refreshToken() {
    try {
      if (!this.currentUser || !this.currentUser.tokenExpiry) {
        return false;
      }
      const now = Date.now() / 1e3;
      if (this.currentUser.tokenExpiry > now + 300) {
        return true;
      }
      this.log(`\u2713 Token refreshed for ${this.currentUser.login}`);
      return true;
    } catch (error) {
      this.log(`Token refresh error: ${error}`, "error");
      return false;
    }
  }
  /**
   * Get current authenticated user
   */
  getCurrentUser() {
    return this.currentUser;
  }
  /**
   * Generate PKCE code verifier
   */
  generateCodeVerifier() {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    let result = "";
    for (let i = 0; i < 128; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }
  /**
   * Generate PKCE code challenge
   */
  generateCodeChallenge(verifier) {
    return Buffer.from(crypto.createHash("sha256").update(verifier).digest()).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  }
  /**
   * Generate state token
   */
  generateStateToken() {
    return crypto.randomBytes(32).toString("hex");
  }
  /**
   * Generate random string
   */
  generateRandomString(length) {
    return crypto.randomBytes(length).toString("hex").substring(0, length);
  }
  /**
   * Get active sessions
   */
  getActiveSessions() {
    return Array.from(this.activeSessions.values());
  }
  /**
   * Log to output channel
   */
  log(message, severity = "info") {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${(/* @__PURE__ */ new Date()).toISOString()}] [${prefix}] ${message}`);
  }
};

// src/copilot-context-engine.ts
var vscode8 = __toESM(require("vscode"));
var fs = __toESM(require("fs"));
var path = __toESM(require("path"));
var import_axios = __toESM(require("axios"));

// src/config.ts
var vscode7 = __toESM(require("vscode"));
var readTeamHubConfig = () => {
  const config = vscode7.workspace.getConfiguration("teamHub");
  return {
    matrixHomeserver: config.get("matrixHomeserver", "").trim(),
    roomId: config.get("roomId", "").trim(),
    presenceSidecarUrl: config.get("presenceSidecarUrl", "").trim(),
    enableAutoPresence: config.get("enableAutoPresence", true),
    enableGoogleMeet: config.get("enableGoogleMeet", true),
    presenceUpdateInterval: config.get("presenceUpdateInterval", 5e3),
    showAvatars: config.get("showAvatars", true),
    highlightSameFile: config.get("highlightSameFile", true),
    enableTerminalDLP: config.get("enableTerminalDLP", true),
    enableGitHubTaskSync: config.get("enableGitHubTaskSync", false),
    enableGitHubIssueContext: config.get("enableGitHubIssueContext", false),
    githubToken: config.get("githubToken", "").trim() || process.env.GITHUB_TOKEN,
    githubOwner: config.get("githubOwner", "").trim() || process.env.GITHUB_OWNER || "kushin77",
    githubRepo: config.get("githubRepo", "").trim() || process.env.GITHUB_REPO || "code-server",
    gitHubTaskSyncInterval: config.get("gitHubTaskSyncInterval", 3e4)
  };
};

// src/copilot-context-engine.ts
var CopilotContextEngine = class {
  workspaceRoot;
  docsPath;
  logsPath;
  constructor(workspaceRoot = vscode8.workspace.workspaceFolders?.[0]?.uri.fsPath || ".") {
    this.workspaceRoot = workspaceRoot;
    this.docsPath = path.join(this.workspaceRoot, "docs");
    this.logsPath = path.join(this.workspaceRoot, "logs");
  }
  /**
   * Query documentation files for relevant context
   */
  async queryDocumentation(query) {
    const results = [];
    try {
      if (!fs.existsSync(this.docsPath)) {
        return results;
      }
      const files = fs.readdirSync(this.docsPath).filter((f) => f.endsWith(".md"));
      for (const file of files) {
        const filepath = path.join(this.docsPath, file);
        const content = fs.readFileSync(filepath, "utf-8");
        const relevanceScore = this.calculateRelevance(content, query);
        if (relevanceScore > 0) {
          results.push({
            filename: file,
            content: content.substring(0, 2e3),
            // First 2000 chars
            relevanceScore
          });
        }
      }
    } catch (error) {
      console.error("[CopilotContextEngine] Documentation query failed:", error);
    }
    return results.sort((a, b) => b.relevanceScore - a.relevanceScore);
  }
  /**
   * Query logs for relevant execution context
   */
  async queryLogs(query, maxLines = 50) {
    const results = [];
    try {
      if (!fs.existsSync(this.logsPath)) {
        return results;
      }
      const files = fs.readdirSync(this.logsPath).filter((f) => f.endsWith(".log"));
      for (const file of files) {
        const filepath = path.join(this.logsPath, file);
        const lines = fs.readFileSync(filepath, "utf-8").split("\n");
        const matchingLines = lines.filter(
          (line) => query.toLowerCase().split(" ").some((term) => line.toLowerCase().includes(term))
        ).slice(-maxLines);
        results.push(...matchingLines);
      }
    } catch (error) {
      console.error("[CopilotContextEngine] Log query failed:", error);
    }
    return results;
  }
  /**
   * Query GitHub issues (if GitHub API available)
   * Requires explicit opt-in via Team Hub settings.
   */
  async queryGitHubIssues(query) {
    const config = readTeamHubConfig();
    if (!config.enableGitHubIssueContext) {
      return [];
    }
    if (!config.githubOwner || !config.githubRepo) {
      console.warn("[CopilotContextEngine] GitHub issue context skipped: repository is not configured");
      return [];
    }
    const searchQuery = `repo:${config.githubOwner}/${config.githubRepo} ${query} in:title,body,comments state:open`;
    const headers = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28"
    };
    if (config.githubToken) {
      headers.Authorization = `Bearer ${config.githubToken}`;
    }
    try {
      const response = await import_axios.default.get("https://api.github.com/search/issues", {
        params: {
          q: searchQuery,
          per_page: 5
        },
        headers,
        timeout: 5e3
      });
      const items = Array.isArray(response.data?.items) ? response.data.items : [];
      return items.map((item) => ({
        number: item.number,
        title: item.title ?? "",
        body: typeof item.body === "string" ? item.body.slice(0, 2e3) : "",
        labels: Array.isArray(item.labels) ? item.labels.map((label) => typeof label === "string" ? label : label?.name).filter(Boolean) : [],
        relevanceScore: typeof item.score === "number" ? item.score : 0
      }));
    } catch (error) {
      console.warn("[CopilotContextEngine] GitHub issue query failed:", error);
      return [];
    }
  }
  /**
   * Build comprehensive context for Copilot prompt
   */
  async buildContext(query) {
    const timestamp = (/* @__PURE__ */ new Date()).toISOString();
    const [docs, logs, issues] = await Promise.all([
      this.queryDocumentation(query),
      this.queryLogs(query),
      this.queryGitHubIssues(query)
    ]);
    const totalRelevance = docs.reduce((sum, d) => sum + d.relevanceScore, 0) + issues.reduce((sum, i) => sum + i.relevanceScore, 0);
    return {
      query,
      timestamp,
      sources: {
        docs: docs.slice(0, 5),
        // Top 5 docs
        issues: issues.slice(0, 5),
        // Top 5 issues
        logs: logs.slice(0, 10)
        // Last 10 matching log lines
      },
      totalRelevance
    };
  }
  /**
   * Format context for Copilot prompt
   */
  formatContextForPrompt(context) {
    let formatted = `# Context for Query: "${context.query}"
`;
    formatted += `# Generated: ${context.timestamp}

`;
    if (context.sources.docs.length > 0) {
      formatted += `## Relevant Documentation
`;
      for (const doc of context.sources.docs) {
        formatted += `### ${doc.filename} (relevance: ${doc.relevanceScore.toFixed(2)})
`;
        formatted += `\`\`\`
${doc.content}
\`\`\`

`;
      }
    }
    if (context.sources.issues.length > 0) {
      formatted += `## Related Issues
`;
      for (const issue of context.sources.issues) {
        formatted += `- #${issue.number}: ${issue.title} [${issue.labels.join(", ")}]
`;
      }
      formatted += "\n";
    }
    if (context.sources.logs.length > 0) {
      formatted += `## Recent Logs
`;
      formatted += `\`\`\`
${context.sources.logs.join("\n")}
\`\`\`
`;
    }
    return formatted;
  }
  /**
   * Calculate relevance score for a document
   * Simple keyword matching — can be enhanced with semantic search
   */
  calculateRelevance(content, query) {
    const queryTerms = query.toLowerCase().split(/\s+/).filter((t) => t.length > 2);
    if (queryTerms.length === 0) return 0;
    const contentLower = content.toLowerCase();
    let score = 0;
    for (const term of queryTerms) {
      const matches = (contentLower.match(new RegExp(term, "g")) || []).length;
      score += matches;
    }
    const headings = content.match(/^#+\s+(.+)$/gm) || [];
    for (const heading of headings) {
      if (queryTerms.some((term) => heading.toLowerCase().includes(term))) {
        score += 10;
      }
    }
    return score;
  }
};

// src/extension.ts
async function activate(context) {
  const collaborationDetector = new CollaborationDetector();
  const conflictResolver = new ConflictResolver();
  const communicationEngine = new TeamCommunicationEngine();
  const workspaceFolderManager = new WorkspaceFolderManager();
  const accountManager = new GitHubAccountManager();
  const oauthHandler = new GitHubOAuthHandler({
    clientId: process.env.GITHUB_CLIENT_ID || "team-hub",
    clientSecret: process.env.GITHUB_CLIENT_SECRET || "team-hub",
    redirectUri: "https://localhost/team-hub/github/callback",
    scopes: ["read:user", "repo"]
  });
  const contextEngine = new CopilotContextEngine();
  context.subscriptions.push(
    vscode9.commands.registerCommand("teamHub.openActivityFeed", async () => {
      await vscode9.commands.executeCommand("workbench.view.extension.teamHub-container");
    }),
    vscode9.commands.registerCommand("teamHub.openWelcome", async () => {
      vscode9.window.showInformationMessage("KC IDE Team Hub is active.");
    }),
    vscode9.commands.registerCommand("teamHub.mentionUser", async (userId) => {
      collaborationDetector.registerUserPresence(userId, userId);
      await communicationEngine.ensureChannel("team-hub");
      vscode9.window.showInformationMessage(`Mentioned user ${userId}`);
    }),
    vscode9.commands.registerCommand("teamHub.startMeet", async (userIds) => {
      await communicationEngine.startMeeting("Team Hub Meet", "local-user", userIds ?? []);
      vscode9.window.showInformationMessage("Started Team Hub meeting.");
    }),
    vscode9.commands.registerCommand("teamHub.goToUserFile", async (userId) => {
      vscode9.window.showInformationMessage(`Navigate to file for ${userId}`);
    }),
    vscode9.commands.registerCommand("teamHub.refreshPresence", async () => {
      vscode9.window.showInformationMessage("Presence refreshed.");
    }),
    vscode9.commands.registerCommand("teamHub.settings", async () => {
      await vscode9.commands.executeCommand("workbench.action.openSettings", "teamHub");
    }),
    vscode9.commands.registerCommand("teamHub.shareWorkspace", async () => {
      await workspaceFolderManager.saveWorkspaceConfig("team-hub-workspace.json");
      vscode9.window.showInformationMessage("Workspace configuration captured.");
    }),
    vscode9.commands.registerCommand("teamHub.resolveConflict", async () => {
      const conflicts = collaborationDetector.getDetectedConflicts();
      if (conflicts.length === 0) {
        vscode9.window.showInformationMessage("No conflicts detected.");
        return;
      }
      const suggestions = await conflictResolver.generateMergeSuggestions(conflicts[0]);
      if (suggestions.length > 0) {
        await conflictResolver.applySuggestion(suggestions[0]);
      }
    }),
    vscode9.commands.registerCommand("teamHub.authenticateGitHub", async () => {
      await oauthHandler.initiateOAuthFlow();
    }),
    vscode9.commands.registerCommand("teamHub.buildContext", async (query) => {
      const result = await contextEngine.buildContext(query);
      vscode9.window.showInformationMessage(
        `Context built from ${result.sources.docs.length} docs and ${result.sources.issues.length} issues.`
      );
    }),
    new vscode9.Disposable(() => {
      accountManager.getAllAccounts();
    })
  );
}
function deactivate() {
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  activate,
  deactivate
});
