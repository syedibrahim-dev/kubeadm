import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],

  // Dev server config (only used with `npm run dev`, not in Docker/K8s)
  server: {
    port: 5173,
    proxy: {
      // Proxy /api calls to the Go backend during local development
      '/api': {
        target:      'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },

  build: {
    outDir: 'dist',
  },
})
