#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "python-hcl2==8.1.4"]
# ///
"""EFS source, template, identity, retention and four-root integration contracts.

Pinned source checks do not prove catalog availability or live AWS/NFS behavior.
"""
import json
import os
from pathlib import Path
import subprocess
from urllib.request import urlopen

import hcl2
from hcl2.utils import SerializationOptions
import yaml

ROOT = Path(__file__).resolve().parents[1]
LAYER = ROOT / "gitops-layers/layers/efs-storage"


def hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def blocks(doc, kind):
    return {name: value for block in doc.get(kind, []) for name, value in block.items()}


def source(revision, path):
    with urlopen(f"https://raw.githubusercontent.com/openshift/csi-operator/{revision}/{path}", timeout=45) as response:
        return response.read().decode()


def main():
    release = yaml.safe_load((LAYER / "release.yaml").read_text())
    rendered = subprocess.check_output(
        [os.environ.get("TERRAFORM_BIN", "terraform"), "-chdir=tests/efs", "console"],
        cwd=ROOT, input="jsonencode(local.manifests)\n", text=True)
    manifests = json.loads(json.loads(rendered))
    sc = manifests["storageclass"]
    assert sc["mountOptions"] == ["tls"] and sc["reclaimPolicy"] == "Retain"
    assert sc["parameters"]["provisioningMode"] == "efs-ap"
    assert int(sc["parameters"]["gidRangeStart"]) > 0
    assert "allowVolumeExpansion" not in sc
    assert manifests["driver"]["spec"] == {"managementState": "Managed"}
    for version, revision in release["source_contracts"].items():
        csv = yaml.safe_load(source(revision, "config/aws-efs/manifests/stable/aws-efs-csi-driver-operator.clusterserviceversion.yaml"))
        assert csv["metadata"]["name"].startswith(f"aws-efs-csi-driver-operator.v{version}.")
        controller = yaml.safe_load(source(revision, "assets/overlays/aws-efs/generated/standalone/controller.yaml"))
        assert controller["spec"]["template"]["spec"]["serviceAccount"] == "aws-efs-csi-driver-controller-sa"
        assert any(p.get("serviceAccountToken", {}).get("audience") == "openshift"
                   for v in controller["spec"]["template"]["spec"]["volumes"]
                   for p in v.get("projected", {}).get("sources", []))
        implementation = source(revision, "pkg/driver/aws-efs/aws_efs.go")
        assert '"ROLEARN"' in implementation and '"aws-efs-cloud-credentials"' in implementation

    canonical = blocks(hcl(ROOT / "modules/gitops-layers/operator/efs-variables.tf"), "variable")["efs_config"]
    for env in ["commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp"]:
        directory = ROOT / "environments" / env
        assert blocks(hcl(directory / "efs-variables.tf"), "variable")["efs_config"] == canonical
        modules = blocks(hcl(directory / "main.tf"), "module")
        for name in ["gitops", "gitops_resources"]:
            assert modules[name]["enable_layer_efs_storage"] == "${var.enable_layer_efs_storage}"
            assert modules[name]["efs_config"] == "${var.efs_config}"
        assert modules["gitops"]["efs_storage_class_name"] == "${var.efs_storage_class_name}"
        assert "efs_file_system_id" in modules["gitops"] and "efs_role_arn" in modules["gitops"]
    operator = hcl(ROOT / "modules/gitops-layers/operator/layer-efs-storage.tf")
    resources = {(kind, name): spec for block in operator["resource"]
                 for kind, names in block.items() for name, spec in names.items()}
    assert ("kubernetes_secret_v1", "efs_csi_credentials") not in resources
    assert any("efs_csi_credentials" in b["from"] and not b["lifecycle"][0]["destroy"] for b in operator["removed"])
    assert all(not spec.get("force_conflicts", False) and spec["apply_only"]
               for (kind, _), spec in resources.items() if kind == "kubectl_manifest")
    assert "wait_for" in resources[("kubectl_manifest", "efs_cluster_csi_driver")]
    aws = hcl(ROOT / "modules/gitops-layers/efs-storage/main.tf")
    assert blocks(aws, "resource")["aws_efs_file_system"]["this"]["lifecycle"][0]["prevent_destroy"]
    outputs = blocks(hcl(ROOT / "modules/gitops-layers/efs-storage/outputs.tf"), "output")
    assert "aws_efs_mount_target.this" in str(outputs["efs_file_system_id"]["depends_on"])
    assert "aws_iam_role_policy_attachment.efs_csi" in str(outputs["efs_role_arn"]["depends_on"])
    monitoring = (ROOT / "modules/gitops-layers/operator/layer-monitoring.tf").read_text()
    assert "EFS/NFS" in monitoring and "var.efs_storage_class_name" in monitoring
    print("PASS: EFS source, STS ownership, retained TLS storage and four-root dependency contracts")


if __name__ == "__main__":
    main()
