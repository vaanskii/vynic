import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

/**
 * A CUSTOM restaurant frontend over the shared Vynic backend.
 *
 * The backend decides the restaurant from the request Host, so `/api` is
 * proxied with `changeOrigin: false`: the browser's Host
 * (`restaurant-x.vynic.localhost`) is what the backend receives. Never point
 * the browser at an absolute API URL — the Host would become the API's own
 * name, and the site's SameSite session cookies would not travel either.
 *
 * Production serves the built files behind the same kind of host-preserving
 * reverse proxy (see docs/CUSTOM_WEBSITES.md).
 */
const apiTarget = process.env.VYNIC_WEBSITE_API ?? "http://127.0.0.1:3000";
const client = fileURLToPath(
  new URL("../../packages/website-client/src/index.ts", import.meta.url),
);
const shared = {
  host: true,
  port: Number(process.env.PORT ?? 5176),
  strictPort: true,
  allowedHosts: [".vynic.localhost", "localhost"],
  proxy: { "/api": { target: apiTarget, changeOrigin: false } },
};

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@vynic/website-client": client } },
  server: {
    ...shared,
    fs: { allow: [".", fileURLToPath(new URL("../../packages", import.meta.url))] },
  },
  preview: shared,
  test: {
    environment: "jsdom",
    setupFiles: "./src/test-setup.ts",
  },
});
