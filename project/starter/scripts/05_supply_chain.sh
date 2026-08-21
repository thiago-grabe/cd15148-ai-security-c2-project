#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv
hdr "5. Supply chain analysis (no network)"
( cd "$STARTER/attacks" && "$VPY" 05_supply_chain_analysis.py )
c_grn "Supply chain done -> attacks/results/05_supply_chain/"
