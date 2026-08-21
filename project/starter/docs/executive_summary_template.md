# Executive Risk Summary

## Overview

At the CISO's direction, we performed an authorized red-team assessment of FinanceGuard's two pre-production AI systems - the Receipt Classifier and the Expense Policy Chatbot - and their deployment pipeline, before wider rollout. All testing ran in an isolated lab against synthetic data. We executed five distinct attacks; **all five succeeded to a degree that warrants remediation before production.** The most serious issue is that the expense chatbot readily exposes **confidential executive compensation data** to ordinary users. We recommend delaying the go-live of the chatbot until the confidential-data exposure is fixed.

## Risk Dashboard

| System | Risk Level | Key Finding |
|--------|-----------|-------------|
| Receipt Classifier | **HIGH** | Nearly invisible image tampering flips the classifier's decision; corrupting a small slice of training data can make it reject all valid receipts. |
| RAG Chatbot | **CRITICAL** | Any employee can retrieve confidential executive salary and bonus figures through normal questions; the vector database enforces no access control. |
| Deployment Infrastructure | **HIGH** | The container runs with full privileges, can leak its own API key into the built image, and ships with hundreds of known vulnerabilities. |

## Findings Summary

### 1. Confidential Pay Data Is Exposed to Any Employee - CRITICAL
**Business Impact:** The chatbot returned real executive base salaries (up to $1.2M), bonus percentages, stock-option grants, and clawback terms in response to routine questions - on 6 of 6 attempts. This is a direct confidentiality breach of board-restricted compensation data. Consequences include employee-relations and morale fallout, potential regulatory/HR exposure, and loss of trust if leaked externally. The data has no access control, so exposure is systemic, not a one-off.

### 2. Receipt Classifier Can Be Fooled by Invisible Tampering - HIGH
**Business Impact:** An attacker can alter a receipt image in a way a human reviewer cannot see, yet reliably flip the classifier's verdict. This enables fraudulent claims to be auto-approved, or legitimate receipts to be rejected. Automated expense approval cannot safely stand on this model alone.

### 3. Poisoning the Training Data Can Disable the Classifier - HIGH
**Business Impact:** Corrupting under 10% of training labels caused the retrained model to reject **100% of genuine receipts** (accuracy fell from 94% to 50%). If poisoned data entered the training pipeline, automated reimbursements would halt entirely (a denial of service on the business process) until detected and retrained.

### 4. The Chatbot's Guardrails Rely Only on the AI's Good Behavior - MEDIUM
**Business Impact:** Five manipulation attempts (fake personas, "ignore your instructions," encoded requests) were refused by the current model. However, the confidential data is still handed to the model on every related query; only the model's current behavior prevents disclosure. A future model update or a new jailbreak could turn Finding 4 into Finding 1. This protection is weak and sits at the wrong layer.

### 5. The Deployment Container Is Over-Privileged and Outdated - HIGH
**Business Impact:** The container runs as root, can accidentally bake its live API key into the shipped image, and carries 34 high-severity known vulnerabilities. Any single compromise (via a dependency, a tampered model file, or the web layer) would grant an attacker full control of the container, and the exposed key could run up API costs or be abused.

## Prioritized Remediation

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 1 | Remove the confidential compensation document from the chatbot's shared knowledge base and add access control so restricted data is never retrieved for general users. | Low | Critical - closes the confidential-data breach (Findings 1 & 4). |
| 2 | Harden the container: run as a non-root user, add a `.dockerignore` so secrets are never copied in, pin/patch the base image, and update the two fixable high-severity Python packages. | Low-Medium | High - removes the highest-impact infrastructure risks (Finding 5). |
| 3 | Add defense-in-depth for the classifier: adversarial training, input preprocessing, training-data integrity/provenance controls, and validation monitoring; keep human review for high-value claims. | Medium-High | High - restores trust in automated expense processing (Findings 2 & 3). |

## Conclusion

**Top recommendation:** Do not expand the Expense Policy Chatbot to production until the confidential-data exposure (Priority 1) is fixed - it is a low-effort change that closes a critical breach. The classifier can proceed only with the defense-in-depth controls in Priority 3 and human review retained for high-value claims. The infrastructure hardening in Priority 2 should accompany any deployment. All three priorities are achievable in the near term and materially reduce the organization's risk.
