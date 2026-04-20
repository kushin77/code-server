import * as vscode from 'vscode';
import type { TeamHubConfig, TeamHubSnapshot, TeamHubUser } from './types';
import { buildTeamHubSnapshot, createDefaultCurrentUser, createDemoUsers } from './presence-model';

export const resolveCurrentFile = (editor: vscode.TextEditor | undefined): string | undefined => {
  if (!editor) {
    return undefined;
  }

  return vscode.workspace.asRelativePath(editor.document.uri, false);
};

export class PresenceService {
  private readonly changeEmitter = new vscode.EventEmitter<TeamHubSnapshot>();
  private readonly currentUser: TeamHubUser = createDefaultCurrentUser();
  private users: TeamHubUser[] = createDemoUsers();
  private currentFile: string | undefined;
  private pollHandle: NodeJS.Timeout | undefined;

  public readonly onDidChangeSnapshot = this.changeEmitter.event;

  constructor(private readonly getConfig: () => TeamHubConfig) {}

  dispose(): void {
    if (this.pollHandle) {
      clearInterval(this.pollHandle);
      this.pollHandle = undefined;
    }

    this.changeEmitter.dispose();
  }

  async connect(): Promise<void> {
    await this.refresh();

    const intervalMs = this.getConfig().presenceUpdateInterval;
    this.pollHandle = setInterval(() => {
      void this.refresh();
    }, intervalMs);
  }

  async refresh(): Promise<void> {
    const remoteSnapshot = await this.tryLoadRemoteSnapshot();

    if (remoteSnapshot) {
      this.users = remoteSnapshot.users;
      this.currentFile = remoteSnapshot.currentFile;
      this.currentUser.status = remoteSnapshot.currentUser.status;
      this.currentUser.currentFile = remoteSnapshot.currentUser.currentFile;
      this.currentUser.currentLine = remoteSnapshot.currentUser.currentLine;
      this.currentUser.lastSeen = Date.now();
      this.emit();
      return;
    }

    this.emit();
  }

  updateActiveEditor(editor: vscode.TextEditor | undefined): void {
    this.currentFile = resolveCurrentFile(editor);
    this.currentUser.currentFile = this.currentFile;
    this.currentUser.currentLine = editor ? editor.selection.active.line + 1 : undefined;
    this.currentUser.lastSeen = Date.now();
    this.currentUser.status = this.currentFile ? 'online' : 'away';
    this.emit();
  }

  getSnapshot(): TeamHubSnapshot {
    return buildTeamHubSnapshot(this.currentUser, this.users, this.currentFile);
  }

  findUser(userId: string): TeamHubUser | undefined {
    if (this.currentUser.id === userId) {
      return { ...this.currentUser };
    }

    return this.users.find((user) => user.id === userId);
  }

  findUsers(userIds: string[]): TeamHubUser[] {
    return userIds
      .map((userId) => this.findUser(userId))
      .filter((user): user is TeamHubUser => Boolean(user));
  }

  getCurrentFile(): string | undefined {
    return this.currentFile;
  }

  private emit(): void {
    this.changeEmitter.fire(this.getSnapshot());
  }

  private async tryLoadRemoteSnapshot(): Promise<TeamHubSnapshot | undefined> {
    const rawUrl = this.getConfig().presenceSidecarUrl;
    if (!rawUrl) {
      return undefined;
    }

    const snapshotUrl = this.normalizeSidecarUrl(rawUrl, '/snapshot');
    if (!snapshotUrl) {
      return undefined;
    }

    try {
      const response = await fetch(snapshotUrl.toString(), {
        headers: {
          accept: 'application/json'
        }
      });

      if (!response.ok) {
        return undefined;
      }

      const data = await response.json() as Partial<TeamHubSnapshot> & { users?: TeamHubUser[] };
      if (!Array.isArray(data.users)) {
        return undefined;
      }

      const currentUser = data.currentUser ?? createDefaultCurrentUser();
      return buildTeamHubSnapshot(currentUser, data.users, data.currentFile);
    } catch {
      return undefined;
    }
  }

  private normalizeSidecarUrl(rawUrl: string, path: string): URL | undefined {
    try {
      const parsed = new URL(rawUrl);
      if (parsed.protocol === 'ws:') {
        parsed.protocol = 'http:';
      } else if (parsed.protocol === 'wss:') {
        parsed.protocol = 'https:';
      }

      parsed.pathname = path;
      parsed.search = '';
      parsed.hash = '';
      return parsed;
    } catch {
      return undefined;
    }
  }
}
