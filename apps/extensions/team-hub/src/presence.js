import * as vscode from 'vscode';
import { buildTeamHubSnapshot, createDefaultCurrentUser, createDemoUsers } from './presence-model';
export const resolveCurrentFile = (editor) => {
    if (!editor) {
        return undefined;
    }
    return vscode.workspace.asRelativePath(editor.document.uri, false);
};
const FUNCTION_PATTERNS = [
    /^(?:export\s+)?(?:async\s+)?function\s+([A-Za-z0-9_$]+)/,
    /^(?:export\s+)?(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:async\s*)?\(/,
    /^(?:public\s+|private\s+|protected\s+)?(?:async\s+)?([A-Za-z0-9_$]+)\s*\([^)]*\)\s*\{/,
    /^(?:export\s+)?class\s+([A-Za-z0-9_$]+)/
];
export const resolveCurrentFunction = (editor) => {
    if (!editor) {
        return undefined;
    }
    const { document } = editor;
    const currentLine = editor.selection.active.line;
    const searchStart = Math.max(0, currentLine - 40);
    for (let lineIndex = currentLine; lineIndex >= searchStart; lineIndex -= 1) {
        const lineText = document.lineAt(lineIndex).text.trim();
        if (!lineText || lineText.startsWith('//') || lineText.startsWith('*')) {
            continue;
        }
        for (const pattern of FUNCTION_PATTERNS) {
            const match = lineText.match(pattern);
            if (match?.[1]) {
                return match[1];
            }
        }
    }
    return undefined;
};
const assignDefined = (target, source) => {
    Object.entries(source).forEach(([key, value]) => {
        if (value !== undefined) {
            target[key] = value;
        }
    });
};
export class PresenceService {
    constructor(getConfig) {
        this.getConfig = getConfig;
        this.changeEmitter = new vscode.EventEmitter();
        this.currentUser = createDefaultCurrentUser();
        this.users = createDemoUsers();
        this.onDidChangeSnapshot = this.changeEmitter.event;
    }
    dispose() {
        if (this.pollHandle) {
            clearInterval(this.pollHandle);
            this.pollHandle = undefined;
        }
        this.changeEmitter.dispose();
    }
    async connect() {
        await this.refresh();
        const intervalMs = this.getConfig().presenceUpdateInterval;
        this.pollHandle = setInterval(() => {
            void this.refresh();
        }, intervalMs);
    }
    async refresh() {
        const remoteSnapshot = await this.tryLoadRemoteSnapshot();
        if (remoteSnapshot) {
            this.users = remoteSnapshot.users.map((user) => ({ ...user }));
            if (remoteSnapshot.currentFile !== undefined) {
                this.currentFile = remoteSnapshot.currentFile;
            }
            assignDefined(this.currentUser, remoteSnapshot.currentUser);
            this.currentUser.lastSeen = Date.now();
            this.emit();
            return;
        }
        this.emit();
    }
    updateActiveEditor(editor) {
        this.currentFile = resolveCurrentFile(editor);
        this.currentUser.currentFile = this.currentFile;
        this.currentUser.currentLine = editor ? editor.selection.active.line + 1 : undefined;
        this.currentUser.currentFunction = resolveCurrentFunction(editor);
        this.currentUser.lastSeen = Date.now();
        this.currentUser.status = this.currentFile ? 'online' : 'away';
        this.emit();
    }
    getSnapshot() {
        return buildTeamHubSnapshot(this.currentUser, this.users, this.currentFile);
    }
    findUser(userId) {
        if (this.currentUser.id === userId) {
            return { ...this.currentUser };
        }
        return this.users.find((user) => user.id === userId);
    }
    findUsers(userIds) {
        return userIds
            .map((userId) => this.findUser(userId))
            .filter((user) => Boolean(user));
    }
    getCurrentFile() {
        return this.currentFile;
    }
    emit() {
        this.changeEmitter.fire(this.getSnapshot());
    }
    async tryLoadRemoteSnapshot() {
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
            const data = await response.json();
            if (!Array.isArray(data.users)) {
                return undefined;
            }
            const currentUser = {
                ...createDefaultCurrentUser(),
                ...(data.currentUser ?? {})
            };
            return buildTeamHubSnapshot(currentUser, data.users, data.currentFile);
        }
        catch {
            return undefined;
        }
    }
    normalizeSidecarUrl(rawUrl, path) {
        try {
            const parsed = new URL(rawUrl);
            if (parsed.protocol === 'ws:') {
                parsed.protocol = 'http:';
            }
            else if (parsed.protocol === 'wss:') {
                parsed.protocol = 'https:';
            }
            parsed.pathname = path;
            parsed.search = '';
            parsed.hash = '';
            return parsed;
        }
        catch {
            return undefined;
        }
    }
}
//# sourceMappingURL=presence.js.map