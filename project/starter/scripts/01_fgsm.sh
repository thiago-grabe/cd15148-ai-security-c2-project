#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv

hdr "1a. FGSM baseline (clean model)"
( cd "$STARTER/classifier" && "$VPY" evaluate.py \
    --model-path checkpoints/receipt_cnn_clean.pt \
    --test-dir balanced_data/test \
    --results-dir ../attacks/results/01_fgsm/baseline )

hdr "1b. FGSM attack sweep"
( cd "$STARTER/attacks" && "$VPY" 01_fgsm_evasion.py )
c_grn "FGSM done -> attacks/results/01_fgsm/"
