import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

/**
 * The generic SaaS restaurant website.
 *
 * One build serves every Venue: which restaurant a request belongs to is
 * decided by the backend from the request Host, never by this app. That makes
 * the proxy below part of the tenancy contract rather than a convenience —
 * `changeOrigin` stays false so the browser's Host (`restaurant-a.vynic.local`)
 * is what the backend actually receives. Rewriting it would silently point
 * every local restaurant at whichever Venue owns the backend's own hostname.
 *
 * `allowedHosts` lists the local development names only. Production serves the
 * built assets from a host-preserving reverse proxy; see
 * `docs/WEBSITE_PHASE_W3.md`.
 */
const apiTarget = process.env.VYNIC_WEBSITE_API ?? "http://127.0.0.1:3102";

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5175,
    strictPort: true,
    allowedHosts: [".vynic.local", "localhost", "127.0.0.1"],
    proxy: {
      "/api": { target: apiTarget, changeOrigin: false },
    },
  },
  preview: {
    host: true,
    port: 5175,
    strictPort: true,
    allowedHosts: [".vynic.local", "localhost", "127.0.0.1"],
    proxy: {
      "/api": { target: apiTarget, changeOrigin: false },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    css: true,
  },
});
