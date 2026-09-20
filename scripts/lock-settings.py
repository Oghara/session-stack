#!/usr/bin/env python3
"""Resolve this account's enabled methods before starting QuickShell."""
import argparse
import os
from pathlib import Path
import pwd

from auth_config import authentication_capabilities, load_settings


def resolve(profile, preview=False):
    project = Path(__file__).resolve().parents[1]
    if profile:
        profiles = {
            "password": ["password"],
            "password-face": ["password", "face"],
            "password-fingerprint": ["password", "fingerprint"],
            "all": ["password", "face", "fingerprint"],
            "face": ["face"],
            "fingerprint": ["fingerprint"],
        }
        if profile not in profiles:
            raise ValueError("Unknown authentication profile: " + profile)
        methods = profiles[profile]
        settings = {"password": "password" in methods, "probe_timeout_seconds": 3,
                    "face": "on" if "face" in methods else "off",
                    "fingerprint": "on" if "fingerprint" in methods else "off"}
    else:
        local = project / "lock.local.toml"
        settings = load_settings(local if local.exists() else project / "lock.toml")
    if preview:
        capabilities = {method: settings[method] != "off" for method in ("face", "fingerprint")}
    else:
        username = pwd.getpwuid(os.getuid()).pw_name
        capabilities = authentication_capabilities(username, settings)
    methods = ["password"] if settings["password"] else []
    for method in ("face", "fingerprint"):
        if settings[method] == "on" and not capabilities[method]:
            raise ValueError(method + " requires a detected backend, device and enrollment")
        if capabilities[method]:
            methods.append(method)
    if not methods:
        raise ValueError("No usable authentication method; enable password in lock.local.toml")
    return methods


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    try:
        print(",".join(resolve(os.environ.get("SESSION_STACK_AUTH_METHODS", ""), args.preview)))
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
