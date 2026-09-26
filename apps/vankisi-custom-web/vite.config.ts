import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

import tailwindcss from '@tailwindcss/vite'

/**
 * Vankisi, a CUSTOM frontend (identity `vankisi-web`) over the shared backend.
 *
 * Open it at its registered local domain, http://vankisi.localhost:5174. The
 * backend picks the restaurant from the request Host, so `/api` is proxied
 * with `changeOrigin: false`: the browser's Host (`vankisi.localhost:5174`)
 * is what the backend receives and resolves through VenueDomain. No Venue id
 * or forwarded host is added here.
 *
 * The port is fixed (`strictPort`) because Platform's local runtime check
 * finds this server through `CUSTOM_WEBSITE_LOCAL_FRONTENDS=vankisi-web=5174`
 * in the backend environment; silently moving to another port would make
 * that check look at the wrong place. `PORT` / `VYNIC_WEBSITE_API` override
 * both for a second local stack. Production serves `dist/` behind a
 * host-preserving `/api` proxy (docs/CUSTOM_WEBSITES.md §5).
 */
const port = Number(process.env.PORT ?? 5174)
const apiTarget = process.env.VYNIC_WEBSITE_API ?? 'http://127.0.0.1:3000'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    host: true,
    port,
    strictPort: true,
    proxy: {
      '/api': { target: apiTarget, changeOrigin: false },
    },
  },
})
