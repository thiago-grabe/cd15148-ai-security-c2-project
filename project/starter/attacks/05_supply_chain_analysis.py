"""
Supply Chain Vulnerability Analysis.

Parses a Trivy JSON report and analyzes a Dockerfile for security issues.
Produces a structured risk assessment of the AI system's deployment pipeline.

Usage:
    python 05_supply_chain_analysis.py
    python 05_supply_chain_analysis.py --trivy-report ../06_trivy_report.json --dockerfile ../Dockerfile
"""
import json
import argparse
import os

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results", "05_supply_chain")


def parse_trivy_report(path):
    """
    Parse a Trivy JSON report and extract vulnerability details.

    The Trivy JSON format has a "Results" array, where each result has:
    - "Target": what was scanned (e.g., "debian 13.4" or "Python")
    - "Type": scan type (e.g., "debian", "python-pkg")
    - "Vulnerabilities": array of vulnerability objects

    Each vulnerability has: VulnerabilityID, Severity, PkgName,
    InstalledVersion, FixedVersion, Title, Description

    Args:
        path: Path to Trivy JSON report

    Returns:
        List of vulnerability dictionaries
    """
    with open(path) as f:
        data = json.load(f)

    vulns = []

    # walk each result's vulnerabilities; use .get() since many lack a FixedVersion
    for result in data.get("Results", []):
        target = result.get("Target", "unknown")
        target_type = result.get("Type", "unknown")
        for vuln in result.get("Vulnerabilities", []):
            vulns.append({
                "id": vuln.get("VulnerabilityID", ""),
                "severity": vuln.get("Severity", "UNKNOWN"),
                "package": vuln.get("PkgName", ""),
                "installed_version": vuln.get("InstalledVersion", ""),
                "fixed_version": vuln.get("FixedVersion", ""),
                "title": vuln.get("Title", ""),
                "description": vuln.get("Description", "")[:200],
                "target": target,
                "target_type": target_type,
            })

    return vulns


def analyze_dockerfile(path):
    """
    Analyze a Dockerfile for common security issues.

    Check for:
    1. Running as root (no USER directive) — HIGH
    2. Unpinned base image (no SHA256 digest) — MEDIUM
    3. COPY . (copies entire context including secrets) — MEDIUM
    4. No HEALTHCHECK — LOW
    5. Build tools left in production image — MEDIUM
    6. Unnecessary tools (curl, git) in production — LOW

    Args:
        path: Path to Dockerfile

    Returns:
        List of issue dictionaries with: issue, severity, detail, recommendation
    """
    with open(path) as f:
        content = f.read()
    lines = content.strip().split("\n")

    issues = []

    # 1. No USER directive -> container runs as root
    has_user = any(line.strip().startswith("USER") for line in lines)
    if not has_user:
        issues.append({
            "issue": "Container runs as root",
            "severity": "HIGH",
            "detail": "No USER directive found; processes run as root, enlarging the "
                      "blast radius if the container is compromised.",
            "recommendation": "Add a non-root user (e.g. 'USER 1000') after installing dependencies.",
        })

    # 2. Unpinned base image (no SHA256 digest)
    from_lines = [l for l in lines if l.strip().startswith("FROM")]
    for from_line in from_lines:
        if "@sha256:" not in from_line:
            issues.append({
                "issue": "Unpinned base image tag",
                "severity": "MEDIUM",
                "detail": f"'{from_line.strip()}' is not pinned to a SHA256 digest; the "
                          "tag can change between builds without notice.",
                "recommendation": "Pin the base image by digest: FROM python:3.11-slim@sha256:<digest>.",
            })

    # 3. COPY . copies the whole build context (secrets, .git, .env)
    copy_all = any("COPY . " in line or "COPY ." in line for line in lines)
    if copy_all:
        issues.append({
            "issue": "COPY . copies entire build context",
            "severity": "MEDIUM",
            "detail": "'COPY . /app' can pull in .env, .git and other secrets, and no "
                      ".dockerignore is present to stop it.",
            "recommendation": "Add a .dockerignore and copy only required paths, or use multi-stage builds.",
        })

    # 4. No HEALTHCHECK
    has_healthcheck = any(line.strip().startswith("HEALTHCHECK") for line in lines)
    if not has_healthcheck:
        issues.append({
            "issue": "No HEALTHCHECK defined",
            "severity": "LOW",
            "detail": "Without HEALTHCHECK, orchestrators cannot detect an unhealthy container.",
            "recommendation": "Add: HEALTHCHECK --interval=30s CMD curl -f http://localhost:5001/health || exit 1.",
        })

    # 5. Build tools left in the final image
    if "build-essential" in content or "gcc" in content:
        if "multi-stage" not in content.lower() and content.count("FROM") == 1:
            issues.append({
                "issue": "Build tools in production image",
                "severity": "MEDIUM",
                "detail": "build-essential/gcc remain in the final single-stage image, "
                          "increasing attack surface and image size.",
                "recommendation": "Compile in a builder stage and copy only artifacts into a clean runtime stage.",
            })

    # 6. Unnecessary tools (curl, git) usable for lateral movement
    if "curl" in content or "git" in content:
        issues.append({
            "issue": "Unnecessary tools in production image",
            "severity": "LOW",
            "detail": "curl and/or git are available at runtime and could aid an "
                      "attacker's lateral movement or data exfiltration.",
            "recommendation": "Remove curl/git from the runtime image or install them only in a build stage.",
        })

    return issues


def generate_report(vulns, dockerfile_issues):
    """Generate a structured supply chain risk report."""
    severity_counts = {}
    for v in vulns:
        sev = v.get("severity", "UNKNOWN")
        severity_counts[sev] = severity_counts.get(sev, 0) + 1

    # top HIGH findings (by CVE id) and Python-package vulns
    high_vulns = sorted(
        [v for v in vulns if v["severity"] == "HIGH"],
        key=lambda v: v["id"],
    )
    python_vulns = [v for v in vulns if v["target_type"] == "python-pkg"]

    report = {
        "summary": {
            "total_vulnerabilities": len(vulns),
            "severity_breakdown": severity_counts,
            "dockerfile_issues": len(dockerfile_issues),
        },
        "high_severity_vulnerabilities": [
            {
                "id": v["id"],
                "package": v["package"],
                "installed": v["installed_version"],
                "fixed": v["fixed_version"],
                "title": v["title"],
            }
            for v in high_vulns[:15]
        ],
        "python_specific": [
            {
                "id": v["id"],
                "package": v["package"],
                "severity": v["severity"],
                "title": v["title"],
                "fixed": v["fixed_version"],
            }
            for v in python_vulns
        ],
        "dockerfile_issues": dockerfile_issues,
        "risk_assessment": {
            "overall_risk": "HIGH" if severity_counts.get("CRITICAL", 0) > 0
                           or severity_counts.get("HIGH", 0) > 10
                           else "MEDIUM",
            "key_concerns": [
                f"{severity_counts.get('HIGH', 0)} HIGH severity vulnerabilities in container dependencies",
                f"{len(python_vulns)} vulnerabilities in Python packages",
                f"{len(dockerfile_issues)} Dockerfile configuration issues",
            ],
        },
    }
    return report


def main():
    parser = argparse.ArgumentParser(description="Supply Chain Vulnerability Analysis")
    parser.add_argument(
        "--trivy-report",
        default=os.path.join(os.path.dirname(__file__), "..", "06_trivy_report.json"),
    )
    parser.add_argument(
        "--dockerfile",
        default=os.path.join(os.path.dirname(__file__), "..", "Dockerfile"),
    )
    parser.add_argument(
        "--output",
        default=os.path.join(RESULTS_DIR, "supply_chain_report.json"),
    )
    args = parser.parse_args()
    if not os.path.dirname(args.output):
        args.output = os.path.join(RESULTS_DIR, args.output)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    print("Parsing Trivy report...")
    vulns = parse_trivy_report(args.trivy_report)

    print("Analyzing Dockerfile...")
    dockerfile_issues = analyze_dockerfile(args.dockerfile)

    report = generate_report(vulns, dockerfile_issues)

    # Print summary
    print(f"\n{'=' * 50}")
    print("  SUPPLY CHAIN RISK ASSESSMENT")
    print(f"{'=' * 50}")
    s = report["summary"]
    print(f"\n  Total vulnerabilities: {s['total_vulnerabilities']}")
    for sev in ["CRITICAL", "HIGH", "MEDIUM", "LOW"]:
        count = s["severity_breakdown"].get(sev, 0)
        if count:
            print(f"    {sev}: {count}")

    print(f"\n  Dockerfile issues: {s['dockerfile_issues']}")
    print(f"{'=' * 50}")

    with open(args.output, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nFull report saved to {args.output}")


if __name__ == "__main__":
    main()
