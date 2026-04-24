import { beforeEach, describe, expect, it, vi } from 'vitest'

import { fetchSymbolDiscussionsByLocation } from '../symbolDiscussions'

const fetchMock = vi.fn()

beforeEach(() => {
  fetchMock.mockReset()
  vi.stubGlobal('fetch', fetchMock)
})

function buildJsonResponse(payload: unknown, ok = true, status = 200) {
  return {
    ok,
    status,
    json: async () => payload,
  } as Response
}

describe('symbolDiscussions', () => {
  it('fetches inline discussion candidates for a file location', async () => {
    fetchMock.mockResolvedValueOnce(
      buildJsonResponse({
        filePath: 'src/services/userService.ts',
        lineNumber: 42,
        count: 1,
        discussions: [],
      })
    )

    await expect(fetchSymbolDiscussionsByLocation('src/services/userService.ts', 42)).resolves.toMatchObject({
      filePath: 'src/services/userService.ts',
      lineNumber: 42,
      count: 1,
    })

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/symbol-discussions/location?filePath=src%2Fservices%2FuserService.ts&lineNumber=42',
      expect.objectContaining({
        headers: expect.objectContaining({
          'Content-Type': 'application/json',
        }),
      })
    )
  })

  it('omits the line number when not provided', async () => {
    fetchMock.mockResolvedValueOnce(
      buildJsonResponse({
        filePath: 'src/services/userService.ts',
        count: 0,
        discussions: [],
      })
    )

    await fetchSymbolDiscussionsByLocation('src/services/userService.ts')

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/symbol-discussions/location?filePath=src%2Fservices%2FuserService.ts',
      expect.objectContaining({
        headers: expect.objectContaining({
          'Content-Type': 'application/json',
        }),
      })
    )
  })
})
