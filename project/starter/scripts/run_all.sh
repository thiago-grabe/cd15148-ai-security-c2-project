#!/usr/bin/env bash
# Run the entire FinanceGuard red-team pipeline end to end.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv
trap 'rag_stop' EXIT   # always stop the chatbot when we finish or abort

DIR="$LIB_DIR"
bash "$DIR/01_fgsm.sh"
bash "$DIR/02_poisoning.sh"
bash "$DIR/05_supply_chain.sh"
rag_start
bash "$DIR/03_prompt_injection.sh"
bash "$DIR/04_data_exfiltration.sh"

print_summary
c_grn "\nAll phases complete. Docs in docs/, artifacts in attacks/results/."
