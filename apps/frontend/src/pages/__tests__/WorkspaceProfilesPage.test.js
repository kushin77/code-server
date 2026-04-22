/** @vitest-environment jsdom */
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { WorkspaceProfilesPage } from '../WorkspaceProfilesPage';
afterEach(() => {
    cleanup();
});
function buildProps(overrides = {}) {
    return {
        workspaceState: {
            activeWorkspace: { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
            recentRepoIds: ['dev-sandbox'],
            projectFiles: ['package.json', 'eslint.config.js'],
            selectWorkspace: vi.fn(),
            workspacePolicy: {
                label: 'Developer',
                canSwitchWorkspace: true,
                canUseQuickSwitcher: true,
                canRestoreSession: true,
                canPinWorkspace: false,
                maxRecentWorkspaces: 3,
            },
            ...overrides.workspaceState,
        },
    };
}
describe('WorkspaceProfilesPage', () => {
    it('renders the active profile details and scope matrix', () => {
        render(<WorkspaceProfilesPage {...buildProps()}/>);
        expect(screen.getByText('Workspace profiles and root-scoped context')).toBeTruthy();
        expect(screen.getAllByText('Portal main').length).toBeGreaterThan(0);
        expect(screen.getByText('workspace.json preview')).toBeTruthy();
        expect(screen.getByText('Workspace sets')).toBeTruthy();
    });
    it('switches workspace profiles through the shared selector callback', () => {
        const selectWorkspace = vi.fn();
        render(<WorkspaceProfilesPage {...buildProps({
            workspaceState: {
                activeWorkspace: { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
                recentRepoIds: ['dev-sandbox'],
                selectWorkspace,
                workspacePolicy: {
                    label: 'Developer',
                    canSwitchWorkspace: true,
                    canUseQuickSwitcher: true,
                    canRestoreSession: true,
                    canPinWorkspace: false,
                    maxRecentWorkspaces: 3,
                },
            },
        })}/>);
        const sandboxButton = screen.getByRole('button', { name: /Dev sandbox/i });
        fireEvent.click(sandboxButton);
        expect(selectWorkspace).toHaveBeenCalledWith('dev-sandbox');
    });
    it('shows the root-specific debugger and terminal details', () => {
        render(<WorkspaceProfilesPage {...buildProps()}/>);
        expect(screen.getAllByText('Frontend root').length).toBeGreaterThan(0);
        expect(screen.getAllByText(/Debugger/i).length).toBeGreaterThan(0);
        expect(screen.getAllByText(/Terminal/i).length).toBeGreaterThan(0);
    });
    it('shows an auto-config preview when project markers are available', () => {
        render(<WorkspaceProfilesPage {...buildProps({
            workspaceState: {
                activeWorkspace: { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
                recentRepoIds: ['dev-sandbox'],
                projectFiles: ['package.json', 'eslint.config.js'],
                selectWorkspace: vi.fn(),
                workspacePolicy: {
                    label: 'Developer',
                    canSwitchWorkspace: true,
                    canUseQuickSwitcher: true,
                    canRestoreSession: true,
                    canPinWorkspace: false,
                    maxRecentWorkspaces: 3,
                },
            },
        })}/>);
        expect(screen.getByText('Auto-config preview')).toBeTruthy();
        expect(screen.getByText('Detected project type: node')).toBeTruthy();
        expect(screen.getAllByText(/dbaeumer\.vscode-eslint/).length).toBeGreaterThan(0);
    });
});
//# sourceMappingURL=WorkspaceProfilesPage.test.js.map