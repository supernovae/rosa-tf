#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["python-hcl2==8.1.4"]
# ///
"""Check tracked tfvars syntax, declared inputs and deployment invariants.

Run: uv run scripts/check-examples.py
This is a static contract check, not a live plan or availability check.
"""

from pathlib import Path
import subprocess

import hcl2
from hcl2.utils import SerializationOptions


ROOT = Path(__file__).resolve().parents[1]
CLUSTERS = [
    "commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"
]
OVERLAYS = {"openshiftai", "netappstorage", "cluster-only", "gitops-workloads", "oadp", "efs-storage", "component-routes", "provider-options"}


def read_hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True
        ))


def declared_inputs(environment):
    return {
        name
        for path in (ROOT / "environments" / environment).glob("*.tf")
        for block in read_hcl(path).get("variable", [])
        for name in block
    }


def main():
    tracked = subprocess.check_output(
        ["git", "ls-files", "*.tfvars"], cwd=ROOT, text=True
    ).splitlines()
    deleted = set(subprocess.check_output(["git", "ls-files", "--deleted", "*.tfvars"], cwd=ROOT, text=True).splitlines())
    tracked = [filename for filename in tracked if filename not in deleted]
    # Include the new safety overlay before its first commit.
    tracked = sorted(set(tracked) | {"examples/cluster-only.tfvars", "examples/gitops-workloads.tfvars", "examples/oadp.tfvars", "examples/efs-storage.tfvars", "examples/component-routes.tfvars", "examples/hcp-spot.tfvars"})
    schemas = {}
    checks = 0
    for filename in tracked:
        path = Path(filename)
        values = read_hcl(ROOT / path)
        if path.parts[0] == "environments":
            targets = [path.parts[1]]
        elif path.parts[0] == "examples":
            targets = CLUSTERS if path.stem in OVERLAYS else [
                "commercial-classic" if path.stem in {"byovpc-classic-prod", "ocpvirtualization"}
                else "commercial-hcp"
            ]
        else:
            continue
        for target in targets:
            if target not in schemas:
                schemas[target] = declared_inputs(target)
            unknown = set(values) - schemas[target]
            assert not unknown, f"{filename} -> {target}: unknown inputs {unknown}"
            if target.endswith("-hcp"):
                assert not values.get("cluster_autoscaler_enabled", False), (
                    f"{filename}: HCP cluster-wide tuning is unsupported"
                )
            checks += 1
        for pool in values.get("machine_pools", []):
            if pool.get("autoscaling", {}).get("enabled", False):
                scaling = pool["autoscaling"]
                assert "replicas" not in pool, f"{filename}: omit replicas for autoscaling"
                assert 0 <= scaling["min"] <= scaling["max"] and scaling["max"] > 0, filename
            if pool.get("autoscaling_enabled", False):
                assert "replicas" not in pool, f"{filename}: omit replicas for autoscaling"
                assert pool["min_replicas"] <= pool["max_replicas"], filename
        if path.name.startswith("cluster-"):
            assert values.get("install_gitops") is False, filename
            if path.parts[:2] == ("environments", "govcloud-hcp"):
                assert values.get("zero_egress") is True, filename
        if path.name.startswith("gitops-"):
            assert values.get("install_gitops") is True, filename
    print(f"PASS: {len(tracked)} tfvars parsed; {checks} environment input contracts checked")


if __name__ == "__main__":
    main()
