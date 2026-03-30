#!/usr/bin/env bash
# Diagnostic backend runner for the FastAPI service.
#
# Contract:
#  Inputs (env vars):
#    - HOST (default: 0.0.0.0)
#    - PORT (default: 8000)
#    - RELOAD (default: 1; set to 0 to disable)
#    - LOG_LEVEL (default: info)
#  Outputs:
#    - Starts uvicorn (replaces the shell via exec on success)
#    - Emits deterministic diagnostics to stdout/stderr to help debug 502s
#  Errors:
#    - Exits non-zero on missing tools, missing requirements, import failures, or port binding issues
#  Side-effects:
#    - Creates backend_api/.venv if missing
#    - Installs backend_api/requirements.txt into that venv
set -euxo pipefail

#######################################
# Logging helpers
#######################################
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [run_backend] $*"; }
warn() { echo "[$(ts)] [run_backend][WARN] $*" >&2; }
die() { echo "[$(ts)] [run_backend][ERROR] $*" >&2; exit 1; }
section() { echo; echo "========== $* =========="; }

#######################################
# Actionable hints for common 502 causes
#######################################
print_502_hints() {
  cat >&2 <<'EOF'

[run_backend] Common 502 ("Bad Gateway") root causes & what to check:

1) Backend not running / crashed at startup
   - Look ABOVE in the logs for an import error, missing dependency, or exception during app startup.
   - Try hitting health endpoints directly:
       curl -v http://127.0.0.1:8000/health
       curl -v http://127.0.0.1:8000/ready

2) Wrong host/port or not reachable from proxy
   - If a reverse proxy expects the backend on 0.0.0.0:8000 but you're binding to 127.0.0.1, it may 502.
   - Ensure HOST/PORT match whatever is proxying to the backend.
   - This script defaults to HOST=0.0.0.0 PORT=8000.

3) Port already in use / uvicorn never actually started
   - If PORT is occupied, uvicorn may fail immediately.
   - This script performs a preflight port bind check and prints what's listening.

4) Dependency/env mismatch
   - "ModuleNotFoundError" or "ImportError": your venv might not have installed requirements.
   - Ensure the script is using backend_api/.venv and installs backend_api/requirements.txt.

5) App running but proxy expects a different path
   - Confirm the frontend/proxy is calling the correct base URL (e.g. /api/v1/...).

If you can reach /health directly but still see 502 via the proxy/frontend, the issue is likely proxy routing/base URL,
CORS, or a mismatch between expected and actual host/port.

EOF
}

on_error() {
  warn "Script failed (exit=$?). Printing troubleshooting hints."
  print_502_hints
}
trap on_error ERR

#######################################
# Paths / config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
BACKEND_DIR="${REPO_ROOT}/backend_api"
VENV_DIR="${BACKEND_DIR}/.venv"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
RELOAD="${RELOAD:-1}"   # set RELOAD=0 to disable auto-reload
LOG_LEVEL="${LOG_LEVEL:-info}"

section "Environment summary"
log "Repo root: ${REPO_ROOT}"
log "Backend dir: ${BACKEND_DIR}"
log "Venv dir: ${VENV_DIR}"
log "HOST=${HOST} PORT=${PORT} RELOAD=${RELOAD} LOG_LEVEL=${LOG_LEVEL}"
log "User: $(id -u) ($(whoami))"
log "PWD: $(pwd)"
log "uname: $(uname -a)"

section "Toolchain checks"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH."
log "python3: $(command -v python3)"
python3 --version

if command -v curl >/dev/null 2>&1; then
  log "curl: $(command -v curl)"
else
  warn "curl not found; health check suggestions will still be printed but you cannot run them."
fi

if [[ ! -d "${BACKEND_DIR}" ]]; then
  die "backend_api directory not found at: ${BACKEND_DIR}"
fi

cd "${BACKEND_DIR}"
log "Changed directory to backend: $(pwd)"

section "Virtualenv setup"
if [[ ! -d "${VENV_DIR}" ]]; then
  log "Creating virtualenv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
log "Activated venv: ${VENV_DIR}"
log "python (venv): $(command -v python)"
python --version
log "pip: $(command -v pip)"
pip --version

section "Dependency install & sanity checks"
if [[ ! -f "${BACKEND_DIR}/requirements.txt" ]]; then
  die "Missing backend requirements file at: ${BACKEND_DIR}/requirements.txt"
fi

log "Upgrading pip tooling"
python -m pip install --upgrade pip setuptools wheel

log "Installing backend requirements (${BACKEND_DIR}/requirements.txt)"
python -m pip install -r "${BACKEND_DIR}/requirements.txt"

# Helpful for diagnosing "installed but incompatible" issues.
log "Running 'pip check' (may be noisy but helps diagnose dependency conflicts)"
python -m pip check || true

section "Import/path diagnostics"
# Ensure imports like "from api.main import app" work (backend_api/src/api/main.py)
export PYTHONPATH="${BACKEND_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"
log "PYTHONPATH=${PYTHONPATH}"

log "Python sys.executable and sys.path (first 5 entries):"
python - <<'PY'
import sys
print("sys.executable =", sys.executable)
print("sys.version    =", sys.version.replace("\n"," "))
print("sys.path[:5]   =")
for p in sys.path[:5]:
    print("  -", p)
PY

log "Checking uvicorn is importable and showing its install path:"
python - <<'PY'
import uvicorn
import inspect
print("uvicorn.__version__ =", getattr(uvicorn, "__version__", "unknown"))
print("uvicorn.__file__    =", uvicorn.__file__)
print("uvicorn module      =", uvicorn)
print("uvicorn signature   =", inspect.signature(uvicorn.run))
PY

log "Checking FastAPI app entrypoint import (api.main:app) and showing file path:"
python - <<'PY'
import api.main
print("api.main.__file__ =", api.main.__file__)
app = getattr(api.main, "app", None)
if app is None:
    raise RuntimeError("api.main.app is missing. Entrypoint 'api.main:app' will not work.")
print("api.main.app type  =", type(app))
PY

section "Port binding preflight"
# Preflight: verify we can bind the port, or if not, show what is listening.
python - <<PY
import socket
host = "${HOST}"
port = int("${PORT}")

def can_bind():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # Reduce false positives during rapid restarts
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((host, port))
    except OSError as e:
        return False, str(e)
    finally:
        s.close()
    return True, ""

ok, err = can_bind()
if ok:
    print(f"[run_backend] Port appears free: {host}:{port}")
else:
    print(f"[run_backend][ERROR] Cannot bind to {host}:{port}: {err}")
    print("[run_backend] This usually means another process is already listening, or you lack permissions.")
    raise SystemExit(2)
PY

# If the port might still be in use due to IPv6 or different bind host,
# show listeners when possible (best-effort).
if command -v ss >/dev/null 2>&1; then
  log "Current listeners for port ${PORT} (via ss):"
  ss -ltnp | (grep -E ":${PORT}\b" || true)
elif command -v lsof >/dev/null 2>&1; then
  log "Current listeners for port ${PORT} (via lsof):"
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN || true
elif command -v netstat >/dev/null 2>&1; then
  log "Current listeners for port ${PORT} (via netstat):"
  netstat -ltnp 2>/dev/null | (grep -E ":${PORT}\b" || true)
else
  warn "No ss/lsof/netstat available to display port listeners."
fi

section "Start Uvicorn"
# FastAPI entrypoint:
#   backend_api/src/api/main.py  ->  module "api.main", attribute "app"
UVICORN_CMD=(python -m uvicorn api.main:app --host "${HOST}" --port "${PORT}" --log-level "${LOG_LEVEL}")

if [[ "${RELOAD}" == "1" ]]; then
  UVICORN_CMD+=(--reload)
fi

log "Starting server command:"
printf '  %q' "${UVICORN_CMD[@]}"
echo
log "Docs:  http://${HOST}:${PORT}/docs"
log "Health: http://${HOST}:${PORT}/health"
log "Ready:  http://${HOST}:${PORT}/ready"
log "If you see a 502 from a proxy, confirm the proxy targets this HOST:PORT and that /health is reachable."

exec "${UVICORN_CMD[@]}"
