#!/usr/bin/env python3
"""Fail closed before any tag/release mutation; GitHub prerelease flags are not authoritative."""
import json
import re
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check_provider_files(status):
    """Metadata alone cannot authorize a release of prerelease provider code."""
    paths = subprocess.check_output(
        ["git", "ls-files", "*versions.tf", "*.terraform.lock.hcl"],
        cwd=ROOT, text=True,
    ).splitlines()
    checked = 0
    for filename in paths:
        path = ROOT / filename
        if not path.exists():
            continue
        source = path.read_text()
        pattern = (r'provider "registry\.terraform\.io/terraform-redhat/rhcs"\s*\{([^}]+)'
                   if path.name == ".terraform.lock.hcl" else r'rhcs\s*=\s*\{([^}]+)')
        for block in re.findall(pattern, source):
            version = re.search(r'version\s*=\s*"([^\"]+)"', block)
            if not version or version[1].removeprefix("= ") != status["rhcs_version"]:
                raise ValueError(f"RHCS constraint/lock does not match release metadata: {filename}")
            checked += 1
    if not checked:
        raise ValueError("No RHCS provider constraints were checked.")


def check(tag, status):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Only explicit stable semantic-version tags are accepted.")
    if tag != "v" + status["target_version"]:
        raise ValueError("Requested tag does not match the reviewed release target.")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", status["rhcs_version"]):
        raise ValueError("Tagging is blocked while RHCS is a prerelease.")
    if status["status"] != "ready" or status["release_approved"] is not True:
        raise ValueError("Release readiness and approval must be explicitly reviewed first.")


if __name__ == "__main__":
    try:
        status = json.loads((ROOT / "release-status.json").read_text())
        check(sys.argv[1], status)
        check_provider_files(status)
    except (ValueError, IndexError, KeyError) as exc:
        sys.exit(f"Release blocked: {exc}")
    print("Release readiness gate passed")
