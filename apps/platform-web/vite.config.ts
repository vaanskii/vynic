import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: { dedupe: ["react", "react-dom", "react-router-dom"] },
  plugins: [react(), tailwindcss()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      "/media/website-logos": "http://127.0.0.1:3000",
      "/customer": "http://127.0.0.1:3000",
      "/platform": "http://127.0.0.1:3000",
    },
  },
  preview: {
    host: "127.0.0.1",
    proxy: {
      "/platform": "http://127.0.0.1:3000",
      "/customer": "http://127.0.0.1:3000",
      "/media/website-logos": "http://127.0.0.1:3000",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    css: true,
  },
});
