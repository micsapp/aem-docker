import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
    cssCodeSplit: false,
    rollupOptions: {
      input: resolve(__dirname, 'src/main.js'),
      output: {
        dir: resolve(__dirname, 'dist/clientlib-site'),
        entryFileNames: 'js/site.js',
        chunkFileNames: 'js/[name].js',
        assetFileNames: (info) => (info.name && info.name.endsWith('.css') ? 'css/site.css' : 'resources/[name][extname]')
      }
    }
  }
})
