#!/usr/bin/env bash
set -euo pipefail

# Robust Codespace start script.
# - Installs deps if missing
# - Ensures a dev gateway token is configured (writes to ~/.openclaw-dev/openclaw.json)
# - Kills stale processes on dev ports
# - Starts `pnpm run dev:codespace` in background and waits for UI + gateway readiness

cd "${GITHUB_WORKSPACE:-/workspaces/openclaw}"

echo "[codespace] Starting Codespace start script..."

# Ensure pnpm is available
if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm missing; please ensure pnpm is installed in the devcontainer image." >&2
  exit 1
fi

# First-time install
if [ ! -d "node_modules" ]; then
  echo "[codespace] Installing dependencies..."
  pnpm install
else
  echo "[codespace] deps already installed"
fi

# Kill processes that may hold dev ports to avoid port conflicts
for port in 5173 19001 18789; do
  if ss -ltn | grep -q ":${port}" >/dev/null 2>&1; then
    echo "[codespace] Port ${port} in use — attempting to kill owners"
    # Try to kill processes with fuser, fallback to lsof/kill
    if command -v fuser >/dev/null 2>&1; then
      fuser -k ${port}/tcp || true
    else
      pkill -f "vite|openclaw" || true
    fi
    sleep 1
  fi
done

# Ensure a gateway token exists for dev (so gateway won't exit for missing token)
CONFIG_DIR="${HOME}/.openclaw-dev"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
mkdir -p "${CONFIG_DIR}"
# Export early so child helpers (node snippets) can read CONFIG_FILE
export CONFIG_FILE="${CONFIG_FILE}"

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  TOKEN="$OPENCLAW_GATEWAY_TOKEN"
  echo "[codespace] Using existing OPENCLAW_GATEWAY_TOKEN from environment"
else
  # Try to read token from existing config; otherwise generate one and persist
  TOKEN=$(node -e "const fs=require('fs');const p=process.env.CONFIG_FILE; if(fs.existsSync(p)){try{const j=JSON.parse(fs.readFileSync(p,'utf8')); if(j?.gateway?.auth?.token){console.log(j.gateway.auth.token); process.exit(0);} }catch(e){} } console.log(require('crypto').randomBytes(16).toString('hex'))" 2>/dev/null || node -e "console.log(require('crypto').randomBytes(16).toString('hex'))")
  export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
  # Persist token into config file
  node -e "const fs=require('fs'); const p=process.env.CONFIG_FILE; let j={}; if(fs.existsSync(p)){ try{ j=JSON.parse(fs.readFileSync(p,'utf8')) }catch(e){} } j.gateway=j.gateway||{}; j.gateway.auth=j.gateway.auth||{}; j.gateway.auth.token=process.env.OPENCLAW_GATEWAY_TOKEN; fs.writeFileSync(p, JSON.stringify(j,null,2)); console.log('[codespace] wrote token to', p);" 2>/dev/null || true
fi

# Write a small UI dev config so the running Vite dev server can auto-configure gateway URL + token
UI_PUBLIC_DIR="ui/public"
mkdir -p "${UI_PUBLIC_DIR}"
DEV_CONFIG_FILE="${UI_PUBLIC_DIR}/dev-config.json"
GATEWAY_PORT=19001
if [ -n "${CODESPACE_NAME:-}" ]; then
  GATEWAY_PREVIEW_URL="wss://${CODESPACE_NAME}-${GATEWAY_PORT}.app.github.dev/gateway"
else
  GATEWAY_PREVIEW_URL=""
fi
# Write JSON using Node so values are properly escaped (handles slashes/quotes safely)
node -e "const fs=require('fs'); const p=process.env.DEV_CONFIG_FILE; const obj={gatewayPort: Number(process.env.GATEWAY_PORT)||19001, token: process.env.OPENCLAW_GATEWAY_TOKEN||'', gatewayPreviewUrl: process.env.GATEWAY_PREVIEW_URL||''}; fs.writeFileSync(p, JSON.stringify(obj,null,2)); console.log('[codespace] wrote UI dev config to', p);" 2>/dev/null || echo "{\"gatewayPort\":${GATEWAY_PORT},\"token\":\"${TOKEN}\",\"gatewayPreviewUrl\":\"${GATEWAY_PREVIEW_URL}\"}" > "${DEV_CONFIG_FILE}"
# Informative message
if [ -f "${DEV_CONFIG_FILE}" ]; then
  echo "[codespace] Wrote UI dev config to ${DEV_CONFIG_FILE}"
fi

# CONFIG_FILE already exported earlier; continue

# Start Gateway first, wait for it, then start the UI so the UI picks up a live gateway URL/token
LOGFILE="/tmp/openclaw-dev.log"
# Start gateway if not already listening
if ss -ltn | grep -q ":${GATEWAY_PORT}" >/dev/null 2>&1; then
  echo "[codespace] Gateway already listening on ${GATEWAY_PORT}"
else
  echo "[codespace] Starting Gateway (dev) and logging to ${LOGFILE}"
  nohup OPENCLAW_SKIP_CHANNELS=1 CLAWDBOT_SKIP_CHANNELS=1 node scripts/run-node.mjs --dev --bind lan gateway > "${LOGFILE}" 2>&1 &
  # wait up to 30s for gateway port
  for i in {1..30}; do
    if ss -ltn | grep -q ":${GATEWAY_PORT}" >/dev/null 2>&1; then
      echo "[codespace] Gateway is listening on ${GATEWAY_PORT}"
      break
    fi
    sleep 1
  done
fi

# Start UI (Vite) if not already running
if ss -ltn | grep -q ":5173" >/dev/null 2>&1; then
  echo "[codespace] UI already listening on 5173"
else
  echo "[codespace] Starting UI (Vite) and logging to ${LOGFILE}"
  nohup pnpm ui:dev -- --host 0.0.0.0 --port 5173 >> "${LOGFILE}" 2>&1 &
  sleep 1
fi

# Wait for UI
echo "[codespace] Waiting for UI on http://localhost:5173..."
for i in {1..30}; do
  if curl -s --head http://localhost:5173 | head -n1 | grep -qE "HTTP/1\.[01] [23]" >/dev/null 2>&1; then
    echo "[codespace] UI is up"
    break
  fi
  sleep 1
done

# Wait for Gateway (dev default is 19001)
DEV_PORT=19001
echo "[codespace] Waiting for Gateway on 127.0.0.1:${DEV_PORT}..."
for i in {1..30}; do
  if ss -ltn | grep -q ":${DEV_PORT}" >/dev/null 2>&1; then
    echo "[codespace] Gateway is listening on ${DEV_PORT}"
    break
  fi
  sleep 1
done

if [ -f "${LOGFILE}" ]; then
  echo "[codespace] logs: ${LOGFILE}"
fi

# If running in GitHub Codespaces, show the preview URLs that Codespaces provides
if [ -n "${CODESPACE_NAME:-}" ]; then
  echo "[codespace] Detected Codespace: ${CODESPACE_NAME}"
  echo "[codespace] Public UI preview (if port 5173 is public): https://${CODESPACE_NAME}-5173.github.dev/"
  echo "[codespace] Public Gateway preview (if port ${DEV_PORT} is public): https://${CODESPACE_NAME}-${DEV_PORT}.app.github.dev/?token=${OPENCLAW_GATEWAY_TOKEN}"
  echo "[codespace] Tip: open the Codespaces Ports panel and 'Make public' the port if you need browser access from the host."
fi

echo "[codespace] Done. UI: http://localhost:5173  Gateway(dev): 127.0.0.1:${DEV_PORT}"
