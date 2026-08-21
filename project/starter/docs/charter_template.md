# Red Team Charter

## Engagement Details

| Field | Value |
|-------|-------|
| **Engagement Name** | FinanceGuard AI Systems Red Team Assessment (Project C2) |
| **Date** | 2026-08-20 |
| **Assessor** | Junior AI Red Team Operator, FinanceGuard AI Security |
| **Sponsor** | Chief Information Security Officer (CISO) |

## Objectives

This engagement evaluates the security posture of two pre-production AI systems - the Receipt Classifier (CNN) and the Expense Policy RAG Chatbot - plus their deployment pipeline. Five adversarial vectors are tested:

1. **FGSM Evasion (Receipt Classifier).** Demonstrate that a white-box, gradient-based perturbation can flip the classifier's decision on valid inputs while the image remains visually plausible to a human reviewer.
2. **Label-Flip Data Poisoning (Training Pipeline).** Demonstrate that corrupting a small fraction (<=10%) of training labels measurably degrades model accuracy on an untouched, clean test set.
3. **Prompt Injection (RAG Chatbot).** Demonstrate whether crafted user inputs can override the system prompt, hijack the assistant's role, or coerce it into repeating false policy - and, independently, whether such queries cause the retriever to surface confidential documents.
4. **Data Exfiltration (RAG Vector Store).** Demonstrate that confidential compensation data can be retrieved from the FAISS vector store through ordinary chat queries, because retrieval enforces no access control.
5. **Supply Chain Analysis (Docker/Dependencies).** Enumerate container and dependency vulnerabilities (Trivy) and identify Dockerfile misconfigurations that expand the attack surface of the deployment.

## Scope

### In Scope
- **Receipt Classifier** - `classifier/` model, the pre-trained `receipt_cnn_clean.pt` checkpoint, the training pipeline (`train.py`, `data.py`), and the balanced dataset (training split only for poisoning).
- **Expense Policy RAG Chatbot** - the Flask service on `localhost:5001`, the FAISS index, and the policy documents in `rag_chatbot/data/policies/`.
- **Deployment Infrastructure** - the `Dockerfile` and the Trivy vulnerability report (`06_trivy_report.json`).

### Out of Scope
- FinanceGuard production systems and any real employee or PII data (all data used is synthetic/course-provided).
- The upstream OpenAI / Vocareum API backend and model weights themselves.
- Network, identity, or cloud infrastructure beyond the provided container definition.
- Denial-of-service, destructive, or availability-impacting techniques.

## Rules of Engagement

1. **Isolated environment only.** All testing runs against the local, self-contained lab (local venv, local Flask server, course dataset). No production system is touched and no external party is targeted.
2. **Authorized and non-destructive.** Testing is authorized by the CISO. The clean test set and the shipped clean checkpoint are preserved; only copies are poisoned. No customer or production data is used.
3. **Responsible handling of findings.** Extracted "confidential" content is synthetic course data; it is documented as evidence only and not redistributed. API credentials are kept in a git-ignored `.env` and never committed or logged.

## Success Criteria

| Attack Vector | Success Metric |
|---------------|---------------|
| FGSM Evasion | Adversarial accuracy decreases as eps increases across >=3 eps values, dropping below 50% at some tested eps. |
| Label-Flip Poisoning | <=10% of training labels flipped, test set untouched, poisoned model >=5 percentage points lower accuracy than the clean model on the same clean test set. |
| Prompt Injection | >=5 distinct techniques executed; both signals (answer-level `injection_successful` and retrieval-level `confidential_source_disclosed`) captured and counted separately; >=1 signal positive. |
| Data Exfiltration | >=5 distinct queries; the `executive_bonus_structure_CONFIDENTIAL.md` document retrieved and/or its data leaked in the answer text on multiple queries. |
| Supply Chain Analysis | Trivy severities enumerated (CRITICAL/HIGH/MEDIUM/LOW), specific HIGH CVEs with fixes identified, and >=3 Dockerfile issues found each with a remediation. |

## Deliverables

- **5 completed attack scripts** in `attacks/` (`01_fgsm_evasion.py` ... `05_supply_chain_analysis.py`) with saved JSON/PNG artifacts under `attacks/results/`.
- **9 documentation files** in `docs/`: this Charter, the FGSM results, poisoning results, prompt-injection transcript, data-exfiltration evidence, supply-chain analysis, vulnerability log, executive risk summary, and reproduction steps.
