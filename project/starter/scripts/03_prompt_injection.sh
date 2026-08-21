#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv
rag_start
hdr "3. Prompt injection"
( cd "$STARTER/attacks" && "$VPY" 03_prompt_injection.py )
c_grn "Injection done -> attacks/results/03_prompt_injection/  (server left running; scripts/rag_stop.sh to stop)"
