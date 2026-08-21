#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hdr "0. Environment setup (uv, Python 3.12)"
if ! command -v uv >/dev/null 2>&1; then
  c_red "uv is not installed. Install from https://github.com/astral-sh/uv and re-run."; exit 1
fi

if [ ! -x "$VPY" ]; then
  ( cd "$STARTER" && uv venv --python 3.12 .venv )
fi
( cd "$STARTER" && uv pip install --python .venv/bin/python -r requirements.txt )
c_grn "Dependencies installed."

if [ ! -f "$STARTER/rag_chatbot/.env" ]; then
  cp "$STARTER/.env.example" "$STARTER/rag_chatbot/.env"
  c_yel "Created rag_chatbot/.env - edit it and set OPENAI_API_KEY to your Vocareum key."
else
  c_grn "rag_chatbot/.env already present."
fi

# Optional local TLS fix (corporate CA not in certifi). Harmless if not needed.
SP="$("$VPY" -c 'import site;print(site.getsitepackages()[0])')"
if [ ! -f "$SP/sitecustomize.py" ]; then
  "$VPY" -m pip install --quiet truststore 2>/dev/null || uv pip install --python "$VPY" truststore || true
  cat > "$SP/sitecustomize.py" <<'PYSHIM'
try:
    import truststore; truststore.inject_into_ssl()
except Exception:
    pass
import os
if os.environ.get("FORCE_CPU") == "1":
    try:
        import torch
        torch.backends.mps.is_available = lambda: False
        torch.cuda.is_available = lambda: False
    except Exception:
        pass
PYSHIM
  c_grn "Installed venv sitecustomize (OS trust store + optional FORCE_CPU)."
fi
c_grn "Setup complete."
