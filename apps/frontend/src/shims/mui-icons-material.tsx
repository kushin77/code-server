import React, { type FC } from 'react'

const createIcon = (): FC<any> => {
  return (props) => React.createElement('span', props)
}

export const ContentCopy = createIcon()
export const OpenInNew = createIcon()
export const Delete = createIcon()
