#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "jsonschema==4.23.0"]
# ///
"""Validate rendered templates against pinned upstream and Red Hat CRDs.

Run with Terraform 1.16.1 on PATH (or set TERRAFORM_BIN). Requires network access
to raw.githubusercontent.com, not cloud credentials or a Kubernetes cluster.
"""
import json
import os
from pathlib import Path
import subprocess
from urllib.request import urlopen

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "Certificate": "https://raw.githubusercontent.com/cert-manager/cert-manager/v1.19.6/deploy/crds/cert-manager.io_certificates.yaml",
    "ClusterIssuer": "https://raw.githubusercontent.com/cert-manager/cert-manager/v1.19.6/deploy/crds/cert-manager.io_clusterissuers.yaml",
    "CertManager": "https://raw.githubusercontent.com/openshift/cert-manager-operator/22755dbe9e996e27c7881539b3fd24a87198ec9c/bundle/manifests/operator.openshift.io_certmanagers.yaml",
}


def strict(schema):
    """Reject unknown fields where the CRD declares a closed property set."""
    if isinstance(schema, dict):
        if schema.get("type") == "object" and "properties" in schema:
            if not schema.get("x-kubernetes-preserve-unknown-fields"):
                schema.setdefault("additionalProperties", False)
        for value in schema.values():
            strict(value)
    elif isinstance(schema, list):
        for value in schema:
            strict(value)


def main():
    schemas = {}
    for kind, url in SOURCES.items():
        with urlopen(url, timeout=30) as response:
            crd = yaml.safe_load(response)
        version = "v1alpha1" if kind == "CertManager" else "v1"
        schemas[kind] = next(
            item["schema"]["openAPIV3Schema"]["properties"]["spec"]
            for item in crd["spec"]["versions"] if item["name"] == version
        )
        strict(schemas[kind])
    tf = os.environ.get("TERRAFORM_BIN", "terraform")
    checked = 0
    for region in ["us-east-1", "us-gov-west-1"]:
        result = subprocess.run(
            [tf, "-chdir=tests/certmanager", "console", f"-var=region={region}"],
            input="jsonencode(local.manifests)\n", text=True, cwd=ROOT,
            capture_output=True, check=True,
        )
        manifests = json.loads(json.loads(result.stdout))
        for manifest in manifests.values():
            if manifest["kind"] in schemas:
                jsonschema.Draft7Validator(schemas[manifest["kind"]]).validate(manifest["spec"])
                checked += 1
    print(f"PASS: {checked} rendered specs match pinned release CRDs (unknown fields rejected)")


if __name__ == "__main__":
    main()
