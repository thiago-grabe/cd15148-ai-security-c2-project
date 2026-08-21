#!/usr/bin/env bash
# Label-flip poisoning: poison -> retrain -> evaluate both on the clean test set.
# Override defaults with:  FLIP_RATE=0.10 SEED=7 ./02_poisoning.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_venv
FLIP_RATE="${FLIP_RATE:-0.10}"
SEED="${SEED:-7}"

hdr "2a. Create poisoned dataset (flip=$FLIP_RATE seed=$SEED)"
( cd "$STARTER/attacks" && "$VPY" 02_label_flip_poisoning.py --flip-rate "$FLIP_RATE" --seed "$SEED" )

hdr "2b. Retrain on poisoned data (protects the clean checkpoint)"
( cd "$STARTER/classifier" && "$VPY" train.py --data-dir poisoned_data --checkpoint-name receipt_cnn_poisoned.pt )

hdr "2c. Evaluate poisoned + clean on the SAME clean test set"
( cd "$STARTER/classifier" && "$VPY" evaluate.py --model-path checkpoints/receipt_cnn_poisoned.pt --test-dir balanced_data/test --results-dir ../attacks/results/02_label_flip/poisoned )
( cd "$STARTER/classifier" && "$VPY" evaluate.py --model-path checkpoints/receipt_cnn_clean.pt   --test-dir balanced_data/test --results-dir ../attacks/results/02_label_flip/clean )

"$VPY" - "$RESULTS" <<'PY'
import json, os, sys
R=sys.argv[1]
cl=json.load(open(os.path.join(R,"02_label_flip/clean/metrics.json")))
po=json.load(open(os.path.join(R,"02_label_flip/poisoned/metrics.json")))
drop=(cl['accuracy']-po['accuracy'])*100
print(f"\nClean acc={cl['accuracy']:.4f}  Poisoned acc={po['accuracy']:.4f}  DROP={drop:.2f}pp")
print("PASS (>=5pp)" if drop>=5 else "NOTE: <5pp this run - label-flip is training-variance-dependent; re-run or try another SEED.")
PY
c_grn "Poisoning done -> attacks/results/02_label_flip/"
