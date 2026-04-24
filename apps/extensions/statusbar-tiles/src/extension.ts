// @file apps/extensions/statusbar-tiles/src/extension.ts
// @module ide/vscode-extensions
// @description P3-1055 Phase 3: VS Code extension main entry point with tile rendering
// @governance GOV-002: All user interactions logged and tracked

import * as vscode from "vscode";
import { StatusTileManager } from "./tile-manager";
import { StatusBarTile } from "./status-bar-tile";

export async function activate(context: vscode.ExtensionContext) {
  console.log('Status Bar Tiles extension activated');

  const manager = new StatusBarTile(context);
  await manager.initialize();

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('statusbar-tiles.refreshTiles', () => {
      console.log('Manually refreshing tiles');
      manager.refresh();
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('statusbar-tiles.openSettings', () => {
      vscode.commands.executeCommand('workbench.action.openSettings', 'statusbar-tiles');
    })
  );
}

export function deactivate() {
  console.log('Status Bar Tiles extension deactivated');
}
