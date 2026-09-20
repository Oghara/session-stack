"""Keep host identity out of the distributable source and demo."""
import importlib.util
import pathlib
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

PROJECT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = PROJECT / "scripts/generate-system-data.py"
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts"))
spec = importlib.util.spec_from_file_location("inventory", SCRIPT)
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class PublicInventoryTests(unittest.TestCase):
    def test_demo_never_discovers_accounts_sessions_or_biometrics(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / "GeneratedSystemData.qml"
            with mock.patch.object(sys, "argv", [str(SCRIPT), "--demo", "--output", str(target)]), \
                 mock.patch.object(inventory, "user_inventory", side_effect=AssertionError("host accounts read")), \
                 mock.patch.object(inventory, "session_inventory", side_effect=AssertionError("host sessions read")), \
                 mock.patch.object(inventory, "authentication_capabilities", side_effect=AssertionError("hardware read")):
                self.assertEqual(inventory.main(), 0)
            self.assertEqual(target.read_text(), inventory.DEFAULT_OUTPUT.read_text())
            self.assertIn("isDemo: true", target.read_text())

    def test_host_inventory_requires_external_destination(self):
        for args in ([], ["--output", str(inventory.DEFAULT_OUTPUT)]):
            result = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("source tree", result.stderr)

    def test_demo_check_detects_accidental_personalization(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / "GeneratedSystemData.qml"
            target.write_text(inventory.DEFAULT_OUTPUT.read_text().replace('"operator"', '"private-account"'))
            result = subprocess.run([sys.executable, str(SCRIPT), "--demo", "--check", "--output", str(target)], capture_output=True)
            self.assertEqual(result.returncode, 1)

    def test_live_mode_rejects_demo_inventory_and_exits(self):
        environment = os.environ.copy()
        environment.pop("GREETD_SOCK", None)
        environment.update(QT_QPA_PLATFORM="offscreen", SESSION_STACK_GREETER_MODE="live")
        result = subprocess.run(
            ["quickshell", "--no-duplicate", "--path", str(PROJECT / "quickshell/session-stack-greeter")],
            env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Live mode refused: stage a host inventory first", result.stdout + result.stderr)
