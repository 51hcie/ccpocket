#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BRIDGE_DIR="${REPO_ROOT}/packages/bridge"

PORT="${BRIDGE_PORT:-${PORT:-8766}}"
HOST="${BRIDGE_HOST:-${HOST:-::}}"
LOG_DIR="${HOME}/.ccpocket"
LOG_FILE="${LOG_DIR}/bridge.log"
PID_FILE="${LOG_DIR}/bridge.pid"

mkdir -p "${LOG_DIR}"

# Locate Node.js binary
NODE_BIN="${NODE_PATH:-}"
if [ -z "${NODE_BIN}" ]; then
  if [ -x "/Users/lw/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node" ]; then
    NODE_BIN="/Users/lw/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
  elif command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  else
    echo "ERROR: Node.js binary not found" >&2
    exit 1
  fi
fi

NODE_DIR="$(dirname "${NODE_BIN}")"
export PATH="${REPO_ROOT}/../../tools/bin:${REPO_ROOT}/../../../tools/bin:${NODE_DIR}:${PATH}"

# Local Proxy if available
if [ -z "${https_proxy:-}" ] && [ -z "${HTTPS_PROXY:-}" ]; then
  export https_proxy="http://127.0.0.1:7897"
  export http_proxy="http://127.0.0.1:7897"
  export all_proxy="socks5://127.0.0.1:7897"
fi

# Stop existing bridge if running
if [ -f "${PID_FILE}" ]; then
  OLD_PID="$(cat "${PID_FILE}" || true)"
  if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "[start-bridge-ipv6] Stopping previous Bridge process (PID ${OLD_PID})..."
    kill "${OLD_PID}" 2>/dev/null || true
    sleep 1
  fi
  rm -f "${PID_FILE}"
fi

# Check if port is in use
if command -v lsof >/dev/null 2>&1; then
  OCCUPIED_PID="$(lsof -ti :"${PORT}" || true)"
  if [ -n "${OCCUPIED_PID}" ]; then
    echo "[start-bridge-ipv6] Killing existing process on port ${PORT} (PID ${OCCUPIED_PID})..."
    kill ${OCCUPIED_PID} 2>/dev/null || true
    sleep 1
  fi
fi

echo "[start-bridge-ipv6] Starting Bridge on host '${HOST}' port '${PORT}' in background..."

# Build if dist does not exist
if [ ! -f "${BRIDGE_DIR}/dist/cli.js" ]; then
  echo "[start-bridge-ipv6] Building bridge..."
  (cd "${BRIDGE_DIR}" && "${NODE_BIN}" ./node_modules/typescript/bin/tsc)
fi

# Launch in background
BRIDGE_HOST="${HOST}" BRIDGE_PORT="${PORT}" nohup "${NODE_BIN}" "${BRIDGE_DIR}/dist/cli.js" --host "${HOST}" --port "${PORT}" > "${LOG_FILE}" 2>&1 &
BRIDGE_PID=$!
echo "${BRIDGE_PID}" > "${PID_FILE}"

echo "[start-bridge-ipv6] Bridge process launched (PID ${BRIDGE_PID}). Log: ${LOG_FILE}"

# Wait up to 10 seconds for health check
READY=0
for i in {1..20}; do
  sleep 0.5
  if curl -s "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 || curl -s "http://[::1]:${PORT}/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
done

if [ "${READY}" -eq 1 ]; then
  echo "[start-bridge-ipv6] Bridge is healthy and listening on [${HOST}]:${PORT}"
  echo "--- Startup Log Output ---"
  tail -n 25 "${LOG_FILE}"
  exit 0
else
  echo "[start-bridge-ipv6] WARNING: Bridge did not respond to health check in 10s. Recent log:"
  tail -n 30 "${LOG_FILE}"
  exit 1
fi
