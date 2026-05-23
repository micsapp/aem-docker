import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

// AEM author origin + admin creds for dev-mode proxy.
// Override per-shell with AEM_HOST / AEM_USER / AEM_PASS env vars.
const AEM_HOST = process.env.AEM_HOST || 'http://localhost:4502'
const AEM_USER = process.env.AEM_USER || 'admin'
const AEM_PASS = process.env.AEM_PASS || 'admin'

export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/content': { target: AEM_HOST, changeOrigin: true, auth: `${AEM_USER}:${AEM_PASS}` },
      '/conf':    { target: AEM_HOST, changeOrigin: true, auth: `${AEM_USER}:${AEM_PASS}` }
    }
  },
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
