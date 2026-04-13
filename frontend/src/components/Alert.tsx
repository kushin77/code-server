import React, { useState } from 'react'

interface AlertProps {
  type?: 'success' | 'error' | 'warning' | 'info'
  children: React.ReactNode
  onDismiss?: () => void
  dismissible?: boolean
  className?: string
}

/**
 * Alert Component
 * Reusable alert/notification component with 4 types
 */
export const Alert: React.FC<AlertProps> = ({
  type = 'info',
  children,
  onDismiss,
  dismissible = true,
  className,
}) => {
  const [isVisible, setIsVisible] = useState(true)

  if (!isVisible) return null

  const typeClasses = {
    success: 'bg-green-50 border-green-200 text-green-800',
    error: 'bg-red-50 border-red-200 text-red-800',
    warning: 'bg-yellow-50 border-yellow-200 text-yellow-800',
    info: 'bg-blue-50 border-blue-200 text-blue-800',
  }

  const iconClasses = {
    success: '✓',
    error: '✕',
    warning: '⚠',
    info: 'ℹ',
  }

  const handleDismiss = () => {
    setIsVisible(false)
    onDismiss?.()
  }

  return (
    <div className={`
      border rounded-lg p-4 flex items-start gap-3
      ${typeClasses[type]}
      ${className}
    `.trim()}>
      <span className="flex-shrink-0 font-bold text-lg">
        {iconClasses[type]}
      </span>
      <div className="flex-1">
        {children}
      </div>
      {dismissible && (
        <button
          onClick={handleDismiss}
          className="flex-shrink-0 text-lg hover:opacity-70 transition-opacity"
          aria-label="Dismiss alert"
        >
          ×
        </button>
      )}
    </div>
  )
}
