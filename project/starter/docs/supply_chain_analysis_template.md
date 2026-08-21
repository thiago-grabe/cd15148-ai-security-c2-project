# Supply Chain Vulnerability Analysis

Source artifacts: `06_trivy_report.json` (Trivy 0.69.3 scan of the `offensive-ai-course` container image, Debian 13.4) and `Dockerfile`. Produced by `python 05_supply_chain_analysis.py` -> `../attacks/results/05_supply_chain/supply_chain_report.json`.

## Vulnerability Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 34 |
| MEDIUM | 160 |
| LOW | 601 |
| UNKNOWN | 9 |
| **Total** | **804** |

The image carries **34 HIGH** findings - 31 in OS packages (Debian) and 3 in Python packages. There are no CRITICAL findings, but the HIGH count (>10) drives the overall risk assessment to **HIGH**. (The 9 UNKNOWN-severity entries are preserved in the report rather than dropped.)

## High Severity Findings

The 31 OS-level HIGHs are almost all in **`linux-libc-dev` 6.12.74-2** (kernel headers) and currently have **no fixed version** - they must be remediated by updating the base image, not by patching a package. The 3 Python-package HIGHs are directly actionable (fixes exist):

| CVE | Package | Installed -> Fixed | Description |
|-----|---------|-------------------|-------------|
| CVE-2026-24049 | wheel | 0.45.1 -> **0.46.2** | Privilege escalation / arbitrary code execution via a malicious wheel |
| CVE-2026-23949 | jaraco.context | 5.3.0 -> **6.1.0** | Path traversal via a malicious tar archive |
| CVE-2013-7445 | linux-libc-dev | 6.12.74-2 -> *no fix* | Kernel memory exhaustion via crafted GEM objects (representative of 31 kernel HIGHs) |
| CVE-2021-3847 | linux-libc-dev | 6.12.74-2 -> *no fix* | Low-privileged user privilege escalation |
| CVE-2025-38584 | linux-libc-dev | 6.12.74-2 -> *no fix* | `padata` use-after-free |

*(Full list of 34 HIGH CVEs in the JSON report under `high_severity_vulnerabilities`.)*

## Python-Specific Vulnerabilities

Trivy's `python-pkg` scan flagged 3 HIGH findings (2 unique CVEs; `wheel` appears twice):

- **CVE-2026-24049 - `wheel` 0.45.1 -> 0.46.2**: a malicious wheel can achieve privilege escalation / arbitrary code execution during install. Directly relevant because this pipeline installs packages from wheels.
- **CVE-2026-23949 - `jaraco.context` 5.3.0 -> 6.1.0**: path traversal when extracting a malicious tar archive.

These are the highest-leverage fixes: both are one-line version bumps and both sit in the build/packaging path that assembles the AI service.

## Dockerfile Issues

`analyze_dockerfile()` found **6** issues (rubric requires >=3):

### 1. Container runs as root - HIGH
**Risk:** No `USER` directive, so the service runs as UID 0. If the Flask app (or a dependency) is compromised, the attacker has root inside the container, maximizing blast radius and easing container escape.
**Fix:** Create and switch to a non-root user after installing dependencies, e.g. `RUN useradd -m app && USER app` (or `USER 1000`).

### 2. Unpinned base image tag - MEDIUM
**Risk:** `FROM python:3.11-slim` is not pinned to a digest; the tag can be re-pointed upstream, so builds are not reproducible and a poisoned upstream image would be pulled silently.
**Fix:** Pin by digest: `FROM python:3.11-slim@sha256:<digest>`.

### 3. `COPY . /app` copies the entire build context - MEDIUM
**Risk:** With no `.dockerignore` present in the repo, `COPY . /app` bakes in whatever is in the context - `.env` (the Vocareum API key!), `.git/`, local caches, and the FAISS index - into the image layers.
**Fix:** Add a `.dockerignore` (excluding `.env`, `.git`, `__pycache__`, `faiss_index/`, data) and copy only the needed paths.

### 4. No HEALTHCHECK - LOW
**Risk:** Orchestrators cannot tell if the service is actually serving; a hung process keeps receiving traffic.
**Fix:** `HEALTHCHECK --interval=30s CMD curl -f http://localhost:5001/health || exit 1` (the app already exposes `/health`).

### 5. Build tools left in the production image - MEDIUM
**Risk:** `build-essential` and `gcc` remain in the final single-stage image, enlarging the attack surface (a compiler is a useful primitive for an attacker) and image size.
**Fix:** Use a multi-stage build - compile in a builder stage, copy only artifacts into a clean runtime stage.

### 6. Unnecessary tools (`curl`, `git`) in production - LOW
**Risk:** `curl` and `git` are available at runtime and are classic lateral-movement / exfiltration primitives if the container is compromised.
**Fix:** Remove `curl`/`git` from the runtime image, or install them only in a build stage.

## AI Pipeline Risk Assessment

- **Model integrity.** `load_index.py` `pickle.load`s `chunks.pkl` from disk with no integrity check. Combined with `COPY .` and a writable image, a tampered `chunks.pkl` yields **arbitrary code execution** at chatbot startup - a concrete supply-chain path into the AI service. The classifier checkpoint (`.pt`) is likewise loaded without signature verification.
- **Dependency security / confusion.** The pinned Python HIGHs (`wheel`, `jaraco.context`) sit in the install path; an attacker who can influence dependency resolution (typosquat / dependency-confusion) could ship a malicious wheel and exploit CVE-2026-24049 for code execution during build. Pin hashes and use a trusted, internal index.
- **Runtime privileges.** Running as root (Issue 1) means any RCE - via a vulnerable dependency, the pickle path, or the web layer - is immediately root inside the container, making escape and persistence far easier.
- **Secret exposure.** `COPY .` with no `.dockerignore` risks baking the live Vocareum API key (`.env`) into a distributed image (Issue 3).
- **Base-image / runtime mismatch.** The container pins Python **3.11** while the project targets **3.12.13**; the 31 unfixable kernel HIGHs come with the Debian base, so the base image itself should be rebased to a patched, slimmer, digest-pinned image.

## Remediation Priority

| Priority | Action |
|----------|--------|
| 1 | Add a non-root `USER`, add a `.dockerignore` (exclude `.env`, `.git`), and stop baking secrets into the image - closes the highest-impact, lowest-effort issues (root + secret exposure). |
| 2 | Bump the actionable Python HIGHs (`wheel`->0.46.2, `jaraco.context`->6.1.0), pin the base image by digest, and rebase onto a patched base image to clear the kernel-header HIGHs. |
| 3 | Adopt a multi-stage build (drop build tools, `curl`, `git`), add a `HEALTHCHECK`, and add integrity verification (hash-pinned installs, signed model/index artifacts) to close the `pickle`/checkpoint RCE path. |
