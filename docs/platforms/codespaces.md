---
summary: "GitHub Codespaces: running OpenClaw UI + Gateway (dev only)"
read_when:
  - You want to run OpenClaw inside GitHub Codespaces
  - You need troubleshooting steps for token/pairing and preview URLs
---

# GitHub Codespaces — Quickstart & Troubleshooting 🔧

This page explains how to run the OpenClaw **Control UI (frontend)** and **Gateway (backend)** inside a GitHub Codespace, the issues you may encounter, and how to fix them. It is tailored for development and testing only — do not use these steps to expose an admin surface publicly in production.

---

## TL;DR (fast path) ✅

1. Start the UI and Gateway inside the Codespace:
   - `pnpm ui:dev` (Vite dev server, default port **5173**)
   - `OPENCLAW_GATEWAY_TOKEN=dev pnpm gateway:dev --bind lan --token dev` (Gateway on **19001**)

2. In the Codespaces **Ports** panel, make the Gateway port (e.g. **19001**) public so you can open the preview host.

3. Open the tokenized dashboard URL (gateway host):
   - `https://<your-codespace>-19001.app.github.dev/?token=dev`

4. If you prefer the UI host, point it at the gateway and include the token:
   - `https://<your-codespace>-5173.github.dev/?gatewayUrl=wss://<your-codespace>-19001.app.github.dev/gateway&token=dev`

5. If you see `pairing required`, approve the pending device request:
   - `pnpm openclaw devices list`
   - `pnpm openclaw devices approve <requestId>`

---

## Ports & preview hosts (how Codespaces exposes services)

- UI dev server (Vite): https://<codespace>-5173.github.dev/
- Gateway dev port (example 19001): https://<codespace>-19001.app.github.dev/

Codespaces proxy may require you to manually **Make public** the port in the Ports panel. During testing we manually enabled the Gateway port to be public so the preview host worked.

> Note: making the Control UI or Gateway public is a dev/testing convenience only. Avoid exposing admin surfaces for production workloads.

---

## Common issues & fixes (we hit these during testing)

### 1) "unauthorized / 1008: gateway token missing"
- Cause: the browser attempted a WebSocket handshake without a token.
- Fixes:
  - Open the tokenized dashboard on the Gateway host: `https://<codespace>-19001.app.github.dev/?token=dev`
  - Or open the UI host with explicit gateway URL and token in the query string:
    `https://<codespace>-5173.github.dev/?gatewayUrl=wss://<codespace>-19001.app.github.dev/gateway&token=dev`
  - Or paste the token into Control UI → Settings (Gateway Token) and click Connect.

### 2) "disconnected / 1008: pairing required"
- Cause: the Gateway is configured to require device pairing for new node devices (default & secure behavior).
- Fix:
  - List pending devices: `pnpm openclaw devices list`
  - Approve the pending request: `pnpm openclaw devices approve <requestId>`
  - Reload the UI page (`/chat?session=main`) and the WS should succeed.

### 3) WebSocket proxy / Vite dev server (optional)
- If you prefer the UI host to proxy WS to the Gateway, add a Vite dev-server proxy in `ui/vite.config.ts`:

```ts
server: {
  proxy: {
    '/gateway': {
      target: 'http://127.0.0.1:19001',
      ws: true,
      rewrite: (path) => path.replace(/^\/gateway/, '/gateway')
    },
    '/__openclaw__': { target: 'http://127.0.0.1:19001' }
  }
}
```

This makes the UI connect to `/gateway` on the UI host and lets the dev server upgrade the WS for you.

---

## Logging & debugging

- Gateway log files: `/tmp/openclaw/openclaw-*.log`
  - Tail while testing: `tail -f /tmp/openclaw/openclaw-*.log`
  - Look for lines like `unauthorized ... reason=token_missing` or `pairing-required`
- Useful CLI commands (repo/dev):
  - `pnpm openclaw dashboard` — prints a fresh tokenized dashboard link
  - `pnpm openclaw devices list` — list pending device pairing requests
  - `pnpm openclaw devices approve <id>` — approve device pairing request

---

## Security & best practices ⚠️

- Do not permanently expose the Control UI or Gateway to the public Internet. If you need remote access, prefer Tailscale Serve or an SSH tunnel.
- For dev-only convenience, `gateway.controlUi.allowInsecureAuth: true` can allow token-only auth on insecure contexts, but **only use in trusted dev environments**.
- If Codespaces shows `Proxy headers detected from untrusted address`, and you rely on local-detection behavior, configure `gateway.trustedProxies` appropriately.

---

## Quick checklist (copy/paste)

```bash
# 1) Start UI
pnpm ui:dev

# 2) Start Gateway (example uses a short dev token)
OPENCLAW_GATEWAY_TOKEN=dev pnpm gateway:dev --bind lan --token dev

# 3) In GitHub Codespaces Ports panel: click port 19001 → Make public

# 4) Open the tokenized dashboard (recommended):
https://<codespace>-19001.app.github.dev/?token=dev

# 5) If you see pairing required:
pnpm openclaw devices list
pnpm openclaw devices approve <requestId>
```

### One-click Codespace (make it seamless)

The repository includes a Codespace-ready devcontainer that already runs a build and a start script for you. When a Codespace is created the devcontainer's `postCreateCommand` will run:

- `pnpm install --frozen-lockfile` (installs dependencies)
- `pnpm check:packagejson` (sanity check for malformed package.json)
- `pnpm ui:install` (ensure UI deps are present)
- `pnpm ui:build` (build Control UI assets)
- `pnpm build` (compile server/dist code)

The `postStartCommand` runs `.devcontainer/start-codespace.sh`, which will start `pnpm run dev:codespace` in the background, persist a generated `OPENCLAW_GATEWAY_TOKEN` to `~/.openclaw-dev/openclaw.json` (unless you set `OPENCLAW_GATEWAY_TOKEN` via Codespaces secrets), and wait for the UI and Gateway to come up.

**Important (Codespaces preview hosts):** When running inside GitHub Codespaces the start script also writes a small UI dev config at `ui/public/dev-config.json` containing `gatewayPort`, `token` and, when a Codespace name is detected, a `gatewayPreviewUrl` like `wss://<codespace>-19001.app.github.dev/gateway`. The Control UI will prefer `gatewayPreviewUrl` (if present) to avoid incorrect host:port combinations, so you do not need to guess or supply the gateway host manually.

To make the experience fully one-click:

- Add a repository secret named `OPENCLAW_GATEWAY_TOKEN` in the GitHub **Codespaces → Secrets** settings to provide a stable token (optional, if omitted a token will be generated and persisted to `~/.openclaw-dev/openclaw.json`).
- Open the Codespace, wait a minute for the postCreate + postStart steps to finish, then open the forwarded UI and Gateway previews.

This should make starting the repository in a Codespace behave as a true "one-click" dev experience. If you want, I can open a PR to add the small robustness fixes above (done) and a short troubleshooting blurb on what to check if ports or builds fail.

---

## Related docs

- Control UI (usage & auth): https://docs.openclaw.ai/web/control-ui 🔗
- Dashboard / token usage: https://docs.openclaw.ai/web/dashboard 🔗
- Node/device pairing: https://docs.openclaw.ai/start/pairing 🔗


---

*Created to consolidate Codespaces-specific steps and the fixes we applied during debugging (token, pairing, Vite proxy, making ports public).*