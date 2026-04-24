// @file        apps/frontend/src/pages/__tests__/CiLogsPage.test.tsx
// @module      pages/ci-logs/tests
// @description Unit tests for the CI logs page component
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { CiLogsPage } from '../CiLogsPage';
describe('CiLogsPage', () => {
    it('renders the in-app CI log panel', () => {
        render(<MemoryRouter initialEntries={['/ci-logs?repo=kushin77%2Fcode-server&workspace=Portal%20main']}>
        <CiLogsPage />
      </MemoryRouter>);
        expect(screen.getByText('Branch CI log panel')).toBeTruthy();
        expect(screen.getByText('kushin77/code-server')).toBeTruthy();
        expect(screen.getByText('Portal main')).toBeTruthy();
    });
});
//# sourceMappingURL=CiLogsPage.test.js.map