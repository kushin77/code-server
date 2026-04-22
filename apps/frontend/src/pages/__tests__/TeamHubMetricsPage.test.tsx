/** @vitest-environment jsdom */

import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

import { TeamHubMetricsPage } from '../TeamHubMetricsPage'

afterEach(() => {
  cleanup()
})

describe('TeamHubMetricsPage', () => {
  it('renders the demo presence snapshot', () => {
    render(
      <MemoryRouter>
        <TeamHubMetricsPage />
      </MemoryRouter>
    )

    expect(screen.getByText('Team online snapshot')).toBeTruthy()
    expect(screen.getByText('3')).toBeTruthy()
    expect(screen.getByText('1')).toBeTruthy()
    expect(screen.getByText('2')).toBeTruthy()
    expect(screen.getByText(/Alice Chen/)).toBeTruthy()
  })
})