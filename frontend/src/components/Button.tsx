import React from 'react'

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger'
  size?: 'sm' | 'md' | 'lg'
  isLoading?: boolean
  loading?: boolean
  label?: React.ReactNode
  fullWidth?: boolean
}

/**
 * Button Component
 * Reusable enterprise button with variants and sizes
 */
export const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  size = 'md',
  isLoading = false,
  loading = false,
  label,
  fullWidth = false,
  disabled,
  children,
  className,
  ...props
}) => {
  const isLoadingState = isLoading || loading
  const variantClasses = {
    primary: 'bg-sky-600 hover:bg-sky-700 text-white',
    secondary: 'bg-gray-200 hover:bg-gray-300 text-gray-900',
    danger: 'bg-red-600 hover:bg-red-700 text-white',
  }

  const sizeClasses = {
    sm: 'px-2 py-1 text-sm',
    md: 'px-4 py-2 text-base',
    lg: 'px-6 py-3 text-lg',
  }

  const baseClasses = `
    inline-flex items-center justify-center
    rounded-lg font-medium transition-colors
    disabled:opacity-50 disabled:cursor-not-allowed
    focus:outline-none focus:ring-2 focus:ring-offset-2
  `

  const widthClass = fullWidth ? 'w-full' : ''

  return (
    <button
      disabled={disabled || isLoadingState}
      className={`
        ${baseClasses}
        ${variantClasses[variant]}
        ${sizeClasses[size]}
        ${widthClass}
        ${className}
      `.trim()}
      {...props}
    >
      {isLoadingState && (
        <svg className="animate-spin -ml-1 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
        </svg>
      )}
      {label || children}
    </button>
  )
}
