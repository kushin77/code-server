// @file apps/extensions/statusbar-tiles/src/tile-manager.ts
// @module ide/vscode-extensions
// @description Configuration management and tile caching for performance

import * as vscode from "vscode";
import { StatusBarTile } from "./status-bar-tile";

interface CacheEntry<T> {
  value: T;
  timestamp: number;
}

export class StatusTileManager {
  private cache: Map<string, CacheEntry<any>> = new Map();
  private cacheTTL: number = 60000; // 60 seconds
  private tile: StatusBarTile;
  private configListener: vscode.Disposable | null = null;

  constructor(tile: StatusBarTile) {
    this.tile = tile;
    this.setupConfigListener();
  }

  private setupConfigListener() {
    this.configListener = vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('statusbar-tiles')) {
        console.log('Status bar tiles configuration changed');
        this.clearCache();
        // Re-initialize tiles with new config
        this.tile.refresh();
      }
    });
  }

  get<T>(key: string): T | null {
    const entry = this.cache.get(key);
    if (!entry) return null;

    const now = Date.now();
    if (now - entry.timestamp > this.cacheTTL) {
      this.cache.delete(key);
      return null;
    }

    return entry.value as T;
  }

  set<T>(key: string, value: T): void {
    this.cache.set(key, {
      value,
      timestamp: Date.now()
    });
  }

  clearCache(): void {
    this.cache.clear();
    console.log('Cache cleared');
  }

  getConfig(section: string, key: string, defaultValue: any = null) {
    return vscode.workspace
      .getConfiguration(section)
      .get(key, defaultValue);
  }

  setConfig(section: string, key: string, value: any, global: boolean = true) {
    const config = vscode.workspace.getConfiguration(section);
    return config.update(
      key,
      value,
      global ? vscode.ConfigurationTarget.Global : vscode.ConfigurationTarget.Workspace
    );
  }

  dispose(): void {
    if (this.configListener) {
      this.configListener.dispose();
    }
    this.clearCache();
  }
}

export class TileConfiguration {
  static loadTileOrder(): string[] {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<string[]>('tileOrder', ['pr', 'ci', 'incidents', 'team-online']);
  }

  static setTileOrder(order: string[]): Thenable<void> {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .update('tileOrder', order);
  }

  static getRefreshInterval(): number {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<number>('refreshInterval', 60);
  }

  static setRefreshInterval(seconds: number): Thenable<void> {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .update('refreshInterval', Math.max(10, seconds));
  }

  static getGitHubToken(): string {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<string>('githubToken', '');
  }

  static setGitHubToken(token: string): Thenable<void> {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .update('githubToken', token, vscode.ConfigurationTarget.Global);
  }

  static getCIEndpoint(): string {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<string>('ciEndpoint', 'http://localhost:8080');
  }

  static getPagerDutyToken(): string {
    return vscode.workspace
      .getConfiguration('statusbar-tiles')
      .get<string>('pagerdutyToken', '');
  }
}
