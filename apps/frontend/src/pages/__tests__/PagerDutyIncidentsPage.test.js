// @file        apps/frontend/src/pages/__tests__/PagerDutyIncidentsPage.test.tsx
// @module      pages/__tests__/pagerduty-incidents
// @description Unit tests for PagerDuty Incidents page component
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import axios from 'axios';
import { vi } from 'vitest';
import '@testing-library/jest-dom';
import { PagerDutyIncidentsPage } from '../PagerDutyIncidentsPage';
vi.mock('axios');
vi.mock('@/common/error-boundary', () => ({
    ErrorBoundary: ({ children }) => children,
}));
vi.mock('@/common/performance', () => ({
    useExtensionMountProfiler: () => ({}),
    measureAsyncExtensionProfiler: async (_config, fn) => fn(),
}));
const mockIncidents = [
    {
        id: '1',
        incident_number: 123,
        title: 'Database Connection Timeout',
        status: 'triggered',
        urgency: 'high',
        created_at: '2024-01-15T10:30:00Z',
        last_status_update_at: '2024-01-15T10:30:00Z',
        html_url: 'https://example.pagerduty.com/incidents/123',
        service: {
            id: 'svc1',
            summary: 'API Service',
        },
        assignees: [
            {
                summary: 'John Doe',
                email: 'john@example.com',
            },
        ],
        total_affected_services: 1,
    },
    {
        id: '2',
        incident_number: 124,
        title: 'Memory Usage High',
        status: 'acknowledged',
        urgency: 'low',
        created_at: '2024-01-15T09:00:00Z',
        last_status_update_at: '2024-01-15T10:00:00Z',
        html_url: 'https://example.pagerduty.com/incidents/124',
        service: {
            id: 'svc2',
            summary: 'Worker Service',
        },
        assignees: [],
        total_affected_services: 1,
    },
];
describe('PagerDutyIncidentsPage', () => {
    beforeEach(() => {
        vi.clearAllMocks();
        localStorage.clear();
        localStorage.setItem('pagerduty.token', 'test-token-12345');
        localStorage.setItem('pagerduty.refreshInterval', '30000');
        vi.mocked(axios.create).mockReturnValue({
            get: vi.fn().mockResolvedValue({
                data: {
                    incidents: mockIncidents,
                },
            }),
        });
    });
    it('renders the page with incident summary metrics', async () => {
        render(<PagerDutyIncidentsPage />);
        await waitFor(() => {
            expect(screen.getByText(/PagerDuty Incidents/)).toBeInTheDocument();
            expect(screen.getByText(/Total/)).toBeInTheDocument();
            expect(screen.getByText(/Triggered/)).toBeInTheDocument();
            expect(screen.getByText(/Acknowledged/)).toBeInTheDocument();
            expect(screen.getByText(/Resolved/)).toBeInTheDocument();
        });
        expect(axios.create).toHaveBeenCalledWith(expect.objectContaining({
            baseURL: 'https://api.pagerduty.com',
            headers: expect.objectContaining({
                Authorization: 'Token token=test-token-12345',
            }),
        }));
    });
    it('renders not configured state when token is missing', () => {
        localStorage.clear();
        render(<PagerDutyIncidentsPage />);
        expect(screen.getByText(/PagerDuty Not Configured/)).toBeInTheDocument();
        expect(screen.getByText(/Please configure your PagerDuty API token/)).toBeInTheDocument();
    });
});
//# sourceMappingURL=PagerDutyIncidentsPage.test.js.map