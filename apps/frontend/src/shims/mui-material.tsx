import React, { type FC, type ReactNode } from 'react'

const createComponent = (tag: keyof JSX.IntrinsicElements): FC<any> => {
  return ({ children, ...props }: { children?: ReactNode }) =>
    React.createElement(tag, props, children)
}

export const Box = createComponent('div')
export const Dialog = createComponent('div')
export const DialogTitle = createComponent('div')
export const DialogContent = createComponent('div')
export const DialogActions = createComponent('div')
export const List = createComponent('ul')
export const ListItem = createComponent('li')
export const ListItemText = createComponent('div')
export const Chip = createComponent('span')
export const Typography = createComponent('div')
export const CircularProgress = createComponent('span')
export const Alert = createComponent('div')

export const Button: FC<any> = ({ children, ...props }) => React.createElement('button', props, children)
export const TextField: FC<any> = (props) => React.createElement('input', props)

export default {
  Box,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  TextField,
  List,
  ListItem,
  ListItemText,
  Chip,
  Typography,
  CircularProgress,
  Alert,
}
