#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "jsonschema==4.23.0", "python-hcl2==8.1.4"]
# ///
"""Validate OADP/Velero schemas, STS ownership and four-root backup contracts.
Pinned maintained-branch schemas are API checks, not proof of catalog availability
or live backup/restore correctness. Kubernetes admission/CEL still must be tested.
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
LAYER = ROOT / "gitops-layers/layers/oadp"


def hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def blocks(value, kind):
    return {name: spec for block in value.get(kind, []) for name, spec in block.items()}


def fetch(revision, path):
    url = f"https://raw.githubusercontent.com/openshift/oadp-operator/{revision}/{path}"
    with urlopen(url, timeout=60) as response:
        return response.read().decode()


def strict(schema):
    if isinstance(schema, dict):
        if schema.get("type") == "object" and "properties" in schema and not schema.get("x-kubernetes-preserve-unknown-fields"):
            schema.setdefault("additionalProperties", False)
        for value in list(schema.values()):
            strict(value)
    elif isinstance(schema, list):
        for value in schema:
            strict(value)


def validate(obj, crd):
    version = obj["apiVersion"].split("/")[-1]
    schema = next(v["schema"]["openAPIV3Schema"] for v in crd["spec"]["versions"] if v["name"] == version)
    strict(schema["properties"]["spec"])
    jsonschema.Draft7Validator(schema).validate(obj)


def main():
    releases = yaml.safe_load((LAYER / "release.yaml").read_text())
    for stream, release in releases["streams"].items():
        minor = release["openshift_minors"][-1]
        result = subprocess.run([
            os.environ.get("TERRAFORM_BIN", "terraform"), "-chdir=tests/oadp", "console",
            f"-var=openshift_version=4.{minor}.0", "-var=virtualization_enabled=true"
        ], input="jsonencode(local.manifests)\n", text=True, capture_output=True, check=True, cwd=ROOT)
        manifests = json.loads(json.loads(result.stdout))
        for name, filename in [
            ("dpa", "oadp.openshift.io_dataprotectionapplications.yaml"),
            ("schedule", "velero.io_schedules.yaml")
        ]:
            crd = yaml.safe_load(fetch(release["schema_commit"], "bundle/manifests/" + filename))
            validate(manifests[name], crd)
        for name, filename in [("Backup", "velero.io_backups.yaml"), ("Restore", "velero.io_restores.yaml")]:
            crd = yaml.safe_load(fetch(release["schema_commit"], "bundle/manifests/" + filename))
            path = ROOT / "examples/oadp" / ("backup-vms.yaml" if name == "Backup" else "restore-vms.yaml")
            validate(yaml.safe_load(path.read_text()), crd)
        sts = fetch(release["schema_commit"], "pkg/credentials/stsflow/stsflow.go")
        assert 'RoleARNEnvKey = "ROLEARN"' in sts
        assert 'AWSSecretCredentialsKey = "credentials"' in sts
        csv = yaml.safe_load(fetch(release["schema_commit"], "bundle/manifests/oadp-operator.clusterserviceversion.yaml"))
        assert "audience: openshift" in yaml.safe_dump(csv)
        config = manifests["dpa"]["spec"]["configuration"]
        assert config["velero"]["disableFsBackup"]
        assert config["velero"]["defaultSnapshotMoveData"]
        assert "kubevirt" in config["velero"]["defaultPlugins"]
        assert manifests["dpa"]["spec"]["backupImages"] is False
        assert not any(k in manifests["dpa"]["spec"] for k in ("snapshotLocations", "features", "unsupportedOverrides"))
        assert "restic" not in config
    canonical = blocks(hcl(ROOT / "tests/oadp/oadp-variables.tf"), "variable")["oadp_config"]
    for env in ["commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"]:
        assert blocks(hcl(ROOT / f"environments/{env}/oadp-variables.tf"), "variable")["oadp_config"] == canonical, env
        root = blocks(hcl(ROOT / f"environments/{env}/main.tf"), "module")
        assert root["gitops"]["oadp_config"] == "${var.oadp_config}"
    operator = blocks(hcl(ROOT / "modules/gitops-layers/operator/oadp-variables.tf"), "variable")["oadp_config"]
    assert {k: v for k, v in operator.items() if k != "validation"} == {k: v for k, v in canonical.items() if k != "validation"}
    layer = hcl(ROOT / "modules/gitops-layers/operator/layer-oadp.tf")
    resources = {(kind, name): spec for block in layer["resource"]
                 for kind, names in block.items() for name, spec in names.items()}
    assert ("kubectl_manifest", "oadp_cloud_credentials") not in resources
    assert any("oadp_cloud_credentials" in r["from"] and r["lifecycle"][0]["destroy"] is False for r in layer["removed"])
    assert resources[("kubernetes_namespace_v1", "oadp")]["lifecycle"][0]["prevent_destroy"]
    assert resources[("kubectl_manifest", "oadp_dpa")]["apply_only"]
    assert "virt_hyperconverged" in str(resources[("kubectl_manifest", "oadp_dpa")]["depends_on"])
    assert "schedule_enabled" in resources[("kubectl_manifest", "oadp_schedule")]["count"]
    assert all(not spec.get("force_conflicts", False) for (kind, _), spec in resources.items() if kind == "kubectl_manifest")
    aws = hcl(ROOT / "modules/gitops-layers/oadp/main.tf")
    policies = next(d["aws_iam_policy_document"]["oadp"] for d in aws["data"] if "oadp" in d.get("aws_iam_policy_document", {}))
    assert all(not a.startswith("ec2:") for s in policies["statement"] for a in s["actions"])
    assert any(s["resources"] == ["${local.bucket_arn}/velero/*"] for s in policies["statement"])
    aws_source = (ROOT / "modules/gitops-layers/oadp/main.tf").read_text()
    assert "ExpirationInDays" not in aws_source and "NoncurrentVersionExpiration" not in aws_source
    assert "local-exec" not in aws_source
    snapshot = yaml.safe_load((LAYER / "netapp-volumesnapshotclass.yaml").read_text())
    assert snapshot["driver"] == "csi.trident.netapp.io" and snapshot["deletionPolicy"] == "Delete"
    assert snapshot["metadata"]["labels"] == {"velero.io/csi-volumesnapshot-class": "true"}
    restore = yaml.safe_load((ROOT / "examples/oadp/restore-vms.yaml").read_text())
    assert restore["metadata"]["labels"]["velero.kubevirt.io/restore-run-strategy"] == "Halted"
    assert restore["spec"]["existingResourcePolicy"] == "none"
    print("PASS: OADP/Velero schemas, STS flow, scoped backup/recovery and four-root contracts")


if __name__ == "__main__":
    main()
