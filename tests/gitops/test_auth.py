"""Offline tests; only synthetic credentials and fake HTTP responses are used."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BootstrapAuthTests(unittest.TestCase):
    def invoke(self, mode="", api="https://api.example.test:6443", oauth=""):
        with tempfile.TemporaryDirectory(prefix="gitops-auth-") as directory:
            executable = Path(directory) / "curl"
            shutil.copyfile(ROOT / "tests/gitops/curl-fixture.sh", executable)
            executable.chmod(0o700)
            value = subprocess.run(
                ["bash", str(ROOT / "modules/utility/cluster-auth/get-token.sh")],
                input=json.dumps({"api_url": api, "oauth_url": oauth,
                                  "username": "test-user", "password": 'test-"password\\'}),
                text=True, capture_output=True, check=True, timeout=10,
                env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                     "FAKE_MODE": mode, "OAUTH_MAX_RETRIES": "1"},
            )
            self.assertNotIn("test-user", value.stderr)
            self.assertNotIn("password", value.stderr)
            self.assertNotIn("test-token", value.stderr)
            return json.loads(value.stdout)

    def test_success(self):
        self.assertEqual(self.invoke()["token"], "test-token")

    def test_tls_failure(self):
        self.assertEqual(self.invoke("tls-failure")["authenticated"], "false")

    def test_bad_issuer(self):
        self.assertEqual(self.invoke("bad-issuer")["authenticated"], "false")

    def test_plain_http_api(self):
        self.assertEqual(self.invoke(api="http://api.example.test")["authenticated"], "false")

    def test_plain_http_override(self):
        self.assertEqual(self.invoke(oauth="http://oauth.example.test")["authenticated"], "false")

    def test_rejected_credentials(self):
        self.assertEqual(self.invoke("rejected")["authenticated"], "false")


if __name__ == "__main__":
    unittest.main()
