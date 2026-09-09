#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "jsonschema==4.23.0", "python-hcl2==8.1.4"]
# ///
"""Validate rendered HCO schemas, CDI API fields and integration contracts.
Upstream schemas are API regression checks, not downstream support certification.
Live admission and storage acceptance remain mandatory.
"""
import json
import os
import re
from pathlib import Path
import subprocess
from urllib.request import urlopen

import hcl2
from hcl2.utils import SerializationOptions
import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[1]
REVISIONS = {
    18: "0de387593e52fc2cbbe23d518ad79f80d71a134f",
    19: "6c94fbddedf38061ee63d9d33b6802d8bb41d1b3",
    22: "8e15ece34163853432aa28bb6cb00966a19c6bd9",
}


def fetch_crds(revision, filename):
    url = f"https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/{revision}/deploy/crds/{filename}"
    with urlopen(url, timeout=60) as response:
        docs = list(yaml.safe_load_all(response))
    return [item for doc in docs if doc for item in (doc.get("items", []) if doc.get("kind") == "List" else [doc])]


def strict_properties(schema):
    if isinstance(schema, dict):
        if schema.get("type") == "object" and "properties" in schema and not schema.get("x-kubernetes-preserve-unknown-fields"):
            schema.setdefault("additionalProperties", False)
        for value in list(schema.values()):
            strict_properties(value)
    elif isinstance(schema, list):
        for item in schema:
            strict_properties(item)


def validate(obj, crds):
    crd = next(c for c in crds if c.get("kind") == "CustomResourceDefinition" and c["spec"]["names"]["kind"] == obj["kind"])
    schema = next(v["schema"]["openAPIV3Schema"] for v in crd["spec"]["versions"] if v["name"] == obj["apiVersion"].split("/")[1])
    # Kubernetes validates ObjectMeta separately; CRDs may constrain only its name.
    strict_properties(schema["properties"]["spec"])
    jsonschema.Draft7Validator(schema).validate(obj)


def hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def blocks(data, kind):
    return {name: spec for block in data.get(kind, []) for name, spec in block.items()}


def main():
    tf = os.environ.get("TERRAFORM_BIN", "terraform")
    for minor, revision in REVISIONS.items():
        result = subprocess.run([tf, "-chdir=tests/virtualization", "console", f"-var=ocp_minor={minor}"],
                                input="jsonencode(local.manifests)\n", text=True, capture_output=True, check=True, cwd=ROOT)
        manifests = json.loads(json.loads(result.stdout))
        validate(manifests["hco"], fetch_crds(revision, "hco00.crd.yaml"))
        url = f"https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/{revision}/vendor/kubevirt.io/containerized-data-importer-api/pkg/apis/core/v1beta1/types.go"
        with urlopen(url, timeout=60) as response:
            cdi = response.read().decode()
        def fields(name):
            body = re.search(r"type " + name + r" struct \{(.*?)\n\}", cdi, re.S).group(1)
            return set(re.findall(r'json:"([^",]+)', body))
        for name in ("san", "nfs"):
            spec = manifests[name]["spec"]
            assert set(spec) <= fields("StorageProfileSpec")
            assert set(spec["claimPropertySets"][0]) <= fields("ClaimPropertySet")
            assert spec["cloneStrategy"] == "csi-clone"
    canonical = blocks(hcl(ROOT / "tests/virtualization/virtualization-variables.tf"), "variable")
    for directory in ["modules/gitops-layers/operator"] + [f"environments/{e}" for e in
            ["commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"]]:
        assert blocks(hcl(ROOT / directory / "virtualization-variables.tf"), "variable") == canonical, directory
        if directory.startswith("environments/"):
            assert blocks(hcl(ROOT / directory / "main.tf"), "module")["gitops"]["virt_config"] == "${var.virt_config}"
    layer = hcl(ROOT / "modules/gitops-layers/operator/layer-virtualization.tf")
    resources = {(kind, name): spec for block in layer["resource"]
                 for kind, names in block.items() for name, spec in names.items()}
    hco = resources[("kubectl_manifest", "virt_hyperconverged")]
    assert hco["apply_only"] and not hco["force_conflicts"]
    assert {c["type"]: c["status"] for c in hco["wait_for"][0]["condition"]} == {
        "Available": "True", "Degraded": "False", "Progressing": "False"}
    namespace = resources[("kubernetes_namespace_v1", "virtualization")]
    assert namespace["lifecycle"][0]["prevent_destroy"]
    assert any("platform_support_confirmed" in p["condition"]
               for p in namespace["lifecycle"][0]["precondition"])
    subscription = resources[("kubectl_manifest", "virt_subscription")]
    installed = subscription["wait_for"][0]["field"][0]
    assert installed["key"] == "status.installedCSV" and "local.ocp_minor_version" in installed["value"]
    profile = resources[("kubectl_manifest", "virt_netapp_storage_profile")]
    assert "netapp_storage_class" in str(profile["depends_on"])
    assert "netapp_snapshot_class_retain" in str(profile["depends_on"])
    assert profile["apply_only"] and not profile["force_conflicts"]
    assert "enable_layer_virtualization" in profile["for_each"]
    for name in ("netapp", "virtualization"):
        for path in (ROOT / "examples" / name).glob("*.yaml"):
            for obj in yaml.safe_load_all(path.read_text()):
                if obj and obj["kind"] == "VirtualMachine":
                    assert obj["spec"]["runStrategy"] == "Halted"
                    disk = obj["spec"]["dataVolumeTemplates"][0]["spec"]["storage"]
                    assert disk["storageClassName"] == "fsx-ontap-vm-rwx"
                    assert disk["volumeMode"] == "Block" and disk["accessModes"] == ["ReadWriteMany"]
                    placement = obj["spec"]["template"]["spec"]
                    assert placement["nodeSelector"]["kubernetes.io/arch"] == "amd64"
                    assert any(t["effect"] == "NoSchedule" for t in placement["tolerations"])
    print("PASS: HCO schemas, CDI API fields, retained storage/readiness and four-root contracts")


if __name__ == "__main__":
    main()
