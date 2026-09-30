import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";
import { configDefaults } from "vitest/config";
import downloadHandler from "./api/download.ts";

export default defineConfig(() => ({
  base: process.env.ZERUS_PREVIEW_BASE ?? "/",
  server: {
    host: "::",
    port: 8080,
    allowedHosts: ["mac-mini-m4-nox.ibex-oratrice.ts.net"],
  },
  plugins: [
    react(),
    {
      name: "preview-app-route",
      configureServer(server) {
        const base = process.env.ZERUS_PREVIEW_BASE;
        if (!base || base === "/" || !base.endsWith("/")) return;
        const route = base.slice(0, -1);
        server.middlewares.use((request, _response, next) => {
          if (request.url === route || request.url?.startsWith(`${route}?`)) {
            request.url = base + request.url.slice(route.length);
          }
          next();
        });
      },
    },
    {
      name: "download-api-preview",
      configureServer(server) {
        server.middlewares.use((request, response, next) => {
          if (request.url?.split("?")[0] !== "/api/download") return next();
          void downloadHandler(request, response).catch(next);
        });
      },
    },
  ],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },
  build: {
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            {
              name: "editor-ui",
              test: /src[\\/]components[\\/]editor[\\/]/,
              maxSize: 450 * 1024,
              includeDependenciesRecursively: false,
            },
            {
              name: "tabler-icons",
              test: /node_modules[\\/]@tabler[\\/]icons-react[\\/]dist[\\/]esm[\\/]icons[\\/]/,
              maxSize: 900 * 1024,
              includeDependenciesRecursively: false,
            },
          ],
        },
      },
    },
  },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
    exclude: [...configDefaults.exclude, "**/.worktrees/**"],
  },
}));
