import { defineConfig } from "vite";
import dyadComponentTagger from "@dyad-sh/react-vite-component-tagger";
import react from "@vitejs/plugin-react";
import path from "path";
import { configDefaults } from "vitest/config";

export default defineConfig(() => ({
  server: {
    host: "::",
    port: 8080,
    allowedHosts: ["mac-mini-m4-nox.ibex-oratrice.ts.net"],
  },
  plugins: [dyadComponentTagger(), react()],
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
    exclude: [...configDefaults.exclude, "**/.worktrees/**"],
  },
}));
