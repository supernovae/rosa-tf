#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["PyYAML==6.0.2", "jsonschema==4.23.0"]
# ///
"""Render both partitions/architectures and check pinned Red Hat release CRDs.

Static schemas do not test CEL, admission, catalog availability or live readiness.
"""
import json
import os
from pathlib import Path
import subprocess
from urllib.request import urlopen

import jsonschema
import yaml

class CRDLoader(yaml.SafeLoader):
    """Treat YAML 1.1's bare '=' token as a string in Kubernetes enum lists."""


CRDLoader.add_constructor("tag:yaml.org,2002:value",
                         lambda loader, node: loader.construct_scalar(node))

ROOT = Path(__file__).resolve().parents[1]
RELEASES = {
    "6.2": ("4662a11ef072098fa5decaab0a78837f61907e95", "cd5eefc1d5853920fdaddde76e462020a1fe637f"),
    "6.5": ("645d0009492a0e2cbeb0d3ebdbf0e03ed49469e7", "163953346b3e4a226ac03c0e72d35a03a1222c93"),
    "6.6": ("7560420af4e2da6fff021d6bb2fc0b1d91ad052c", "678e5e8f46311c6dd591e105117f4616a0cc82b1"),
}
COO = "https://raw.githubusercontent.com/rhobs/observability-operator/e5f9cd04a2eb1e254764b9062fb6bf06efd7f20e/deploy/crds/common/observability.openshift.io_uiplugins.yaml"
# OpenShift CMO release-4.18 uses monitoring APIs v0.76.0.
PROMETHEUS = "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.76.0/example/prometheus-operator-crd"


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
        crd = yaml.load(response, Loader=CRDLoader)
    result = next(v["schema"]["openAPIV3Schema"]["properties"]["spec"]
                  for v in crd["spec"]["versions"] if v["name"] == version)
    strict(result)
    return result


def main():
    ui = schema(COO, "v1alpha1")
    rendered = []
    for region in ["us-east-1", "us-gov-west-1"]:
        for arm in ["true", "false"]:
            result = subprocess.run(
                [os.environ.get("TERRAFORM_BIN", "terraform"), "-chdir=tests/monitoring",
                 "console", f"-var=region={region}", f"-var=arm={arm}"],
                input="jsonencode(local.manifests)\n", text=True, cwd=ROOT,
                capture_output=True, check=True,
            )
            rendered.append(json.loads(json.loads(result.stdout)))
    checked = 0
    for release, (logging, loki) in RELEASES.items():
        schemas = {
            "ClusterLogForwarder": schema(f"https://raw.githubusercontent.com/openshift/cluster-logging-operator/{logging}/bundle/manifests/observability.openshift.io_clusterlogforwarders.yaml", "v1"),
            "LokiStack": schema(f"https://raw.githubusercontent.com/openshift/loki/{loki}/operator/config/crd/bases/loki.grafana.com_lokistacks.yaml", "v1"),
            "UIPlugin": ui,
        }
        for manifests in rendered:
            for manifest in manifests.values():
                jsonschema.Draft7Validator(schemas[manifest["kind"]]).validate(manifest["spec"])
                checked += 1
        print(f"PASS: Logging/Loki {release} and COO 1.5 release schemas")
    print(f"PASS: {checked} rendered specs; both partitions and ARM/default placement")
    examples = {
        "ServiceMonitor": ("monitoring.coreos.com_servicemonitors.yaml", "v1"),
        "PrometheusRule": ("monitoring.coreos.com_prometheusrules.yaml", "v1"),
        "AlertmanagerConfig": ("monitoring.coreos.com_alertmanagerconfigs.yaml", "v1alpha1"),
    }
    example_schemas = {kind: schema(f"{PROMETHEUS}/{path}", version)
                       for kind, (path, version) in examples.items()}
    for path in (ROOT / "examples/observability").glob("*.yaml"):
        for manifest in yaml.safe_load_all(path.read_text()):
            if manifest["kind"] in example_schemas:
                jsonschema.Draft7Validator(example_schemas[manifest["kind"]]).validate(manifest["spec"])
    print("PASS: application scrape/rule/receiver examples match the OpenShift 4.18 API baseline")


if __name__ == "__main__":
    main()
