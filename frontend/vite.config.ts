import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: true,
    proxy: {
      '/api': {
        // MANDATE: Use domain DNS or container networks, NEVER localhost
        // Development: VITE_API_URL=http://rbac-api:3001 (Docker container)
        // Staging/Prod: VITE_API_URL=https://api-staging.kushnir.cloud OR https://api.kushnir.cloud
        target: process.env.VITE_API_URL || 'http://rbac-api:3001',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    minify: 'terser',
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          zustand: ['zustand'],
          axios: ['axios'],
        },
      },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
