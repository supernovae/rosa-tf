"""Guard the shared deployment posture, not live service availability."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
TARGETS = ("commercial-classic", "commercial-hcp", "govcloud-classic", "govcloud-hcp")


class SafetyDefaults(unittest.TestCase):
    def test_layer_opt_in_and_security_defaults(self):
        for target in TARGETS:
            sources = "\n".join(p.read_text() for p in (ROOT / "environments" / target).glob("*.tf"))
            blocks = dict(re.findall(r'^variable "([^\"]+)" (\{[\s\S]*?^\})', sources, re.M))
            for name, block in blocks.items():
                if name.startswith("enable_layer_") or name == "install_gitops":
                    self.assertRegex(block, r'default\s*=\s*false', (target, name))
            for name in ("cluster_delete_protection", "efs_encrypted", "certmanager_enable_dnssec", "create_oidc_config"):
                if name in blocks:
                    self.assertRegex(blocks[name], r'default\s*=\s*true', (target, name))

    def test_seed_posture(self):
        for target in TARGETS:
            for tier in ("dev", "prod"):
                seed = (ROOT / "environments" / target / f"cluster-{tier}.tfvars").read_text()
                for name in ("private_cluster", "cluster_delete_protection", "etcd_encryption"):
                    self.assertRegex(seed, rf'(?m)^{name}\s*=\s*true')
                self.assertNotRegex(seed, r'(?m)^openshift_version\s*=')
                if target == "govcloud-hcp":
                    self.assertRegex(seed, r'(?m)^zero_egress\s*=\s*true')

    def test_no_forced_field_takeover(self):
        for path in (ROOT / "modules/gitops-layers/operator").glob("*.tf"):
            self.assertNotRegex(path.read_text(), r'force_conflicts\s*=\s*true', str(path))

    def test_actions_are_immutable(self):
        for path in (ROOT / ".github/workflows").glob("*.yml"):
            for ref in re.findall(r'uses:\s*([^\s#]+)', path.read_text()):
                self.assertRegex(ref, r'@[a-f0-9]{40}$', str(path))

    def test_cleanup_is_read_only(self):
        source = (ROOT / "scripts/vpc-cleanup.sh").read_text()
        self.assertNotRegex(source, r'aws\s+ec2\s+(delete|revoke|detach|terminate)-')
