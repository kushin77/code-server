// @file apps/extensions/shared-clipboard/src/clipboard-manager.ts
// @module ide/shared-clipboard
// @description P3-1080 Phase 3b: Clipboard state management
// @governance GOV-002: All clipboard operations immutable and audited

import * as vscode from 'vscode';
import axios from 'axios';

export interface ClipboardEntry {
    id: string;
    content: string;
    timestamp: string;
    fileName?: string;
    language?: string;
    tags: string[];
    shared: boolean;
}

export interface AddEntryRequest {
    content: string;
    fileName?: string;
    language?: string;
    tags?: string[];
}

export class ClipboardManager {
    private dbPath: string;
    private apiClient: axios.AxiosInstance;
    private config: any;
    private cache: Map<string, ClipboardEntry> = new Map();
    private cacheTimeout: NodeJS.Timeout | null = null;
    
    constructor(dbPath: string) {
        this.dbPath = dbPath;
        this.apiClient = axios.create({
            baseURL: 'http://localhost:8000',
            timeout: 5000
        });
        this.loadConfig();
    }
    
    private loadConfig() {
        const config = vscode.workspace.getConfiguration('sharedClipboard');
        this.config = {
            enabled: config.get('enabled', true),
            historySize: config.get('historySize', 100),
            autoRecord: config.get('autoRecord', true),
            syncInterval: config.get('syncInterval', 5)
        };
    }
    
    async addEntry(request: AddEntryRequest): Promise<string> {
        try {
            const userId = await this.getCurrentUserId();
            
            const response = await this.apiClient.post('/clipboard/add', {
                content: request.content,
                userId,
                fileName: request.fileName,
                language: request.language,
                tags: request.tags || []
            });
            
            const clipId = response.data.clipId;
            this.invalidateCache();
            
            return clipId;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to add entry:', err);
            throw err;
        }
    }
    
    async getEntries(
        limit: number = 50,
        offset: number = 0,
        tags?: string[]
    ): Promise<ClipboardEntry[]> {
        try {
            const userId = await this.getCurrentUserId();
            
            const response = await this.apiClient.get('/clipboard/entries', {
                params: {
                    userId,
                    limit,
                    offset,
                    tags: tags ? tags.join(',') : undefined
                }
            });
            
            return response.data.entries || [];
        } catch (err) {
            console.error('[Shared Clipboard] Failed to get entries:', err);
            throw err;
        }
    }
    
    async getEntryById(clipId: string): Promise<ClipboardEntry | null> {
        // Check cache first
        if (this.cache.has(clipId)) {
            return this.cache.get(clipId) || null;
        }
        
        try {
            const response = await this.apiClient.get(`/clipboard/${clipId}`);
            const entry = response.data.entry as ClipboardEntry;
            this.cache.set(clipId, entry);
            return entry;
        } catch (err) {
            console.error(`[Shared Clipboard] Failed to get entry ${clipId}:`, err);
            return null;
        }
    }
    
    async search(query: string, limit: number = 50): Promise<ClipboardEntry[]> {
        try {
            const response = await this.apiClient.get('/clipboard/search', {
                params: { q: query, limit }
            });
            
            return response.data.results || [];
        } catch (err) {
            console.error('[Shared Clipboard] Search failed:', err);
            throw err;
        }
    }
    
    async shareEntry(clipId: string, userIds: string[]): Promise<boolean> {
        try {
            await this.apiClient.post(`/clipboard/${clipId}/share`, {
                sharedWith: userIds
            });
            
            this.invalidateCache();
            return true;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to share entry:', err);
            throw err;
        }
    }
    
    async deleteEntry(clipId: string): Promise<boolean> {
        try {
            await this.apiClient.delete(`/clipboard/${clipId}`);
            this.cache.delete(clipId);
            this.invalidateCache();
            return true;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to delete entry:', err);
            throw err;
        }
    }
    
    async addTags(clipId: string, tags: string[]): Promise<boolean> {
        try {
            await this.apiClient.post(`/clipboard/${clipId}/tags`, { tags });
            this.cache.delete(clipId);
            return true;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to add tags:', err);
            throw err;
        }
    }
    
    async clearHistory(): Promise<boolean> {
        try {
            const userId = await this.getCurrentUserId();
            await this.apiClient.post('/clipboard/clear', { userId });
            this.cache.clear();
            this.invalidateCache();
            return true;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to clear history:', err);
            throw err;
        }
    }
    
    async getEntryCount(): Promise<number> {
        try {
            const userId = await this.getCurrentUserId();
            const response = await this.apiClient.get('/clipboard/count', {
                params: { userId }
            });
            return response.data.count || 0;
        } catch (err) {
            console.error('[Shared Clipboard] Failed to get count:', err);
            return 0;
        }
    }
    
    async getAuditLog(clipId: string): Promise<any[]> {
        try {
            const response = await this.apiClient.get(`/clipboard/${clipId}/audit`);
            return response.data.events || [];
        } catch (err) {
            console.error('[Shared Clipboard] Failed to get audit log:', err);
            return [];
        }
    }
    
    reloadConfig() {
        this.loadConfig();
        console.log('[Shared Clipboard] Config reloaded');
    }
    
    private async getCurrentUserId(): Promise<string> {
        // In production, would get from GitHub Auth context
        return vscode.env.machineId;
    }
    
    private invalidateCache() {
        if (this.cacheTimeout) {
            clearTimeout(this.cacheTimeout);
        }
        this.cacheTimeout = setTimeout(() => {
            this.cache.clear();
        }, this.config.syncInterval * 1000);
    }
    
    dispose() {
        if (this.cacheTimeout) {
            clearTimeout(this.cacheTimeout);
        }
    }
}
