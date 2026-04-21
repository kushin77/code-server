import React from 'react'

type PrimitiveProps = React.HTMLAttributes<HTMLElement> & {
  children?: React.ReactNode
}

type SpaceProps = {
  p?: number
  mb?: number
  width?: string | number
  display?: string
  justifyContent?: React.CSSProperties['justifyContent']
  alignItems?: React.CSSProperties['alignItems']
  gap?: number
}

const toSpacing = (value?: number) => (typeof value === 'number' ? `${value * 0.25}rem` : undefined)

export function Panel({ children, className = '', ...props }: PrimitiveProps) {
  return (
    <div className={`rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-950 ${className}`.trim()} {...props}>
      {children}
    </div>
  )
}

export function PanelHeader({ children, className = '', ...props }: PrimitiveProps) {
  return (
    <div className={`border-b border-slate-200 px-4 py-3 dark:border-slate-800 ${className}`.trim()} {...props}>
      {children}
    </div>
  )
}

export function PanelBody({ children, className = '', ...props }: PrimitiveProps) {
  return (
    <div className={`p-4 ${className}`.trim()} {...props}>
      {children}
    </div>
  )
}

export function Button({ children, className = '', size, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { size?: string }) {
  return <button className={className} {...props}>{children}</button>
}

export function TextInput({ className = '', block, mb, ...props }: React.InputHTMLAttributes<HTMLInputElement> & { block?: boolean; mb?: number }) {
  const style: React.CSSProperties = {
    marginBottom: toSpacing(mb),
    display: block ? 'block' : undefined,
    width: block ? '100%' : undefined,
  }

  return <input className={className} style={style} {...props} />
}

export function Spinner({ className = '', ...props }: React.HTMLAttributes<HTMLSpanElement>) {
  return <span className={`inline-block h-3 w-3 animate-spin rounded-full border-2 border-current border-t-transparent ${className}`.trim()} {...props} />
}

export function Alert({ children, className = '', variant, onClose, ...props }: React.HTMLAttributes<HTMLDivElement> & { variant?: string; onClose?: () => void }) {
  const variantClass =
    variant === 'error'
      ? 'border-rose-300 bg-rose-50 text-rose-900'
      : 'border-amber-300 bg-amber-50 text-amber-900'

  return (
    <div className={`rounded-2xl border px-4 py-3 ${variantClass} ${className}`.trim()} {...props}>
      <div className="flex items-start justify-between gap-3">
        <div>{children}</div>
        {onClose && (
          <button type="button" onClick={onClose} aria-label="Close alert" className="rounded-full px-2 py-1">
            ×
          </button>
        )}
      </div>
    </div>
  )
}

export function Badge({ children, className = '', variant, ...props }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string }) {
  const variantClass =
    variant === 'attention'
      ? 'border-amber-300 bg-amber-100 text-amber-900'
      : 'border-slate-300 bg-slate-100 text-slate-700'

  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-medium ${variantClass} ${className}`.trim()} {...props}>
      {children}
    </span>
  )
}

export function Box({
  children,
  className = '',
  p,
  mb,
  width,
  display,
  justifyContent,
  alignItems,
  gap,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & SpaceProps) {
  const style: React.CSSProperties = {
    padding: toSpacing(p),
    marginBottom: toSpacing(mb),
    width,
    display,
    justifyContent,
    alignItems,
    gap: toSpacing(gap),
  }

  return (
    <div className={className} style={style} {...props}>
      {children}
    </div>
  )
}

export function Flex({ children, className = '', p, mb, width, display = 'flex', justifyContent, alignItems, gap, ...props }: React.HTMLAttributes<HTMLDivElement> & SpaceProps) {
  const style: React.CSSProperties = {
    padding: toSpacing(p),
    marginBottom: toSpacing(mb),
    width,
    display,
    justifyContent,
    alignItems,
    gap: toSpacing(gap),
  }

  return (
    <div className={className} style={style} {...props}>
      {children}
    </div>
  )
}
