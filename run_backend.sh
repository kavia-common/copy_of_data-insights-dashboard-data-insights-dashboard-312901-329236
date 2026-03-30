#!/usr/bin/env bash
set -euo pipefail

# Runs the FastAPI backend manually for this workspace:
# /home/kavia/workspace/code-generation/copy_of_data-insights-dashboard-data-insights-dashboard-312901-329236
#
# What it does:
#  - Creates/uses a Python virtualenv at backend_api/.venv
#  - Installs backend_api/requirements.txt
#  - Starts Uvicorn with the correct module path (src/api/main.py -> api.main:app)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
BACKEND_DIR="${REPO_ROOT}/backend_api"
VENV_DIR="${BACKEND_DIR}/.venv"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
RELOAD="${RELOAD:-1}"  # set RELOAD=0 to disable auto-reload
LOG_LEVEL="${LOG_LEVEL:-info}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found on PATH."
  exit 1
fi

cd "${BACKEND_DIR}"

echo "[run_backend] Using backend directory: ${BACKEND_DIR}"

if [[ ! -d "${VENV_DIR}" ]]; then
  echo "[run_backend] Creating virtualenv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo "[run_backend] Upgrading pip tooling"
python -m pip install --upgrade pip setuptools wheel

if [[ ! -f "${BACKEND_DIR}/requirements.txt" ]]; then
  echo "ERROR: Missing backend requirements file at: ${BACKEND_DIR}/requirements.txt"
  echo "Expected this repo to include backend_api/requirements.txt."
  exit 1
fi

echo "[run_backend] Installing backend requirements (${BACKEND_DIR}/requirements.txt)"
python -m pip install -r "${BACKEND_DIR}/requirements.txt"

# Ensure imports like "from api.main import app" work (backend_api/src/api/main.py)
export PYTHONPATH="${BACKEND_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"

# FastAPI entrypoint:
#   backend_api/src/api/main.py  ->  module "api.main", attribute "app"
UVICORN_CMD=(python -m uvicorn api.main:app --host "${HOST}" --port "${PORT}" --log-level "${LOG_LEVEL}")

if [[ "${RELOAD}" == "1" ]]; then
  UVICORN_CMD+=(--reload)
fi

echo "[run_backend] Starting server:"
printf '  %q' "${UVICORN_CMD[@]}"
echo
echo "[run_backend] OpenAPI docs will be at: http://${HOST}:${PORT}/docs"
echo

exec "${UVICORN_CMD[@]}"
