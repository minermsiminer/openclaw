import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = path.dirname(fileURLToPath(import.meta.url));

function normalizeBase(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return "/";
  if (trimmed === "./") return "./";
  if (trimmed.endsWith("/")) return trimmed;
  return `${trimmed}/`;
}

export default defineConfig(({ command }) => {
  const envBase = process.env.OPENCLAW_CONTROL_UI_BASE_PATH?.trim();
  const base = envBase ? normalizeBase(envBase) : "./";
  return {
    base,
    publicDir: path.resolve(here, "public"),
    optimizeDeps: {
      include: ["lit/directives/repeat.js"],
    },
    build: {
      outDir: path.resolve(here, "../dist/control-ui"),
      emptyOutDir: true,
      sourcemap: true,
    },
    server: {
      host: true,
      port: 5173,
      strictPort: true,
      // Proxy gateway WS/HTTP paths to the local gateway so the browser (served
      // from Codespaces public host) can reach the gateway without exposing
      // the gateway port. See docs: Vite proxy with ws: true.
      proxy: {
        // WebSocket proxy for control UI websocket upgrades.
        "/gateway": {
          target: "http://127.0.0.1:19001",
          changeOrigin: true,
          ws: true,
          rewrite: (path) => path.replace(/^\/gateway/, ""),
        },
        // Proxy for canvas/media HTTP hosting paths
        "/__openclaw__": {
          target: "http://127.0.0.1:19001",
          changeOrigin: true,
          ws: false,
          rewrite: (path) => path.replace(/^\/__openclaw__/, "/__openclaw__"),
        },
      },
    },
  };
});
