import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";
import { configDefaults } from "vitest/config";
import downloadHandler from "./api/download.ts";

export default defineConfig(() => ({
  server: {
    host: "::",
    port: 8080,
    allowedHosts: ["mac-mini-m4-nox.ibex-oratrice.ts.net"],
  },
  plugins: [
    react(),
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
