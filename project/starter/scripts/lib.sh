#!/usr/bin/env bash
# Shared helpers for the FinanceGuard red-team run scripts.
# Sourced by the other scripts; not meant to be run directly.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STARTER="$(dirname "$LIB_DIR")"
VPY="$STARTER/.venv/bin/python"
RESULTS="$STARTER/attacks/results"
RAG_URL="http://localhost:5001"

c_grn() { printf '\033[0;32m%s\033[0m\n' "$*"; }
c_yel() { printf '\033[0;33m%s\033[0m\n' "$*"; }
c_red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
hdr()   { echo; printf '\033[1;36m==== %s ====\033[0m\n' "$*"; }

require_venv() {
  if [ ! -x "$VPY" ]; then
    c_red "Virtualenv not found at $VPY"
    c_yel "Run scripts/00_setup.sh first."
    exit 1
  fi
}

# --- RAG server helpers (chatbot on :5001) ---
rag_healthy() { curl -sf "$RAG_URL/health" >/dev/null 2>&1; }

rag_wait() {
  local i
  for i in $(seq 1 30); do
    rag_healthy && { c_grn "RAG server healthy at $RAG_URL"; return 0; }
    sleep 1
  done
  c_red "RAG server did not become healthy - see $STARTER/rag_chatbot/server.log"
  return 1
}

rag_start() {
  require_venv
  if rag_healthy; then c_grn "RAG server already running"; return 0; fi
  if [ ! -f "$STARTER/rag_chatbot/.env" ]; then
    c_red "rag_chatbot/.env is missing - add your Vocareum key (see scripts/00_setup.sh)"; return 1
  fi
  if [ ! -f "$STARTER/rag_chatbot/faiss_index/policy.index" ]; then
    hdr "Building FAISS index"
    ( cd "$STARTER/rag_chatbot" && "$VPY" build_index.py )
  fi
  hdr "Starting RAG server (:5001)"
  ( cd "$STARTER/rag_chatbot" && nohup "$VPY" app.py </dev/null > "$STARTER/rag_chatbot/server.log" 2>&1 & )
  rag_wait
}

rag_stop() {
  if lsof -ti:5001 >/dev/null 2>&1; then
    lsof -ti:5001 | xargs kill 2>/dev/null || true
    c_grn "RAG server stopped"
  else
    echo "No RAG server running on :5001"
  fi
}

print_summary() {
  [ -x "$VPY" ] || return 0
  "$VPY" - "$RESULTS" <<'PY'
import json, os, sys
R = sys.argv[1]
def load(p):
    p = os.path.join(R, p)
    return json.load(open(p)) if os.path.exists(p) else None
print("\n================ RESULTS SUMMARY ================")
b = load("01_fgsm/baseline/metrics.json")
if b: print(f"Baseline clean : acc={b['accuracy']:.4f} P={b['precision']:.4f} R={b['recall']:.4f} F1={b['f1']:.4f}")
fg = load("01_fgsm/fgsm_results.json")
if fg: print("FGSM sweep     : " + "  ".join(f"e{r['epsilon']}={r['adversarial_accuracy']:.3f}" for r in fg))
cl, po = load("02_label_flip/clean/metrics.json"), load("02_label_flip/poisoned/metrics.json")
if cl and po:
    drop = (cl['accuracy']-po['accuracy'])*100
    print(f"Poisoning      : clean {cl['accuracy']:.4f} -> poisoned {po['accuracy']:.4f}  drop={drop:.2f}pp  ({'PASS >=5pp' if drop>=5 else 'below 5pp'})")
inj = load("03_prompt_injection/prompt_injection_results.json")
if inj: print(f"Injection      : successful={sum(1 for r in inj if r.get('injection_successful'))}/{len(inj)}  conf_source_disclosed={sum(1 for r in inj if r.get('confidential_source_disclosed'))}/{len(inj)}")
ex = load("04_exfiltration/data_exfiltration_results.json")
if ex: print(f"Exfiltration   : exfiltrated={sum(1 for r in ex if r.get('data_exfiltrated'))}/{len(ex)}  conf_retrieved={sum(1 for r in ex if r.get('confidential_source_retrieved'))}/{len(ex)}")
sc = load("05_supply_chain/supply_chain_report.json")
if sc:
    s = sc['summary']; print(f"Supply chain   : {s['total_vulnerabilities']} vulns {s['severity_breakdown']}  dockerfile_issues={s['dockerfile_issues']}  risk={sc['risk_assessment']['overall_risk']}")
print("=================================================")
PY
}
