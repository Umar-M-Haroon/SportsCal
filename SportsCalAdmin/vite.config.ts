import { defineConfig } from 'vite'
import { serverControlPlugin } from './server-plugin'

export default defineConfig({
  plugins: [serverControlPlugin()],
  server: {
    port: 3000,
    proxy: {
      '/v2025': {
        target: 'http://localhost:8080',
        changeOrigin: true
      },
      '/api/admin': {
        target: 'http://localhost:8080',
        changeOrigin: true
      },
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true
      }
    }
  },
  base: '/admin/',
  build: {
    outDir: '../SportsCalAPI/SportsCalServer/Public/admin',
    emptyOutDir: true
  }
})
