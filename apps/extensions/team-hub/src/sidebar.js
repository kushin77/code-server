import { renderTeamHubWebviewHtml } from './webview';
export class TeamHubSidebarProvider {
    constructor(extensionUri, presenceService, actions, getConfig) {
        this.extensionUri = extensionUri;
        this.presenceService = presenceService;
        this.actions = actions;
        this.getConfig = getConfig;
        this.presenceService.onDidChangeSnapshot((snapshot) => {
            this.lastSnapshot = snapshot;
            this.render();
        });
    }
    resolveWebviewView(webviewView) {
        this.view = webviewView;
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this.extensionUri]
        };
        webviewView.webview.onDidReceiveMessage(async (message) => {
            switch (message.action) {
                case 'mention':
                    if (typeof message.userId === 'string') {
                        await this.actions.mentionUser(message.userId);
                    }
                    break;
                case 'start-meet':
                    await this.actions.startMeet();
                    break;
                case 'share-workspace':
                    await this.actions.shareWorkspace();
                    break;
                case 'focus-file':
                    if (typeof message.userId === 'string') {
                        await this.actions.goToUserFile(message.userId);
                    }
                    break;
                case 'refresh':
                    await this.actions.refreshPresence();
                    break;
                case 'settings':
                    this.actions.openSettings();
                    break;
            }
        });
        this.render();
    }
    render() {
        if (!this.view) {
            return;
        }
        const snapshot = this.lastSnapshot ?? this.presenceService.getSnapshot();
        this.view.webview.html = renderTeamHubWebviewHtml(snapshot, this.getConfig(), this.view.webview);
    }
}
//# sourceMappingURL=sidebar.js.map