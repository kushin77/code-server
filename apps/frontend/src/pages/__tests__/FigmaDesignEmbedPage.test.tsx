/** @vitest-environment jsdom */

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { FigmaDesignEmbedPage } from '../FigmaDesignEmbedPage'

const getMock = vi.fn().mockResolvedValue({ data: { files: [] } })
const postMock = vi.fn()
const storage = new Map<string, string>()

vi.stubGlobal('localStorage', {
  getItem: vi.fn((key: string) => storage.get(key) ?? null),
  setItem: vi.fn((key: string, value: string) => {
    storage.set(key, value)
  }),
  removeItem: vi.fn((key: string) => {
    storage.delete(key)
  }),
  clear: vi.fn(() => {
    storage.clear()
  }),
  key: vi.fn((index: number) => Array.from(storage.keys())[index] ?? null),
  length: 0,
})

vi.mock('axios', () => ({
  default: {
    create: vi.fn(() => ({
      get: getMock,
      post: postMock,
    })),
  },
}))

afterEach(() => {
  cleanup()
  storage.clear()
  getMock.mockClear()
  postMock.mockClear()
})

beforeEach(() => {
  storage.set('figma.token', 'test-token')
})

describe('FigmaDesignEmbedPage', () => {
  it('renders the Figma embed panel and loads files from the client', async () => {
    render(<FigmaDesignEmbedPage />)

    expect(screen.getByText('Figma Designs')).toBeTruthy()
    expect(await screen.findByText('No Figma files found.')).toBeTruthy()
    expect(getMock).toHaveBeenCalledWith('/files', expect.objectContaining({ params: { team_id: undefined } }))
  })
})
