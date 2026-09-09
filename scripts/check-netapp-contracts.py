#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "python-hcl2==8.1.4"]
# ///
"""Check pinned certified release/API fields and four-root security contracts.

Trident CRDs preserve unknown fields, so CRD validation alone misses misspellings.
This checks rendered field names/types against the release's Go API definitions;
it is not a replacement for admission, backend authentication or live I/O tests.
"""
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.request import urlopen

import hcl2
from hcl2.utils import SerializationOptions
import yaml

ROOT = Path(__file__).resolve().parents[1]
CERTIFIED_COMMIT = "097b06e244849b605bc0f18f63edbcf83021afb8"
ENVS = ["commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"]


def fetch(url):
    with urlopen(url, timeout=30) as response:
        return response.read().decode()


def hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def blocks(value, kind):
    return {name: spec for block in value.get(kind, []) for name, spec in block.items()}


def fields(source, name):
    body = re.search(r"type " + name + r" struct \{(.*?)\n\}", source, re.S).group(1)
    return set(re.findall(r'json:"([^",]+)', body)) - {"-"}


def main():
    release = yaml.safe_load((ROOT / "gitops-layers/layers/netapp-storage/release.yaml").read_text())
    base = f"https://raw.githubusercontent.com/NetApp/trident/{release['tag']}"
    operator = fetch(f"{base}/operator/crd/apis/netapp/v1/types.go")
    drivers = fetch(f"{base}/storage_drivers/types.go")
    certified = f"https://raw.githubusercontent.com/redhat-openshift-ecosystem/certified-operators/{CERTIFIED_COMMIT}/operators/trident-operator/26.6.1"
    csv = yaml.safe_load(fetch(f"{certified}/manifests/{release['csv']}.clusterserviceversion.yaml"))
    annotations = yaml.safe_load(fetch(f"{certified}/metadata/annotations.yaml"))["annotations"]
    assert csv["metadata"]["name"] == release["csv"]
    assert release["channel"] in annotations["operators.operatorframework.io.bundle.channels.v1"].split(",")
    assert annotations["com.redhat.openshift.versions"] == "v4.14-v4.22"

    result = subprocess.run(
        [os.environ.get("TERRAFORM_BIN", "terraform"), "-chdir=tests/netapp", "console"],
        input="jsonencode(local.manifests)\n", text=True, capture_output=True, check=True, cwd=ROOT)
    manifests = json.loads(json.loads(result.stdout))
    assert set(manifests["orchestrator"]["spec"]) <= fields(operator, "TridentOrchestratorSpec")
    backend_fields = set().union(*(fields(drivers, name) for name in [
        "CommonStorageDriverConfig", "OntapStorageDriverConfig", "OntapStorageDriverPool"])) | {"deletionPolicy"}
    for name in ["nas", "san"]:
        spec = manifests[name]["spec"]
        assert set(spec) <= backend_fields, set(spec) - backend_fields
        assert set(spec["defaults"]) <= fields(drivers, "OntapStorageDriverConfigDefaults")
        assert all(isinstance(v, str) for v in spec["defaults"].values())
        assert spec["useREST"] is True and spec["deletionPolicy"] == "retain"
    canonical = blocks(hcl(ROOT / "tests/netapp/netapp-variables.tf"), "variable")
    infrastructure = blocks(hcl(ROOT / "modules/gitops-layers/netapp-storage/netapp-variables.tf"), "variable")
    for env in ENVS:
        actual = blocks(hcl(ROOT / f"environments/{env}/netapp-variables.tf"), "variable")
        assert actual == canonical | infrastructure, env
        root = blocks(hcl(ROOT / f"environments/{env}/main.tf"), "module")
        for name in canonical:
            assert root["gitops"][name] == "${var." + name + "}", (env, name)
        for name in infrastructure:
            assert root["gitops_resources"][name] == "${var." + name + "}", (env, name)
    actual_operator = blocks(hcl(ROOT / "modules/gitops-layers/operator/netapp-variables.tf"), "variable")
    assert all(actual_operator[name] == spec for name, spec in canonical.items())
    assert blocks(hcl(ROOT / "modules/gitops-layers/resources/netapp-variables.tf"), "variable") == infrastructure
    infra = hcl(ROOT / "modules/gitops-layers/netapp-storage/main.tf")
    assert not any(kind.startswith("aws_iam_") for block in infra["resource"] for kind in block)
    fsx = next(block["aws_fsx_ontap_file_system"]["this"] for block in infra["resource"] if "aws_fsx_ontap_file_system" in block)
    assert "local.second_generation ? null" in fsx["throughput_capacity"]
    assert fsx["lifecycle"][0]["prevent_destroy"] is True
    layer = hcl(ROOT / "modules/gitops-layers/operator/layer-netapp-storage.tf")
    resources = {(kind, name): spec for block in layer["resource"]
                 for kind, names in block.items() for name, spec in names.items()}
    secret = resources[("kubernetes_secret_v1", "trident_backend_credentials")]
    assert secret["data"] == {"username": "vsadmin", "password": "${var.fsx_admin_password}"}
    assert "backend_secret_name" in secret["count"]
    checks = resources[("kubectl_manifest", "trident_subscription")]["lifecycle"][0]["precondition"]
    assert any("trusted_ca_pem" in check["condition"] for check in checks)
    assert any("node_prep_iscsi" in check["condition"] for check in checks)
    assert any("use_chap" in check["condition"] for check in checks)
    for path in (ROOT / "examples/netapp").glob("*.yaml"):
        for obj in yaml.safe_load_all(path.read_text()):
            assert obj["apiVersion"] and obj["kind"] and obj["metadata"]["name"], path
            if obj["kind"] == "PersistentVolumeClaim":
                assert obj["spec"]["storageClassName"] in ["fsx-ontap-nfs-retain", "fsx-ontap-san-retain"], path
                assert obj["spec"]["volumeMode"] == "Filesystem", path
            if obj["kind"] == "VirtualMachine":
                assert obj["spec"]["runStrategy"] == "Halted", path
                disk = obj["spec"]["dataVolumeTemplates"][0]["spec"]["storage"]
                assert disk["volumeMode"] == "Block" and disk["accessModes"] == ["ReadWriteMany"], path
                assert disk["storageClassName"] == "fsx-ontap-vm-rwx", path
    print("PASS: certified Trident release, rendered API fields, credentials and four-root contracts")


if __name__ == "__main__":
    main()
