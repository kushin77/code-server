import React from 'react'

type ButtonProps = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'children'> & {
  label: string
  variant?: 'primary' | 'secondary' | 'danger' | string
  fullWidth?: boolean
  loading?: boolean
  flex?: boolean
  size?: 'sm' | 'md' | 'lg' | string
}

type InputProps = React.InputHTMLAttributes<HTMLInputElement> & {
  label?: string
  helperText?: string
  error?: string | null
  block?: boolean
  mb?: number
}

type AlertProps = React.HTMLAttributes<HTMLDivElement> & {
  type?: 'error' | 'warning' | 'success' | string
  variant?: 'error' | 'warning' | 'success' | string
  onClose?: () => void
}

export function Button({ label, loading, fullWidth, flex, size, variant, className = '', ...props }: ButtonProps) {
  const widthClass = fullWidth || flex ? 'w-full' : ''
  const sizeClass = size === 'sm' ? 'px-3 py-2 text-sm' : size === 'lg' ? 'px-5 py-3 text-base' : 'px-4 py-2 text-sm'
  const variantClass =
    variant === 'secondary'
      ? 'border border-slate-300 bg-white text-slate-700 hover:bg-slate-50'
      : variant === 'danger'
        ? 'border border-rose-600 bg-rose-600 text-white hover:bg-rose-700'
        : 'border border-sky-600 bg-sky-600 text-white hover:bg-sky-700'

  return (
    <button
      className={`inline-flex items-center justify-center gap-2 rounded-lg font-medium transition disabled:cursor-not-allowed disabled:opacity-60 ${widthClass} ${sizeClass} ${variantClass} ${className}`.trim()}
      {...props}
    >
      {loading ? 'Loading...' : label}
    </button>
  )
}

export function Input({ label, helperText, error, block = true, mb, className = '', style, ...props }: InputProps) {
  const containerStyle: React.CSSProperties = {
    marginBottom: typeof mb === 'number' ? `${mb * 0.25}rem` : undefined,
  }

  const inputStyle: React.CSSProperties = {
    width: block ? '100%' : undefined,
    ...style,
  }

  return (
    <label className={`block ${className}`.trim()} style={containerStyle}>
      {label ? <span className="mb-1 block text-sm font-medium text-slate-700">{label}</span> : null}
      <input
        className="w-full rounded-lg border border-slate-300 px-3 py-2 text-slate-900 placeholder:text-slate-400 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
        style={inputStyle}
        {...props}
      />
      {error ? <p className="mt-1 text-sm text-rose-600">{error}</p> : null}
      {!error && helperText ? <p className="mt-1 text-sm text-slate-500">{helperText}</p> : null}
    </label>
  )
}

export function Alert({ type, variant, onClose, children, className = '', ...props }: AlertProps) {
  const tone = type ?? variant ?? 'warning'
  const toneClass =
    tone === 'error'
      ? 'border-rose-300 bg-rose-50 text-rose-900'
      : tone === 'success'
        ? 'border-emerald-300 bg-emerald-50 text-emerald-900'
        : 'border-amber-300 bg-amber-50 text-amber-900'

  return (
    <div className={`rounded-2xl border px-4 py-3 ${toneClass} ${className}`.trim()} {...props}>
      <div className="flex items-start justify-between gap-3">
        <div>{children}</div>
        {onClose ? (
          <button type="button" onClick={onClose} aria-label="Close alert" className="rounded-full px-2 py-1">
            ×
          </button>
        ) : null}
      </div>
    </div>
  )
}

export function Card({ children, className = '', ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={`rounded-2xl border border-slate-200 bg-white shadow-sm ${className}`.trim()} {...props}>
      {children}
    </div>
  )
}

export function Spinner({ className = '', size }: React.HTMLAttributes<HTMLSpanElement> & { size?: 'sm' | 'md' | 'lg' | string }) {
  const sizeClass = size === 'lg' ? 'h-8 w-8' : size === 'sm' ? 'h-3 w-3' : 'h-5 w-5'
  return <span className={`inline-block animate-spin rounded-full border-2 border-current border-t-transparent ${sizeClass} ${className}`.trim()} />
}