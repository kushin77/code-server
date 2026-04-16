import React from 'react'
import ReactDOM from 'react-dom/client'
import { App } from './App.tsx'
import './index.css'

// Initialize OpenTelemetry FIRST, before any other code runs
import { initOTel } from './otel-setup'
initOTel()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
