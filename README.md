# Project Repository

## Run backend locally (manual)

The FastAPI backend lives under `backend_api/`.

### Option A: use the provided script (recommended)

```bash
./run_backend.sh
```

Environment variables (optional):
- `HOST` (default `0.0.0.0`)
- `PORT` (default `8000`)
- `RELOAD` (default `1`, set `0` to disable)
- `LOG_LEVEL` (default `info`)

### Option B: run directly with pip + uvicorn

From the repository root:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
PYTHONPATH=backend_api/src python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

Backend entrypoint:
- File: `backend_api/src/api/main.py`
- Uvicorn app: `api.main:app`

OpenAPI docs:
- http://localhost:8000/docs
- http://localhost:8000/openapi.json