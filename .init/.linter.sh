#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/home/kavia/workspace/code-generation/copy_of_data-insights-dashboard-data-insights-dashboard-312901-329236"
BACKEND_DIR="${REPO_ROOT}/backend_api"
VENV_DIR="${BACKEND_DIR}/.venv"

cd "${BACKEND_DIR}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found on PATH."
  exit 1
fi

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel >/dev/null
python -m pip install -r requirements.txt >/dev/null

# Run flake8 from the venv (avoids 'flake8: command not found' in CI)
# Important: do NOT lint the virtualenv; lint only project code.
python -m flake8 src tests
