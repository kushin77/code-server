import React from 'react'

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string
  helperText?: string
  error?: boolean
  errorMessage?: string
}

/**
 * Input Component
 * Reusable text input with label and validation states
 */
export const Input: React.FC<InputProps> = ({
  label,
  helperText,
  error = false,
  errorMessage,
  id,
  className,
  ...props
}) => {
  const inputId = id || `input-${Math.random().toString(36).substr(2, 9)}`

  return (
    <div className="w-full">
      {label && (
        <label htmlFor={inputId} className="block text-sm font-medium text-gray-700 mb-2">
          {label}
        </label>
      )}
      <input
        id={inputId}
        className={`
          w-full px-4 py-2 border rounded-lg
          focus:outline-none focus:ring-2 focus:ring-sky-500
          transition-colors
          ${error ? 'border-red-500 focus:ring-red-500' : 'border-gray-300'}
          ${className}
        `.trim()}
        {...props}
      />
      {errorMessage && error && (
        <p className="mt-1 text-sm text-red-600">{errorMessage}</p>
      )}
      {helperText && !error && (
        <p className="mt-1 text-sm text-gray-500">{helperText}</p>
      )}
    </div>
  )
}
