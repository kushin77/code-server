/** @vitest-environment jsdom */
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SymbolDiscussionsPanel } from '../symbol-discussions-panel';
const fetchSymbolDiscussionsByLocation = vi.fn();
vi.mock('../../utils/symbolDiscussions', () => ({
    fetchSymbolDiscussionsByLocation: (...args) => fetchSymbolDiscussionsByLocation(...args),
}));
describe('SymbolDiscussionsPanel', () => {
    beforeEach(() => {
        fetchSymbolDiscussionsByLocation.mockReset();
    });
    afterEach(() => {
        vi.clearAllMocks();
    });
    it('loads and renders discussions for a file location', async () => {
        fetchSymbolDiscussionsByLocation.mockResolvedValueOnce({
            filePath: 'src/services/userService.ts',
            lineNumber: 42,
            count: 1,
            discussions: [
                {
                    id: 'discussion-1',
                    fqn: 'src/services/userService.ts:UserService.getUser',
                    filePath: 'src/services/userService.ts',
                    symbolName: 'getUser',
                    symbolType: 'method',
                    lineNumber: 42,
                    createdAt: '2026-04-22T00:00:00.000Z',
                    updatedAt: '2026-04-22T00:05:00.000Z',
                    thread: {
                        id: 'thread-1',
                        title: 'Should this guard be extracted?',
                        createdBy: 'alice',
                        createdAt: '2026-04-22T00:00:00.000Z',
                        updatedAt: '2026-04-22T00:05:00.000Z',
                        isResolved: false,
                        comments: [
                            {
                                id: 'comment-1',
                                threadId: 'thread-1',
                                author: 'alice',
                                content: 'This check looks reusable across the handler path.',
                                createdAt: '2026-04-22T00:00:00.000Z',
                                updatedAt: '2026-04-22T00:00:00.000Z',
                                isEdited: false,
                                reactions: [],
                            },
                        ],
                    },
                },
            ],
        });
        render(<SymbolDiscussionsPanel />);
        fireEvent.change(screen.getByLabelText('File path'), { target: { value: 'src/services/userService.ts' } });
        fireEvent.change(screen.getByLabelText('Line number'), { target: { value: '42' } });
        fireEvent.click(screen.getByRole('button', { name: 'Load discussions' }));
        await waitFor(() => expect(fetchSymbolDiscussionsByLocation).toHaveBeenCalledWith('src/services/userService.ts', 42));
        expect(await screen.findByText('Should this guard be extracted?')).toBeTruthy();
        expect(screen.getByText('getUser · src/services/userService.ts:42')).toBeTruthy();
        expect(screen.getByText('1 comment')).toBeTruthy();
        expect(screen.getByText('This check looks reusable across the handler path.')).toBeTruthy();
    });
    it('accepts an initial file path and line number', async () => {
        fetchSymbolDiscussionsByLocation.mockResolvedValueOnce({
            filePath: 'src/components/Button.tsx',
            lineNumber: 18,
            count: 0,
            discussions: [],
        });
        render(<SymbolDiscussionsPanel initialFilePath="src/components/Button.tsx" initialLineNumber={18}/>);
        await waitFor(() => expect(fetchSymbolDiscussionsByLocation).toHaveBeenCalledWith('src/components/Button.tsx', 18));
        expect(screen.getByText('No inline discussions are anchored to src/components/Button.tsx:18.')).toBeTruthy();
    });
});
//# sourceMappingURL=symbol-discussions-panel.test.js.map