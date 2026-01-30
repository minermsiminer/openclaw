#!/usr/bin/env bash
set -euo pipefail

# Start script run by Codespaces after the container starts.
# It installs deps if missing, builds UI artifacts, and starts the gateway in the background.

cd "${GITHUB_WORKSPACE:-/workspaces/openclaw}"

# Ensure pnpm is available
if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm missing; please ensure pnpm is installed in the devcontainer image." >&2
  exit 1
fi

# Fast path: skip install if node_modules exists
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  pnpm install
fi

# Build UI and TypeScript (safe to run repeatedly)
echo "Building UI and TypeScript..."
pnpm ui:build || true
pnpm build || true

# Start the gateway if not already running
if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
  echo "Gateway already running."
else
  echo "Starting OpenClaw Gateway in background..."
  nohup pnpm openclaw gateway --port 18789 --bind lan --token devtoken --allow-unconfigured --dev --verbose > /tmp/openclaw-running.log 2>&1 &
  sleep 1
  echo "Gateway logs: /tmp/openclaw-running.log"
fi
