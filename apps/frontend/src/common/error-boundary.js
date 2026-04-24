/**
 * Error Boundary component for graceful error handling
 * Wraps components and catches errors during rendering
 */
import { Component } from 'react';
export class ErrorBoundary extends Component {
    constructor(props) {
        super(props);
        this.state = { hasError: false };
    }
    static getDerivedStateFromError(error) {
        return { hasError: true, error };
    }
    componentDidCatch(error, errorInfo) {
        console.error('[ErrorBoundary] Caught error:', error, errorInfo);
        this.props.onError?.(error, errorInfo);
    }
    render() {
        if (this.state.hasError) {
            return (this.props.fallback || (<div className="flex flex-col gap-4 p-6 border border-red-200 bg-red-50 rounded-lg">
            <h2 className="text-lg font-semibold text-red-900">Something went wrong</h2>
            <p className="text-red-800">{this.state.error?.message || 'An unexpected error occurred'}</p>
            <button onClick={() => window.location.reload()} className="w-fit px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700">
              Reload page
            </button>
          </div>));
        }
        return this.props.children;
    }
}
//# sourceMappingURL=error-boundary.js.map