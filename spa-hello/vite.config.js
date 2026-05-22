import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  build: {
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: 'index.js',
        chunkFileNames: 'index.js',
        assetFileNames: (info) => (info.name && info.name.endsWith('.css') ? 'index.css' : 'assets/[name][extname]')
      }
    },
    emptyOutDir: true
  }
})
