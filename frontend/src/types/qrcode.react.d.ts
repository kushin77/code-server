declare module 'qrcode.react' {
  import React from 'react'
  
  interface QRCodeProps {
    value: string
    size?: number
    level?: 'L' | 'M' | 'Q' | 'H'
    includeMargin?: boolean
    renderAs?: 'canvas' | 'svg'
    fgColor?: string
    bgColor?: string
    imageSettings?: {
      src: string
      height: number
      width: number
      excavate: boolean
    }
  }
  
  const QRCode: React.FC<QRCodeProps>
  export default QRCode
}
