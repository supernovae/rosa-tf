#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["python-hcl2==8.1.4"]
# ///
"""Fail on unreviewed RHCS schema additions/removals/types or wrapper drift."""
import json
import os
from pathlib import Path
import subprocess

import hcl2
from hcl2.utils import SerializationOptions

ROOT = Path(__file__).resolve().parents[1]


def hcl(path):
    with path.open() as stream:
        return hcl2.load(stream, serialization_options=SerializationOptions(
            with_comments=False, explicit_blocks=False, strip_string_quotes=True))


def writable_fields(attributes, prefix=""):
    result = {}
    for name, value in attributes.items():
        if not (value.get("optional") or value.get("required")):
            continue
        key = prefix + name
        result[key] = value.get("type", value.get("nested_type", {}).get("nesting_mode"))
        if "nested_type" in value:
            result.update(writable_fields(value["nested_type"]["attributes"], key + "."))
    return result


def main():
    audit = json.loads((ROOT / "docs/rhcs-capabilities.json").read_text())
    status = json.loads((ROOT / "release-status.json").read_text())
    assert audit["rhcs_version"] == status["rhcs_version"], "Review inventory on provider upgrades"
    provider = json.loads(subprocess.check_output([
        os.environ.get("TERRAFORM_BIN", "terraform"),
        "-chdir=modules/cluster/rosa-hcp", "providers", "schema", "-json"
    ], cwd=ROOT, text=True))["provider_schemas"]["registry.terraform.io/terraform-redhat/rhcs"]
    schema = provider["resource_schemas"]
    data_sources = provider["data_source_schemas"]
    assert set(data_sources) == set(audit["data_sources"]), "Provider data-source inventory changed"
    for kind, source in data_sources.items():
        record = audit["data_sources"][kind]
        assert record["disposition"], kind
        assert writable_fields(source["block"]["attributes"]) == record["input_fields"], f"Unreviewed data-source change: {kind}"
    assert set(schema) == set(audit["resources"]), "Provider resource inventory changed"
    for kind, resource in schema.items():
        record = audit["resources"][kind]
        assert record["disposition"], kind
        assert writable_fields(resource["block"]["attributes"]) == record["writable_fields"], f"Unreviewed schema change: {kind}"
    core = {
        "rhcs_cluster_rosa_classic": ("rosa-classic", "this"),
        "rhcs_cluster_rosa_hcp": ("rosa-hcp", "this"),
        "rhcs_machine_pool": ("machine-pools", "pool"),
        "rhcs_hcp_machine_pool": ("machine-pools-hcp", "pool"),
    }
    for kind, (module, name) in core.items():
        source = hcl(ROOT / "modules/cluster" / module / "main.tf")
        resources = {(k, n): value for block in source["resource"] for k, named in block.items() for n, value in named.items()}
        configured = resources[kind, name]
        native = {key for key, value in schema[kind]["block"]["attributes"].items() if value.get("optional") or value.get("required")}
        # Native admin_credentials implements the existing named bootstrap contract;
        # do not expose a second competing provider-generated admin switch.
        exceptions = {"create_admin_user"} if module.startswith("rosa-") else set()
        assert native - configured.keys() == exceptions, (kind, native - configured.keys())
        if module.startswith("rosa-"):
            ignored = configured.get("lifecycle", [{}])[0].get("ignore_changes", [])
            assert not any(field in str(ignored) for field in ("version", "auto_node")), "Do not hide native upgrade or AutoNode requests"
            arch = module.removeprefix("rosa-")
            canonical = (ROOT / "modules/cluster" / module / "native-options.tf").read_text()
            for partition in ("commercial", "govcloud"):
                assert (ROOT / "environments" / f"{partition}-{arch}" / "native-options.tf").read_text() == canonical, "Native option copies drifted"
        else:
            assert configured["ignore_deletion_error"] is False, kind
            arch = "hcp" if module.endswith("-hcp") else "classic"
            def pool_type(path):
                return next(block["machine_pools"]["type"] for block in hcl(path)["variable"] if "machine_pools" in block)
            canonical_type = pool_type(ROOT / "modules/cluster" / module / "variables.tf")
            for partition in ("commercial", "govcloud"):
                assert pool_type(ROOT / "environments" / f"{partition}-{arch}" / "variables.tf") == canonical_type, f"{partition}-{arch}: machine-pool input type drifted"
    print(f"PASS: {len(schema)} RHCS resources, {len(data_sources)} data sources and input field/type inventories reviewed; four core wrappers wired")


if __name__ == "__main__":
    main()
