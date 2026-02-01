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
  if ss -ltn | rg ":${port}" >/dev/null 2>&1; then
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

export CONFIG_FILE="${CONFIG_FILE}"

# Start both UI and gateway in dev mode (background)
LOGFILE="/tmp/openclaw-dev.log"
if pgrep -f "pnpm run dev:codespace" >/dev/null 2>&1; then
  echo "[codespace] dev:codespace already running"
else
  echo "[codespace] Starting dev:codespace (UI + gateway)"
  nohup pnpm run dev:codespace > "${LOGFILE}" 2>&1 &
  sleep 1
fi

# Wait for UI
echo "[codespace] Waiting for UI on http://localhost:5173..."
for i in {1..30}; do
  if curl -s --head http://localhost:5173 | head -n1 | rg -q "HTTP/1.[01] [23].." >/dev/null 2>&1; then
    echo "[codespace] UI is up"
    break
  fi
  sleep 1
done

# Wait for Gateway (dev default is 19001)
DEV_PORT=19001
echo "[codespace] Waiting for Gateway on 127.0.0.1:${DEV_PORT}..."
for i in {1..30}; do
  if ss -ltn | rg -q ":${DEV_PORT}" >/dev/null 2>&1; then
    echo "[codespace] Gateway is listening on ${DEV_PORT}"
    break
  fi
  sleep 1
done

if [ -f "${LOGFILE}" ]; then
  echo "[codespace] logs: ${LOGFILE}"
fi

echo "[codespace] Done. UI: http://localhost:5173  Gateway(dev): 127.0.0.1:${DEV_PORT}"
