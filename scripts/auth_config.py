"""Authentication settings and enrolled-device discovery shared by both entry points."""
import glob
import os
import pathlib
import shutil
import subprocess
import sys
import tomllib

DEFAULT_AUTHENTICATION = {
    "password": True,
    "face": "auto",
    "fingerprint": "auto",
    "probe_timeout_seconds": 3,
}


def load_settings(path: pathlib.Path) -> dict[str, object]:
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    if set(document) - {"authentication"}:
        raise ValueError("Unknown config section; expected [authentication]")
    configured = document.get("authentication", {})
    if not isinstance(configured, dict):
        raise ValueError("authentication must be a TOML table")
    unknown = set(configured) - set(DEFAULT_AUTHENTICATION)
    if unknown:
        raise ValueError("Unknown authentication setting: " + ", ".join(sorted(unknown)))
    settings = DEFAULT_AUTHENTICATION | configured
    if type(settings["password"]) is not bool:
        raise ValueError("authentication.password must be true or false")
    for method in ("face", "fingerprint"):
        if settings[method] not in ("auto", "on", "off"):
            raise ValueError(f"authentication.{method} must be auto, on, or off")
    timeout = settings["probe_timeout_seconds"]
    if type(timeout) not in (int, float) or not 0.1 <= timeout <= 10:
        raise ValueError("probe_timeout_seconds must be a number between 0.1 and 10")
    if not settings["password"] and all(settings[m] == "off" for m in ("face", "fingerprint")):
        raise ValueError("At least one authentication method must be enabled")
    return settings


def authentication_capabilities(username: str, settings: dict[str, object]) -> dict[str, bool]:
    face = False
    if settings["face"] != "off" and shutil.which("howrs") and glob.glob("/dev/video*"):
        try:
            face = pathlib.Path("/var/lib/howrs", username, "faces.bin").is_file()
        except OSError:
            face = False
    fingerprint = False
    if settings["fingerprint"] != "off" and shutil.which("fprintd-list") and shutil.which("fprintd-verify"):
        try:
            result = subprocess.run(
                ["fprintd-list", username], capture_output=True, text=True,
                check=False, timeout=settings["probe_timeout_seconds"],
                env={**os.environ, "LC_ALL": "C"})
            fingerprint = result.returncode == 0 and "- #" in result.stdout
            output = result.stdout + result.stderr
            if "PermissionDenied" in output or "Not Authorized" in output:
                fingerprint = False
                print(f"Fingerprint unavailable for {username}: fprintd denied access. "
                      "For UWSM/user-service launches, see docs/lockscreen.md#fingerprint-under-uwsm.",
                      file=sys.stderr)
            elif result.returncode != 0:
                print(f"Fingerprint unavailable for {username}: fprintd-list failed "
                      f"with exit status {result.returncode}.", file=sys.stderr)
        except subprocess.TimeoutExpired:
            print(f"Fingerprint unavailable for {username}: fprintd-list timed out.", file=sys.stderr)
        except OSError as error:
            print(f"Fingerprint unavailable for {username}: cannot run fprintd-list: {error}.",
                  file=sys.stderr)
    return {"face": face, "fingerprint": fingerprint}
