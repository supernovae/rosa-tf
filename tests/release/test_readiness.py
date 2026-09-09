"""Offline release gate tests: never create a tag or contact a cloud API."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("readiness", ROOT / "scripts/check-release-ready.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.ready = dict(target_version="2.0.0", rhcs_version="1.7.8",
                          status="ready", release_approved=True)

    def test_explicit_stable_approval(self):
        gate.check("v2.0.0", self.ready)

    def test_prerelease_blocked_even_when_approved(self):
        with self.assertRaises(ValueError):
            gate.check("v2.0.0", {**self.ready, "rhcs_version": "1.7.8-prerelease.2"})

    def test_missing_approval_blocked(self):
        with self.assertRaises(ValueError):
            gate.check("v2.0.0", {**self.ready, "release_approved": False})

    def test_development_blocked(self):
        with self.assertRaises(ValueError):
            gate.check("v2.0.0", {**self.ready, "status": "development"})

    def test_other_tag_blocked(self):
        for tag in ("v2.0.1", "v2.0.0-rc.1", "v2.0.0;echo bad", "2.0.0"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                gate.check(tag, self.ready)

    def test_checked_in_provider_matches_metadata(self):
        gate.check_provider_files(json.loads((ROOT / "release-status.json").read_text()))

    def test_metadata_cannot_hide_other_provider(self):
        with self.assertRaises(ValueError):
            gate.check_provider_files({**self.ready, "rhcs_version": "0.0.0"})
