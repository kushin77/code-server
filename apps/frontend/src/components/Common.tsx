/**
 * Common UI components exported from a central location
 * Re-exports and aliases for frequently used UI components
 */

import React from 'react'

/**
 * Button component
 */
export const Button: React.FC<{
  children?: React.ReactNode
  label?: string
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void
  type?: 'button' | 'submit' | 'reset'
  disabled?: boolean
  className?: string
  variant?: 'primary' | 'secondary' | 'danger'
  fullWidth?: boolean
  flex?: boolean
}> = ({
  children,
  label,
  onClick,
  type = 'button',
  disabled = false,
  className = '',
  variant = 'primary',
  fullWidth = false,
  flex = false,
}) => {
  const variantClass = {
    primary: 'bg-blue-500 text-white hover:bg-blue-600',
    secondary: 'bg-gray-300 text-gray-900 hover:bg-gray-400',
    danger: 'bg-red-500 text-white hover:bg-red-600',
  }[variant]

  const content = children || label

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`px-4 py-2 rounded font-medium transition-colors ${variantClass} ${disabled ? 'opacity-50 cursor-not-allowed' : ''} ${fullWidth ? 'w-full' : ''} ${flex ? 'flex-1' : ''} ${className}`}
    >
      {content}
    </button>
  )
}

/**
 * Input component
 */
export const Input: React.FC<{
  label?: string
  type?: string
  placeholder?: string
  value?: string | number
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void
  disabled?: boolean
  maxLength?: number
  inputMode?: 'numeric' | 'email' | 'url' | 'tel' | 'text'
  className?: string
  error?: string
}> = ({
  label,
  type = 'text',
  placeholder = '',
  value = '',
  onChange,
  disabled = false,
  maxLength,
  inputMode = 'text',
  className = '',
  error,
}) => {
  return (
    <div className={`flex flex-col gap-1 ${className}`}>
      {label && <label className="text-sm font-medium text-gray-700">{label}</label>}
      <input
        type={type}
        placeholder={placeholder}
        value={value}
        onChange={onChange}
        disabled={disabled}
        maxLength={maxLength}
        inputMode={inputMode}
        className={`border rounded px-3 py-2 font-mono text-sm ${error ? 'border-red-500' : 'border-gray-300'} ${disabled ? 'bg-gray-100 cursor-not-allowed' : ''}`}
      />
      {error && <span className="text-sm text-red-500">{error}</span>}
    </div>
  )
}

/**
 * Alert component
 */
export const Alert: React.FC<{
  children: React.ReactNode
  type?: 'info' | 'success' | 'warning' | 'error'
  className?: string
}> = ({ children, type = 'info', className = '' }) => {
  const typeClass = {
    info: 'bg-blue-100 border-blue-500 text-blue-900',
    success: 'bg-green-100 border-green-500 text-green-900',
    warning: 'bg-yellow-100 border-yellow-500 text-yellow-900',
    error: 'bg-red-100 border-red-500 text-red-900',
  }[type]

  return (
    <div className={`border-l-4 p-4 rounded ${typeClass} ${className}`}>
      {children}
    </div>
  )
}

/**
 * Card component
 */
export const Card: React.FC<{
  children: React.ReactNode
  className?: string
  title?: string
}> = ({ children, className = '', title }) => {
  return (
    <div className={`bg-white border border-gray-200 rounded-lg shadow-sm p-4 ${className}`}>
      {title && <h3 className="text-lg font-semibold mb-4">{title}</h3>}
      {children}
    </div>
  )
}

/**
 * Spinner component
 */
export const Spinner: React.FC<{
  size?: 'sm' | 'md' | 'lg'
  className?: string
}> = ({ size = 'md', className = '' }) => {
  const sizeClass = {
    sm: 'w-4 h-4',
    md: 'w-8 h-8',
    lg: 'w-12 h-12',
  }[size]

  return (
    <div
      className={`animate-spin border-4 border-gray-200 border-t-blue-500 rounded-full ${sizeClass} ${className}`}
      role="status"
      aria-label="Loading"
    />
  )
}
