# Run scripts

All scripts resolve their own paths, so you can run them from anywhere. They use
the project virtualenv at `../.venv` (create it with `00_setup.sh`).

| Script | What it does | Network |
|--------|--------------|---------|
| `00_setup.sh` | Create the uv venv, install deps, scaffold `rag_chatbot/.env`, add the local TLS fix. | pip only |
| `01_fgsm.sh` | Clean baseline eval + FGSM sweep. | no |
| `02_poisoning.sh` | Poison (10%/seed 7) → retrain → eval clean vs poisoned. `FLIP_RATE`/`SEED` overridable. | no |
| `03_prompt_injection.sh` | Ensure chatbot is up, run 5 injections. | Vocareum API |
| `04_data_exfiltration.sh` | Ensure chatbot is up, run 6 exfil queries. | Vocareum API |
| `05_supply_chain.sh` | Parse Trivy report + Dockerfile. | no |
| `rag_start.sh` / `rag_stop.sh` | Start/stop the chatbot on :5001 (auto-builds the index). | Vocareum API |
| `run_all.sh` | Everything, in order, auto start/stop the chatbot, prints a summary. | Vocareum API |

## Quick start
```bash
cd project/starter/scripts
./00_setup.sh          # first time only; then put your Vocareum key in ../rag_chatbot/.env
./run_all.sh           # runs the whole project
```

Run one phase at a time, e.g. `./01_fgsm.sh`. The RAG attacks (`03`/`04`) start the
chatbot automatically and leave it running; stop it with `./rag_stop.sh`.
