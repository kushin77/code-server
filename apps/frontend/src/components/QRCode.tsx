import React from 'react'

export type QRCodeProps = {
  value: string
  size?: number
  level?: 'L' | 'M' | 'Q' | 'H'
  includeMargin?: boolean
}

function hashValue(value: string): number {
  let hash = 0
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0
  }
  return hash
}

export default function QRCode({ value, size = 200, includeMargin = true }: QRCodeProps) {
  const cells = 21
  const margin = includeMargin ? 4 : 0
  const cellSize = size / (cells + margin * 2)
  const hash = hashValue(value)

  const points: React.ReactNode[] = []
  for (let row = 0; row < cells; row += 1) {
    for (let column = 0; column < cells; column += 1) {
      const bit = (hash >> ((row * cells + column) % 31)) & 1
      const isCorner = (row < 7 && column < 7) || (row < 7 && column >= cells - 7) || (row >= cells - 7 && column < 7)
      const filled = isCorner || bit === 1

      if (!filled) {
        continue
      }

      points.push(
        <rect
          key={`${row}-${column}`}
          x={(column + margin) * cellSize}
          y={(row + margin) * cellSize}
          width={cellSize}
          height={cellSize}
          rx={cellSize * 0.12}
          fill={isCorner ? '#0f172a' : '#1e293b'}
        />
      )
    }
  }

  return (
    <svg
      viewBox={`0 0 ${size} ${size}`}
      width={size}
      height={size}
      role="img"
      aria-label="QR code"
      className="block"
    >
      <rect width={size} height={size} fill="#ffffff" />
      {points}
    </svg>
  )
}
