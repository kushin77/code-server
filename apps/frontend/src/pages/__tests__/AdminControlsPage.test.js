/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';
vi.mock('@/store', () => ({
    useAuthStore: () => ({
        user: {
            email: 'admin@kushnir.cloud',
            roles: [{ roleId: 'admin' }],
        },
    }),
}));
vi.mock('@/api/rbac-client', () => ({
    rbacAPI: {
        healthCheck: vi.fn().mockResolvedValue({ status: 'ok' }),
        getAuditLogs: vi.fn().mockResolvedValue({ logs: [{ eventType: 'policy.update', userId: 'system', targetId: 'control-plane' }] }),
    },
}));
import { AdminControlsPage } from '../AdminControlsPage.tsx';
afterEach(() => {
    cleanup();
    vi.clearAllMocks();
});
beforeEach(() => {
    const localStorageMock = {
        getItem: vi.fn(() => null),
        setItem: vi.fn(),
        removeItem: vi.fn(),
        clear: vi.fn(),
    };
    Object.defineProperty(window, 'localStorage', {
        value: localStorageMock,
        configurable: true,
    });
    vi.stubGlobal('localStorage', localStorageMock);
    vi.stubGlobal('fetch', vi.fn((input) => {
        const url = String(input);
        if (url.includes('/api/resource-quotas/cost/monthly')) {
            return Promise.resolve({
                ok: true,
                status: 200,
                json: async () => ({
                    success: true,
                    data: {
                        windowStart: Date.UTC(2026, 3, 1),
                        windowEnd: Date.UTC(2026, 3, 22),
                        totals: {
                            cpuHours: 12.5,
                            memoryGbHours: 18.25,
                            storageGbDays: 9.75,
                            gpuHours: 2,
                        },
                        quotas: [
                            {
                                quotaId: 'quota-user-1',
                                userId: 'user-1',
                                workspaceId: 'workspace-main',
                                windowStart: Date.UTC(2026, 3, 1),
                                windowEnd: Date.UTC(2026, 3, 22),
                                sampleCount: 8,
                                estimated: false,
                                cpuHours: 8,
                                memoryGbHours: 11.5,
                                storageGbDays: 4.5,
                                gpuHours: 1,
                            },
                            {
                                quotaId: 'quota-user-2',
                                userId: 'user-2',
                                workspaceId: 'workspace-main',
                                windowStart: Date.UTC(2026, 3, 1),
                                windowEnd: Date.UTC(2026, 3, 22),
                                sampleCount: 3,
                                estimated: true,
                                cpuHours: 4.5,
                                memoryGbHours: 6.75,
                                storageGbDays: 5.25,
                                gpuHours: 1,
                            },
                        ],
                    },
                }),
            });
        }
        if (url.includes('/api/resource-quotas/cost/alerts')) {
            return Promise.resolve({
                ok: true,
                status: 200,
                json: async () => ({
                    success: true,
                    data: [
                        {
                            alertId: 'alert-1',
                            scope: 'user',
                            scopeId: 'user-1',
                            userId: 'user-1',
                            workspaceId: 'workspace-main',
                            metric: 'cpuHours',
                            threshold: 10,
                            actual: 12.5,
                            severity: 'critical',
                            message: 'cpuHours usage 12.50 exceeded budget threshold 10.00',
                            triggeredAt: Date.UTC(2026, 3, 22, 9, 30),
                            acknowledgedAt: undefined,
                            acknowledgedBy: undefined,
                        },
                    ],
                }),
            });
        }
        return Promise.resolve({
            ok: false,
            status: 404,
            json: async () => ({ success: false }),
        });
    }));
});
afterEach(() => {
    vi.unstubAllGlobals();
});
describe('AdminControlsPage', () => {
    it('renders the cost insights dashboard with monthly rollups and alerts', async () => {
        render(<AdminControlsPage />);
        await waitFor(() => {
            expect(screen.getByText('Monthly cost report and budget alerts')).toBeTruthy();
        });
        expect(screen.getByText('12.5')).toBeTruthy();
        expect(screen.getByText('18.25')).toBeTruthy();
        expect(screen.getByText('9.75')).toBeTruthy();
        expect(screen.getByText('2')).toBeTruthy();
        expect(screen.getByText('user-1 · workspace-main')).toBeTruthy();
        expect(screen.getByText('user-2 · workspace-main')).toBeTruthy();
        expect(screen.getByText('cpuHours usage 12.50 exceeded budget threshold 10.00')).toBeTruthy();
        expect(screen.getByText('critical')).toBeTruthy();
        expect(screen.getByText('1 active')).toBeTruthy();
    });
});
//# sourceMappingURL=AdminControlsPage.test.js.map