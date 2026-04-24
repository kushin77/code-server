/**
 * Workspace profile management utilities
 */
const PROJECT_DETECTION_RULES = [
    {
        projectType: 'node',
        markers: ['package.json', 'pnpm-lock.yaml', 'package-lock.json', 'yarn.lock', 'bun.lockb'],
        recommendedSettings: {
            '[typescript]': {
                'editor.defaultFormatter': 'dbaeumer.vscode-eslint',
                'editor.formatOnSave': true,
            },
            'typescript.tsdk': 'node_modules/typescript/lib',
            'typescript.enablePromptUseWorkspaceTsdk': true,
        },
        recommendedExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss', 'ms-vscode.vscode-typescript-next'],
        recommendedDebugger: {
            name: 'Node app',
            type: 'pwa-node',
            request: 'launch',
            cwd: '.',
            program: 'src/index.ts',
            runtimeExecutable: 'node',
            args: ['--enable-source-maps'],
        },
        recommendedLinters: ['eslint'],
        summary: 'Detected a Node/TypeScript project from package manager metadata.',
    },
    {
        projectType: 'go',
        markers: ['go.mod', 'go.sum'],
        recommendedSettings: {
            '[go]': {
                'editor.formatOnSave': true,
                'editor.codeActionsOnSave': {
                    'source.organizeImports': true,
                },
            },
        },
        recommendedExtensions: ['golang.go'],
        recommendedDebugger: {
            name: 'Go service',
            type: 'go',
            request: 'launch',
            cwd: '.',
            program: 'main.go',
            runtimeExecutable: 'go',
        },
        recommendedLinters: ['golangci-lint'],
        summary: 'Detected a Go project from module metadata.',
    },
    {
        projectType: 'python',
        markers: ['pyproject.toml', 'requirements.txt', 'poetry.lock', 'setup.py'],
        recommendedSettings: {
            'python.linting.enabled': true,
            'python.linting.pylintEnabled': true,
            '[python]': {
                'editor.defaultFormatter': 'ms-python.python',
                'editor.formatOnSave': true,
            },
        },
        recommendedExtensions: ['ms-python.python', 'ms-python.vscode-pylance'],
        recommendedDebugger: {
            name: 'Python app',
            type: 'python',
            request: 'launch',
            cwd: '.',
            program: 'app.py',
            runtimeExecutable: 'python',
        },
        recommendedLinters: ['ruff', 'pylint'],
        summary: 'Detected a Python project from packaging metadata.',
    },
    {
        projectType: 'rust',
        markers: ['Cargo.toml', 'Cargo.lock'],
        recommendedSettings: {
            '[rust]': {
                'editor.formatOnSave': true,
                'editor.defaultFormatter': 'rust-lang.rust-analyzer',
            },
        },
        recommendedExtensions: ['rust-lang.rust-analyzer'],
        recommendedDebugger: {
            name: 'Rust binary',
            type: 'lldb',
            request: 'launch',
            cwd: '.',
            program: 'target/debug/app',
            runtimeExecutable: 'cargo',
        },
        recommendedLinters: ['cargo clippy'],
        summary: 'Detected a Rust workspace from Cargo metadata.',
    },
    {
        projectType: 'java',
        markers: ['pom.xml', 'build.gradle', 'build.gradle.kts'],
        recommendedSettings: {
            '[java]': {
                'editor.formatOnSave': true,
            },
        },
        recommendedExtensions: ['redhat.java'],
        recommendedDebugger: {
            name: 'Java service',
            type: 'java',
            request: 'launch',
            cwd: '.',
            program: 'src/main/java/Main.java',
            runtimeExecutable: 'java',
        },
        recommendedLinters: ['checkstyle'],
        summary: 'Detected a Java project from build metadata.',
    },
    {
        projectType: 'docs',
        markers: ['mkdocs.yml', 'docs/scripts/preview.ts', 'README.md'],
        recommendedSettings: {
            '[markdown]': {
                'editor.wordWrap': 'on',
                'editor.quickSuggestions': {
                    comments: 'off',
                    strings: 'off',
                    other: 'off',
                },
            },
            'markdown.preview.breaks': true,
        },
        recommendedExtensions: ['yzhang.markdown-all-in-one', 'bierner.markdown-mermaid'],
        recommendedDebugger: {
            name: 'Docs preview',
            type: 'pwa-node',
            request: 'launch',
            cwd: 'docs',
            program: 'docs/scripts/preview.ts',
            runtimeExecutable: 'node',
        },
        recommendedLinters: ['markdownlint'],
        summary: 'Detected documentation-heavy workspace markers.',
    },
];
const normalizeMarker = (value) => value.replace(/\\/g, '/').toLowerCase();
const extractBasename = (value) => normalizeMarker(value).split('/').pop() ?? normalizeMarker(value);
function findProjectDetectionRule(fileNames) {
    const normalizedMarkers = fileNames.map((fileName) => normalizeMarker(fileName));
    for (const rule of PROJECT_DETECTION_RULES) {
        const matchedMarkers = rule.markers.filter((marker) => {
            const normalizedMarker = normalizeMarker(marker);
            return normalizedMarkers.some((fileName) => fileName.endsWith(normalizedMarker) || extractBasename(fileName) === normalizedMarker);
        });
        if (matchedMarkers.length > 0) {
            return {
                ...rule,
                markers: matchedMarkers,
            };
        }
    }
    return undefined;
}
export function detectWorkspaceProjectType(fileNames) {
    return findProjectDetectionRule(fileNames)?.projectType ?? 'unknown';
}
export function buildWorkspaceAutoConfigSuggestion(fileNames) {
    const rule = findProjectDetectionRule(fileNames);
    if (!rule) {
        return undefined;
    }
    return {
        projectType: rule.projectType,
        detectedFrom: rule.markers,
        recommendedSettings: { ...rule.recommendedSettings },
        recommendedExtensions: [...rule.recommendedExtensions],
        recommendedDebugger: { ...rule.recommendedDebugger },
        recommendedLinters: [...rule.recommendedLinters],
        summary: rule.summary,
    };
}
const WORKSPACE_PROFILE_MANIFESTS = {
    'portal-main': {
        id: 'portal-main',
        name: 'Portal main',
        workspaceLabel: 'Portal main',
        description: 'Primary repo surface for the portal and RBAC dashboard.',
        root: 'apps/frontend',
        workspaceId: 'portal-main',
        mergeOrder: [1, 2, 3, 4, 5],
        settings: {
            'workbench.startupEditor': 'none',
            'files.autoSave': 'afterDelay',
            'editor.formatOnSave': true,
        },
        roots: [
            {
                path: 'apps/frontend',
                label: 'Frontend root',
                settings: {
                    'editor.defaultFormatter': 'dbaeumer.vscode-eslint',
                    'typescript.tsdk': 'node_modules/typescript/lib',
                    'files.exclude': ['**/.next', '**/dist', '**/coverage'],
                },
                debugger: {
                    name: 'Portal UI',
                    type: 'pwa-node',
                    request: 'launch',
                    cwd: 'apps/frontend',
                    program: 'apps/frontend/src/main.tsx',
                    runtimeExecutable: 'node',
                    args: ['--enable-source-maps'],
                },
                terminal: {
                    name: 'Frontend terminal',
                    shell: 'pnpm',
                    cwd: 'apps/frontend',
                    env: { NODE_ENV: 'development', VITE_APP_NAME: 'portal' },
                },
                enabledExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss', 'ms-vscode.vscode-typescript-next'],
            },
            {
                path: 'apps/backend',
                label: 'Backend root',
                settings: {
                    'editor.defaultFormatter': 'esbenp.prettier-vscode',
                    'files.exclude': ['**/dist', '**/coverage'],
                },
                debugger: {
                    name: 'API server',
                    type: 'node',
                    request: 'launch',
                    cwd: 'apps/backend',
                    program: 'apps/backend/src/server.js',
                    runtimeExecutable: 'node',
                },
                terminal: {
                    name: 'Backend terminal',
                    shell: 'pnpm',
                    cwd: 'apps/backend',
                    env: { NODE_ENV: 'development' },
                },
                enabledExtensions: ['esbenp.prettier-vscode', 'ms-azuretools.vscode-docker'],
            },
        ],
    },
    'docs-review': {
        id: 'docs-review',
        name: 'Docs review',
        workspaceLabel: 'Docs review',
        description: 'Runbook and governance doc set used during release prep.',
        root: 'docs',
        workspaceId: 'docs-review',
        mergeOrder: [1, 2, 3, 4, 5],
        settings: { 'files.autoSave': 'off', 'editor.wordWrap': 'on' },
        roots: [
            {
                path: 'docs',
                label: 'Docs root',
                settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'markdown.preview.breaks': true },
                debugger: {
                    name: 'Docs preview',
                    type: 'pwa-node',
                    request: 'launch',
                    cwd: 'docs',
                    program: 'docs/scripts/preview.ts',
                    runtimeExecutable: 'node',
                },
                terminal: { name: 'Docs terminal', shell: 'pnpm', cwd: 'docs' },
                enabledExtensions: ['yzhang.markdown-all-in-one', 'bierner.markdown-mermaid'],
            },
        ],
    },
    'ops-control': {
        id: 'ops-control',
        name: 'Ops control',
        workspaceLabel: 'Ops control',
        description: 'Operational automation, redeploy gates, and failover controls.',
        root: 'scripts',
        workspaceId: 'ops-control',
        mergeOrder: [1, 2, 3, 4, 5],
        settings: { 'files.autoSave': 'off', 'terminal.integrated.defaultProfile.windows': 'PowerShell' },
        roots: [
            {
                path: 'scripts',
                label: 'Operations root',
                settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'files.exclude': ['**/node_modules', '**/dist'] },
                debugger: {
                    name: 'Ops automation',
                    type: 'node',
                    request: 'launch',
                    cwd: 'scripts',
                    program: 'scripts/ops/run-resilience-campaign.sh',
                    runtimeExecutable: 'node',
                },
                terminal: { name: 'Ops terminal', shell: 'bash', cwd: 'scripts', env: { CI: 'true' } },
                enabledExtensions: ['timonwong.shellcheck', 'ms-vscode.powershell'],
            },
        ],
    },
    'dev-sandbox': {
        id: 'dev-sandbox',
        name: 'Dev sandbox',
        workspaceLabel: 'Dev sandbox',
        description: 'Experimental feature branch workspace for pilot navigation flows.',
        root: 'apps/frontend',
        workspaceId: 'dev-sandbox',
        mergeOrder: [1, 2, 3, 4, 5],
        settings: { 'workbench.startupEditor': 'readme', 'editor.formatOnSave': true },
        roots: [
            {
                path: 'apps/frontend',
                label: 'Frontend root',
                settings: { 'editor.defaultFormatter': 'dbaeumer.vscode-eslint', 'typescript.tsdk': 'node_modules/typescript/lib' },
                debugger: {
                    name: 'Sandbox preview',
                    type: 'pwa-node',
                    request: 'launch',
                    cwd: 'apps/frontend',
                    program: 'apps/frontend/src/main.tsx',
                    runtimeExecutable: 'node',
                },
                terminal: { name: 'Sandbox terminal', shell: 'pnpm', cwd: 'apps/frontend' },
                enabledExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss'],
            },
        ],
    },
    'security-lab': {
        id: 'security-lab',
        name: 'Security lab',
        workspaceLabel: 'Security lab',
        description: 'Security hardening workspace with stricter repo access controls.',
        root: 'apps/backend',
        workspaceId: 'security-lab',
        mergeOrder: [1, 2, 3, 4, 5],
        settings: { 'workbench.startupEditor': 'none', 'files.exclude': ['**/.secrets', '**/dist', '**/coverage'] },
        roots: [
            {
                path: 'apps/backend',
                label: 'Security root',
                settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'terminal.integrated.shellIntegration.enabled': false },
                debugger: {
                    name: 'Security server',
                    type: 'node',
                    request: 'launch',
                    cwd: 'apps/backend',
                    program: 'apps/backend/src/server.js',
                    runtimeExecutable: 'node',
                },
                terminal: { name: 'Security terminal', shell: 'bash', cwd: 'apps/backend' },
                enabledExtensions: ['timonwong.shellcheck', 'gruntfuggly.todo-tree'],
            },
        ],
    },
};
function cloneWorkspaceRoot(root) {
    return {
        ...root,
        settings: { ...root.settings },
        debugger: {
            ...root.debugger,
            args: root.debugger.args ? [...root.debugger.args] : undefined,
            env: root.debugger.env ? { ...root.debugger.env } : undefined,
            config: root.debugger.config ? { ...root.debugger.config } : undefined,
        },
        terminal: {
            ...root.terminal,
            env: root.terminal.env ? { ...root.terminal.env } : undefined,
        },
        enabledExtensions: [...root.enabledExtensions],
    };
}
function cloneWorkspaceProfile(profile) {
    return {
        ...profile,
        settings: { ...profile.settings },
        mergeOrder: [...profile.mergeOrder],
        roots: profile.roots.map((root) => cloneWorkspaceRoot(root)),
    };
}
function createFallbackRoot(workspaceId) {
    return {
        path: workspaceId,
        label: 'Workspace root',
        settings: { 'workbench.startupEditor': 'welcomePage' },
        debugger: {
            name: 'Workspace debugger',
            type: 'pwa-node',
            request: 'launch',
            cwd: workspaceId,
            program: 'src/index.ts',
            runtimeExecutable: 'node',
        },
        terminal: { name: 'Workspace terminal', shell: 'pnpm', cwd: workspaceId },
        enabledExtensions: [],
    };
}
function getWorkspaceProfileManifest(workspaceId) {
    return WORKSPACE_PROFILE_MANIFESTS[workspaceId];
}
function createWorkspaceJson(profile, activeRoot) {
    return JSON.stringify({
        schema_version: 1,
        id: profile.workspaceId,
        name: profile.name,
        workspace_label: profile.workspaceLabel,
        description: profile.description,
        primary_root: profile.root,
        selected_root: activeRoot.path,
        merge_order: profile.mergeOrder,
        roots: profile.roots.map((root) => ({
            path: root.path,
            label: root.label,
            settings: root.settings,
            debugger: root.debugger,
            terminal: root.terminal,
            enabledExtensions: root.enabledExtensions,
        })),
        settings: profile.settings,
    }, null, 2);
}
export function buildWorkspaceProfileSnapshot(root, selectedRoot, projectFiles = []) {
    const profile = getWorkspaceProfileManifest(root);
    const activeRoot = resolveWorkspaceRootProfile(root, selectedRoot);
    const autoConfig = buildWorkspaceAutoConfigSuggestion(projectFiles);
    return {
        profiles: profile ? [cloneWorkspaceProfile(profile)] : [],
        activeProfileId: profile?.workspaceId ?? root,
        lastUpdated: Date.now(),
        workspaceJson: profile
            ? createWorkspaceJson(profile, activeRoot)
            : JSON.stringify({
                schema_version: 1,
                id: root,
                name: root,
                selected_root: activeRoot.path,
                roots: [activeRoot],
            }, null, 2),
        workspaceLabel: profile?.workspaceLabel ?? root,
        mergeOrder: profile?.mergeOrder ?? [1, 2, 3, 4, 5],
        detectedProjectType: autoConfig?.projectType,
        autoConfig,
    };
}
export function getWorkspaceProfile(id) {
    const profile = getWorkspaceProfileManifest(id);
    return profile ? cloneWorkspaceProfile(profile) : null;
}
export function resolveWorkspaceRootProfile(root, selectedPath) {
    const profile = getWorkspaceProfileManifest(root);
    const roots = profile?.roots.map((entry) => cloneWorkspaceRoot(entry)) ?? [];
    if (selectedPath) {
        const selectedRoot = roots.find((entry) => entry.path === selectedPath);
        if (selectedRoot) {
            return selectedRoot;
        }
    }
    return roots[0] ?? createFallbackRoot(root);
}
export function readStoredWorkspaceTabs(storage) {
    if (!storage) {
        return { activeRepoId: 'portal-main', recentRepoIds: ['dev-sandbox', 'security-lab'] };
    }
    try {
        const activeRepoId = storage.getItem('workspace-tabs:active-repo') || 'portal-main';
        const recentRepoIds = JSON.parse(storage.getItem('workspace-tabs:recent-repos') || '[]');
        return {
            activeRepoId,
            recentRepoIds: Array.isArray(recentRepoIds) ? recentRepoIds : ['dev-sandbox', 'security-lab'],
        };
    }
    catch {
        return { activeRepoId: 'portal-main', recentRepoIds: ['dev-sandbox', 'security-lab'] };
    }
}
export function writeStoredWorkspaceTabs(storage, workspaceState) {
    if (!storage) {
        return;
    }
    storage.setItem('workspace-tabs:active-repo', workspaceState.activeRepoId);
    storage.setItem('workspace-tabs:recent-repos', JSON.stringify(workspaceState.recentRepoIds));
}
export function buildRecentWorkspaceIds(activeRepoId, recentRepoIds, maxCount = 2) {
    return [activeRepoId, ...recentRepoIds.filter((workspaceId) => workspaceId !== activeRepoId)].slice(0, maxCount);
}
export function getSuggestedWorkspaceId(roleIds) {
    const normalizedRoleIds = roleIds.map((roleId) => roleId.toLowerCase());
    if (normalizedRoleIds.includes('admin') || normalizedRoleIds.includes('auditor')) {
        return 'ops-control';
    }
    if (normalizedRoleIds.includes('developer')) {
        return 'dev-sandbox';
    }
    if (normalizedRoleIds.includes('reviewer')) {
        return 'docs-review';
    }
    if (normalizedRoleIds.includes('viewer')) {
        return 'portal-main';
    }
    return 'portal-main';
}
export function notifyWorkspaceTabsChanged() {
    if (typeof window === 'undefined') {
        return;
    }
    window.dispatchEvent(new Event('workspace-tabs:changed'));
}
//# sourceMappingURL=workspaceProfilesData.js.map