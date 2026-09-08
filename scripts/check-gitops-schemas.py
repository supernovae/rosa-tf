#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "jsonschema==4.23.0", "python-hcl2==8.1.4"]
# ///
"""Check rendered GitOps release schemas and shared root/operator input contracts.

No live catalog, admission, RBAC or cluster readiness is asserted by this check.
"""
import json
import os
from pathlib import Path
import subprocess
from urllib.request import urlopen

import hcl2
from hcl2.utils import SerializationOptions
import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[1]
RELEASES = {
    "1.20": ("7f18b149252aaabb8111003d8207e3b2b94fd7bc", "v3.3.12"),
    "1.21": ("bf0725b79530d763d7dd4aa99065d027df5ae940", "v3.4.4"),
}


def strict(schema):
    if isinstance(schema, dict):
        if schema.get("type") == "object" and "properties" in schema:
            if not schema.get("x-kubernetes-preserve-unknown-fields"):
                schema.setdefault("additionalProperties", False)
        for value in schema.values():
            strict(value)
    elif isinstance(schema, list):
        for value in schema:
            strict(value)


def schema(url, version):
    with urlopen(url, timeout=30) as response:
        crd = yaml.safe_load(response)
    result = next(v["schema"]["openAPIV3Schema"]["properties"]["spec"]
                  for v in crd["spec"]["versions"] if v["name"] == version)
    strict(result)
    return result


def read_hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def variables(path):
    value = read_hcl(path)
    return {name: spec for block in value.get("variable", []) for name, spec in block.items()}


def main():
    canonical = variables(ROOT / "modules/gitops-layers/operator/gitops-variables.tf")
    for path in [
        ROOT / "tests/gitops/gitops-variables.tf",
        *(ROOT / f"environments/{env}/gitops-variables.tf" for env in [
            "commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"]),
    ]:
        actual = variables(path)
        assert all(actual[name] == value for name, value in canonical.items()), path
        if path.parent.parent.name == "environments":
            root = read_hcl(path.parent / "main.tf")
            providers = {name: spec for block in root["provider"] for name, spec in block.items()}
            for name in ["kubernetes", "kubectl"]:
                assert providers[name]["insecure"] is False, (path, name)
                assert "var.gitops_cluster_ca_certificate" in providers[name]["cluster_ca_certificate"], path
            modules = {name: spec for block in root["module"] for name, spec in block.items()}
            for name in canonical:
                assert modules["gitops"][name] == "${var." + name + "}", (path, name)
            assert "supernovae/rosa-tf" not in modules["gitops"]["gitops_repo_url"], path
    identity = read_hcl(ROOT / "modules/gitops-layers/operator/identity.tf")
    resources = {(kind, name): spec for block in identity["resource"]
                 for kind, named in block.items() for name, spec in named.items()}
    assert resources[("kubernetes_service_account_v1", "terraform_operator")]["automount_service_account_token"] is False
    assert "gitops_create_legacy_token" in resources[("kubernetes_secret_v1", "terraform_operator_token")]["count"]
    checked = 0
    for release, (commit, argo) in RELEASES.items():
        schemas = {
            "ArgoCD": schema(f"https://raw.githubusercontent.com/redhat-developer/gitops-operator/{commit}/bundle/manifests/argoproj.io_argocds.yaml", "v1beta1"),
            "Application": schema(f"https://raw.githubusercontent.com/argoproj/argo-cd/{argo}/manifests/crds/application-crd.yaml", "v1alpha1"),
            "AppProject": schema(f"https://raw.githubusercontent.com/argoproj/argo-cd/{argo}/manifests/crds/appproject-crd.yaml", "v1alpha1"),
        }
        for config in [
            "{}",
            '{ha_enabled=true}',
            '{oidc_config="name: External SSO\\nissuer: https://id.example.test\\nclientID: gitops\\nclientSecret: $oidc-client-secret:clientSecret\\n"}',
        ]:
            result = subprocess.run(
                [os.environ.get("TERRAFORM_BIN", "terraform"), "-chdir=tests/gitops",
                 "console", f"-var=gitops_instance_config={config}"],
                input="jsonencode(local.manifests)\n", text=True, cwd=ROOT,
                capture_output=True, check=True,
            )
            for manifest in json.loads(json.loads(result.stdout)).values():
                if manifest["kind"] in schemas:
                    jsonschema.Draft7Validator(schemas[manifest["kind"]]).validate(manifest["spec"])
                    checked += 1
        print(f"PASS: GitOps {release} release schemas")
    print(f"PASS: {checked} specs and shared operator/four-root/test variable contracts")


if __name__ == "__main__":
    main()
