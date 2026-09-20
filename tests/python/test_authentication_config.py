"""Configuration and unavailable hardware must never remove every login route."""
import io
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from test_public_inventory import inventory
import auth_config


class AuthenticationConfigTests(unittest.TestCase):
    def read_config(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "config.toml"
            path.write_text(text)
            return inventory.load_authentication_config(path)

    def test_defaults_and_password_only(self):
        self.assertEqual(self.read_config(""), inventory.DEFAULT_AUTHENTICATION)
        settings = self.read_config('[authentication]\nface="off"\nfingerprint="off"')
        with mock.patch.object(auth_config.shutil, "which", side_effect=AssertionError("disabled probe")):
            self.assertEqual(inventory.authentication_capabilities("alpha", settings),
                             {"face": False, "fingerprint": False})

    def test_invalid_configuration_is_rejected(self):
        for text in ('[auth]\npassword=true', '[authentication]\npassword="false"',
                     '[authentication]\nface="enabled"', '[authentication]\nfingerprint=true',
                     '[authentication]\nprobe_timeout_seconds=0', '[authentication]\nprobe_timeout_seconds=true',
                     '[authentication]\nprobe_timeout_seconds=11', '[authentication]\nfingerprnt="on"',
                     '[authentication]\npassword=false\nface="off"\nfingerprint="off"'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.read_config(text)

    def test_missing_backends_are_optional(self):
        with mock.patch.object(auth_config.shutil, "which", return_value=None):
            self.assertEqual(inventory.authentication_capabilities("alpha", inventory.DEFAULT_AUTHENTICATION),
                             {"face": False, "fingerprint": False})

    def test_fingerprint_probe_handles_timeout_service_failure_and_localization(self):
        settings = inventory.DEFAULT_AUTHENTICATION | {"face": "off"}
        with mock.patch.object(auth_config.shutil, "which", return_value="/usr/bin/backend"):
            for failure in (subprocess.TimeoutExpired("fprintd-list", 3), OSError("unavailable")):
                with mock.patch.object(auth_config.subprocess, "run", side_effect=failure):
                    self.assertFalse(inventory.authentication_capabilities("alpha", settings)["fingerprint"])
            for code, output, expected in ((1, "- #0: right-index-finger", False),
                                            (0, "No devices available", False),
                                            (0, " - #0: right-index-finger", True)):
                with mock.patch.object(auth_config.subprocess, "run", return_value=
                                       subprocess.CompletedProcess([], code, output, "")) as probe:
                    self.assertEqual(inventory.authentication_capabilities("alpha", settings)["fingerprint"], expected)
                    self.assertEqual(probe.call_args.kwargs["timeout"], 3)
                    self.assertEqual(probe.call_args.kwargs["env"]["LC_ALL"], "C")

    def test_face_requires_camera_backend_and_account_enrollment(self):
        settings = inventory.DEFAULT_AUTHENTICATION | {"fingerprint": "off"}
        with mock.patch.object(auth_config.shutil, "which", return_value="/usr/bin/howrs"), \
             mock.patch.object(auth_config.glob, "glob", return_value=["/dev/video0"]):
            for enrolled in (True, False):
                with mock.patch.object(pathlib.Path, "is_file", return_value=enrolled):
                    self.assertEqual(inventory.authentication_capabilities("alpha", settings)["face"], enrolled)
            with mock.patch.object(pathlib.Path, "is_file", side_effect=PermissionError()):
                self.assertFalse(inventory.authentication_capabilities("alpha", settings)["face"])
        with mock.patch.object(auth_config.shutil, "which", return_value="/usr/bin/howrs"), \
             mock.patch.object(auth_config.glob, "glob", return_value=[]):
            self.assertFalse(inventory.authentication_capabilities("alpha", settings)["face"])

    def test_denied_fingerprint_probe_explains_omission(self):
        settings = inventory.DEFAULT_AUTHENTICATION | {"face": "off"}
        for code in (0, 1):
            result = subprocess.CompletedProcess([], code, "", "GDBus.Error: PermissionDenied: Not Authorized")
            with self.subTest(code=code), \
                 mock.patch.object(auth_config.shutil, "which", return_value="/usr/bin/backend"), \
                 mock.patch.object(auth_config.subprocess, "run", return_value=result), \
                 mock.patch.object(sys, "stderr", new_callable=io.StringIO) as errors, \
                 mock.patch.object(sys, "stdout", new_callable=io.StringIO) as output:
                self.assertFalse(inventory.authentication_capabilities("alpha", settings)["fingerprint"])
                self.assertIn("fprintd denied access", errors.getvalue())
                self.assertIn("docs/lockscreen.md#fingerprint-under-uwsm", errors.getvalue())
                self.assertEqual(output.getvalue(), "")

    def test_capabilities_are_per_account(self):
        users = [{"username": "alpha"}, {"username": "beta"}]
        with mock.patch.object(inventory, "authentication_capabilities", side_effect=[
                {"face": True, "fingerprint": False}, {"face": False, "fingerprint": True}]):
            resolved = inventory.configured_users(users, inventory.DEFAULT_AUTHENTICATION)
        self.assertTrue(resolved[0]["faceAuthenticationEnabled"])
        self.assertFalse(resolved[0]["fingerprintAuthenticationEnabled"])
        self.assertFalse(resolved[1]["faceAuthenticationEnabled"])
        self.assertTrue(resolved[1]["fingerprintAuthenticationEnabled"])

    def test_forced_on_requires_detected_method(self):
        with mock.patch.object(inventory, "authentication_capabilities", return_value={"face": False, "fingerprint": False}):
            for method in ("face", "fingerprint"):
                with self.subTest(method=method), self.assertRaisesRegex(ValueError, method + " is on"):
                    inventory.configured_users([{"username": "alpha"}], inventory.DEFAULT_AUTHENTICATION | {method: "on"})

    def test_password_off_requires_biometric_for_every_account(self):
        settings = inventory.DEFAULT_AUTHENTICATION | {"password": False}
        with mock.patch.object(inventory, "authentication_capabilities", side_effect=[
                {"face": True, "fingerprint": False}, {"face": False, "fingerprint": False}]), \
             self.assertRaisesRegex(ValueError, "Password is disabled"):
            inventory.configured_users([{"username": "alpha"}, {"username": "beta"}], settings)
        with mock.patch.object(inventory, "authentication_capabilities", return_value={"face": True, "fingerprint": False}):
            document = inventory.qml_document([{"username": "alpha"}], [], settings=settings)
            self.assertIn("passwordAuthenticationEnabled: false", document)

    def test_invalid_settings_preserve_existing_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            config = pathlib.Path(directory) / "invalid.toml"
            config.write_text('[authentication]\npassword="off"')
            output = pathlib.Path(directory) / "inventory.qml"
            output.write_text("existing release inventory")
            with mock.patch.object(sys, "argv", ["generate", "--config", str(config), "--output", str(output)]), \
                 mock.patch.object(inventory, "user_inventory", return_value=[{"username": "alpha"}]), \
                 mock.patch.object(inventory, "session_inventory", return_value=[{"id": "desktop"}]), \
                 mock.patch.object(sys, "stderr"), self.assertRaises(SystemExit) as error:
                inventory.main()
            self.assertEqual(error.exception.code, 2)
            self.assertEqual(output.read_text(), "existing release inventory")
