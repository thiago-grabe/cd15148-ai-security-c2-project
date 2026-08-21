#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv
rag_start
hdr "4. Data exfiltration"
( cd "$STARTER/attacks" && "$VPY" 04_data_exfiltration.py )
c_grn "Exfiltration done -> attacks/results/04_exfiltration/  (server left running; scripts/rag_stop.sh to stop)"
