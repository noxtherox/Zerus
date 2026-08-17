import { defineConfig } from "vite";
import dyadComponentTagger from "@dyad-sh/react-vite-component-tagger";
import react from "@vitejs/plugin-react-swc";
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
  test: {
    exclude: [...configDefaults.exclude, "**/.worktrees/**"],
  },
}));
