import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'url'
import path from 'path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: {
    alias: {
      '/src': path.resolve(__dirname, 'src'),
      '@': path.resolve(__dirname, 'src'),
    },
  },
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      // Proxy /api requests to backend when running local dev
      '/api': {
        target: process.env.VITE_API_BASE_URL
          ? process.env.VITE_API_BASE_URL.replace('/api', '')
          : 'http://localhost:8000',
        changeOrigin: true,
        rewrite: (path) => path,
      },
    },
  },
  define: {
    __API_BASE__: JSON.stringify(
      process.env.VITE_API_BASE_URL || 'http://localhost:8000/api'
    ),
  },
})
