# Reproduction Steps

All commands assume the repository is checked out and you are inside `project/starter/`. Paths are relative to that directory. The classifier scripts (`train.py`, `evaluate.py`) use CWD-relative paths, so run them **from `classifier/`**; the five attack scripts are location-independent but are run from `attacks/`.

## Prerequisites

- **Python 3.12** (the project targets 3.12.13; `torch==2.5.1` provides 3.12 wheels) and **[uv](https://github.com/astral-sh/uv)**.
- ~2 GB disk for the virtualenv (PyTorch). A GPU is optional; runs fine on CPU/Apple-Silicon (MPS).
- A **Vocareum OpenAI API key** for the RAG attacks (Steps 5-7). The classifier and supply-chain steps need no network.

## Environment Setup

```bash
cd project/starter

# 1. Create the virtualenv and install pinned dependencies
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r requirements.txt
source .venv/bin/activate            # so `python` = the venv interpreter

# 2. Configure the Vocareum API key (used only by the RAG chatbot)
cp .env.example rag_chatbot/.env
#   then edit rag_chatbot/.env:
#     OPENAI_API_KEY=voc-...your key...
#     OPENAI_BASE_URL=https://openai.vocareum.com/v1
```

> **TLS note (local machines only):** if `build_index.py` fails with `CERTIFICATE_VERIFY_FAILED`, your machine has a corporate root CA that Python's bundled `certifi` doesn't trust. Fix with `uv pip install truststore` and add a `sitecustomize.py` to the venv's site-packages containing `import truststore; truststore.inject_into_ssl()`. This makes Python trust the OS certificate store (like `curl`). Not needed in the Udacity workspace.

## Step 1: Prepare Dataset

The balanced dataset ships in `classifier/balanced_data/` (577/577 train, 195/195 test). No action needed.

```bash
ls classifier/balanced_data/train classifier/balanced_data/test   # receipt/ non_receipt/
```

## Step 2: Train and Evaluate Clean Model

The clean checkpoint `classifier/checkpoints/receipt_cnn_clean.pt` ships pre-trained. Establish the baseline (also used by FGSM):

```bash
cd classifier
python evaluate.py --model-path checkpoints/receipt_cnn_clean.pt \
  --test-dir balanced_data/test \
  --results-dir ../attacks/results/01_fgsm/baseline
cd ..
```

**Expected output:** Accuracy ~ **0.9436**, Precision ~ 0.9943, Recall ~ 0.8923, F1 ~ 0.9405; writes `metrics.json` + `confusion_matrix.png`.

## Step 3: FGSM Attack

```bash
cd attacks
python 01_fgsm_evasion.py
cd ..
```

**Expected output:** a per-eps table where adversarial accuracy falls as eps rises (0.94 at eps=0 -> ~0.27 at eps=0.10; eps=0 must equal the baseline). Writes `results/01_fgsm/fgsm_results.json` and six `fgsm_results_openimages_0000_<eps>.png` comparisons.

## Step 4: Data Poisoning

```bash
# 1. Create the poisoned training set (10% flip; test set untouched)
cd attacks
python 02_label_flip_poisoning.py --flip-rate 0.10 --seed 7
cd ../classifier

# 2. Retrain on the poisoned data (MUST pass --checkpoint-name to protect the clean model)
python train.py --data-dir poisoned_data --checkpoint-name receipt_cnn_poisoned.pt

# 3. Evaluate poisoned + clean on the SAME clean test set
python evaluate.py --model-path checkpoints/receipt_cnn_poisoned.pt --test-dir balanced_data/test --results-dir ../attacks/results/02_label_flip/poisoned
python evaluate.py --model-path checkpoints/receipt_cnn_clean.pt   --test-dir balanced_data/test --results-dir ../attacks/results/02_label_flip/clean
cd ..
```

**Expected output:** the poisoned model's accuracy drops well below the clean baseline (in our run: 94.36% -> **50.00%**, a -44 pp collapse; the poisoned model predicts `non_receipt` for everything).

> **Variance:** label-flip poisoning is training-run-dependent - some retrains absorb the noise (accuracy stays ~0.94) while others collapse. If a run does not show >=5 pp degradation, re-run the retrain or try another `--seed` (still at `--flip-rate 0.10`). Results also differ by hardware (this reference run used Apple-Silicon MPS; CPU/Linux trajectories differ).

## Step 5: RAG Chatbot Setup

```bash
cd rag_chatbot
python build_index.py          # embeds 4 policy docs -> 23 chunks -> faiss_index/
python app.py &                # starts Flask on http://localhost:5001
# wait for readiness, then confirm the key works end-to-end:
curl --retry 15 --retry-connrefused --retry-delay 1 -sS http://localhost:5001/health
curl -sS -X POST http://localhost:5001/chat -H "Content-Type: application/json" \
  -d '{"question": "What is the meal expense limit?"}'
cd ..
```

**Expected output:** `build_index.py` prints "FAISS index built: 23 vectors"; `/health` returns `{"status":"ok"}`; the chat call returns a real answer ("...$75 per person per meal...") with `sources`.

## Step 6: Prompt Injection

```bash
cd attacks
python 03_prompt_injection.py
cd ..
```

**Expected output:** `0/5` answer-level injections succeed (the model refuses), but the confidential file appears in `sources` on `3/5` attempts. Writes `results/03_prompt_injection/prompt_injection_results.json`.

## Step 7: Data Exfiltration

```bash
cd attacks
python 04_data_exfiltration.py
cd ..
# stop the chatbot when done:  kill %1   (or: lsof -ti:5001 | xargs kill)
```

**Expected output:** `6/6` queries exfiltrate - every query retrieves `executive_bonus_structure_CONFIDENTIAL.md`; 4/6 also leak figures (salaries, bonus %, strike price, clawback) in the answer. Writes `results/04_exfiltration/data_exfiltration_results.json`.

## Step 8: Supply Chain Analysis

```bash
cd attacks
python 05_supply_chain_analysis.py
cd ..
```

**Expected output:** 804 total vulnerabilities (0 CRITICAL / 34 HIGH / 160 MEDIUM / 601 LOW / 9 UNKNOWN) and 6 Dockerfile issues; overall risk HIGH. Writes `results/05_supply_chain/supply_chain_report.json`. No network required.

## Expected Results Summary

| Attack | Metric | Expected Result |
|--------|--------|----------------|
| Baseline (clean model) | Accuracy | ~94.4% (P 0.994 / R 0.892 / F1 0.941) |
| FGSM Evasion | Adversarial accuracy vs eps | 0.94 (eps=0) -> 0.81 (0.01) -> 0.51 (0.03) -> 0.30 (0.05) -> 0.27 (0.10); ASR peaks ~0.71 |
| Label-Flip Poisoning | Accuracy drop on clean test | >=5 pp; reference run 94.36% -> 50.00% (-44 pp), receipt recall -> 0% |
| Prompt Injection | injection_successful / confidential_source_disclosed | 0/5 and 3/5 (two independent signals) |
| Data Exfiltration | Queries exfiltrating confidential data | 6/6 (CONFIDENTIAL doc retrieved every time; figures leaked on 4/6) |
| Supply Chain | Vulns by severity + Dockerfile issues | 804 total (34 HIGH), 6 Dockerfile issues, overall HIGH |
