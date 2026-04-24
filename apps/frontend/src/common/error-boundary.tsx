/**
 * Error Boundary component for graceful error handling
 * Wraps components and catches errors during rendering
 */

import { Component, ReactNode, ErrorInfo } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
  onError?: (error: Error, errorInfo: ErrorInfo) => void
}

interface State {
  hasError: boolean
  error?: Error
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    console.error('[ErrorBoundary] Caught error:', error, errorInfo)
    this.props.onError?.(error, errorInfo)
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        this.props.fallback || (
          <div className="flex flex-col gap-4 p-6 border border-red-200 bg-red-50 rounded-lg">
            <h2 className="text-lg font-semibold text-red-900">Something went wrong</h2>
            <p className="text-red-800">{this.state.error?.message || 'An unexpected error occurred'}</p>
            <button
              onClick={() => window.location.reload()}
              className="w-fit px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
            >
              Reload page
            </button>
          </div>
        )
      )
    }

    return this.props.children
  }
}
