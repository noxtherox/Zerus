import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";
import { configDefaults } from "vitest/config";

export default defineConfig(() => ({
  server: {
    host: "::",
    port: 8080,
    allowedHosts: ["mac-mini-m4-nox.ibex-oratrice.ts.net"],
  },
  plugins: [react()],
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
