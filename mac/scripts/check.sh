#!/bin/bash
set -euo pipefail
WRITER_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$WRITER_REPO"
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests -v
python3 mac/scripts/check_dependencies.py
if [[ "${1:-}" == --protocol ]]; then
  export PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
  PYTHONDONTWRITEBYTECODE=1 .venv-hwp/bin/python protocol/v0/run_checks.py
fi
