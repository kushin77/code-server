import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
export default defineConfig({
    plugins: [react()],
    server: {
        port: 3000,
        host: true,
        proxy: {
            '/api': {
                target: process.env.VITE_API_URL || 'http://localhost:3001',
                changeOrigin: true,
                rewrite: (path) => path.replace(/^\/api/, ''),
            },
        },
    },
    test: {
        environment: 'jsdom',
        globals: true,
        coverage: {
            provider: 'v8',
            reporter: ['text', 'json-summary'],
            thresholds: {
                lines: 45,
                functions: 45,
                branches: 35,
                statements: 45,
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
});
//# sourceMappingURL=vite.config.js.map