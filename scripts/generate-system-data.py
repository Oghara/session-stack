#!/usr/bin/env python3
"""Generate the greeter's public account and desktop-session inventory."""

from __future__ import annotations

import argparse
import configparser
import json
import os
import pathlib
import pwd
import shlex
import shutil
import sys

from auth_config import DEFAULT_AUTHENTICATION, authentication_capabilities, load_settings


DEFAULT_OUTPUT = pathlib.Path(__file__).resolve().parents[1] / (
    "quickshell/session-stack-greeter/GeneratedSystemData.qml"
)
SESSION_DIRS = (
    pathlib.Path("/usr/share/wayland-sessions"),
    pathlib.Path("/usr/share/xsessions"),
)
BLOCKED_SHELLS = {
    "/bin/false",
    "/usr/bin/false",
    "/sbin/nologin",
    "/usr/sbin/nologin",
}
FIELD_CODES = {"%f", "%F", "%u", "%U", "%i", "%c", "%k"}


def login_uid_bounds() -> tuple[int, int]:
    lower, upper = 1000, 60000
    path = pathlib.Path("/etc/login.defs")
    if not path.is_file():
        return lower, upper
    for raw_line in path.read_text(errors="replace").splitlines():
        fields = raw_line.split()
        if len(fields) < 2 or fields[0].startswith("#"):
            continue
        if fields[0] == "UID_MIN":
            lower = int(fields[1])
        elif fields[0] == "UID_MAX":
            upper = int(fields[1])
    return lower, upper


def account_is_hidden(username: str) -> bool:
    path = pathlib.Path("/var/lib/AccountsService/users") / username
    if not path.is_file():
        return False
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(path)
    if not parser.has_section("User"):
        return False
    return parser.getboolean("User", "SystemAccount", fallback=False) or parser.getboolean(
        "User", "Hidden", fallback=False
    )


def user_inventory() -> list[dict[str, str]]:
    uid_min, uid_max = login_uid_bounds()
    users: list[dict[str, str]] = []
    for entry in pwd.getpwall():
        if not uid_min <= entry.pw_uid <= uid_max:
            continue
        if entry.pw_shell in BLOCKED_SHELLS or account_is_hidden(entry.pw_name):
            continue
        if not pathlib.Path(entry.pw_shell).is_file():
            continue
        display_name = entry.pw_gecos.split(",", 1)[0].strip() or entry.pw_name
        users.append(
            {
                "username": entry.pw_name,
                "label": display_name.upper(),
                "role": "LOCAL OPERATOR",
            }
        )
    return sorted(users, key=lambda user: user["username"])


def executable_exists(executable: str) -> bool:
    if os.path.isabs(executable):
        return os.path.isfile(executable) and os.access(executable, os.X_OK)
    return shutil.which(executable) is not None


def parse_exec(value: str) -> list[str]:
    command = []
    for token in shlex.split(value, posix=True):
        if token in FIELD_CODES:
            continue
        for code in FIELD_CODES:
            token = token.replace(code, "")
        if token:
            command.append(token)
    return command


def session_inventory() -> list[dict[str, object]]:
    sessions: list[dict[str, object]] = []
    seen: set[str] = set()
    for directory in SESSION_DIRS:
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.desktop")):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            parser.read(path)
            if not parser.has_section("Desktop Entry"):
                continue
            entry = parser["Desktop Entry"]
            if entry.get("Type", "Application") != "Application":
                continue
            if entry.get("Hidden", "false").lower() == "true" \
                    or entry.get("NoDisplay", "false").lower() == "true":
                continue
            command = parse_exec(entry.get("Exec", ""))
            if not command or not executable_exists(command[0]):
                continue
            try_exec = entry.get("TryExec", "").strip()
            if try_exec and not executable_exists(try_exec):
                continue
            session_id = path.stem
            if session_id in seen:
                continue
            seen.add(session_id)
            name = entry.get("Name", session_id).strip()
            session_kind = "WAYLAND" if directory.name == "wayland-sessions" else "X11"
            sessions.append(
                {
                    "id": session_id,
                    "label": name.upper(),
                    "detail": session_kind,
                    "command": command,
                }
            )
    return sessions


def load_authentication_config(path: pathlib.Path | None = None) -> dict[str, object]:
    if path is None:
        project = pathlib.Path(__file__).resolve().parents[1]
        local = project / "greeter.local.toml"
        path = local if local.exists() else project / "greeter.toml"
    return load_settings(path)


def configured_users(users: list[dict[str, str]], settings: dict[str, object]) -> list[dict[str, object]]:
    result = []
    for user in users:
        capabilities = authentication_capabilities(user["username"], settings)
        if not settings["password"] and not any(capabilities.values()):
            raise ValueError("Password is disabled but an eligible account has no detected biometric method; "
                             "enable password or complete enrollment and stage again")
        result.append({**user, "faceAuthenticationEnabled": capabilities["face"],
                       "fingerprintAuthenticationEnabled": capabilities["fingerprint"]})
    for method in ("face", "fingerprint"):
        if settings[method] == "on" and not any(user[f"{method}AuthenticationEnabled"] for user in result):
            raise ValueError(f"{method} is on but no eligible account has a detected backend/device/enrollment; "
                             "configure the backend, use auto, or turn it off")
    return result


def qml_document(users: list[dict[str, str]], sessions: list[dict[str, object]],
                 *, demo: bool = False, settings: dict[str, object] | None = None) -> str:
    settings = DEFAULT_AUTHENTICATION if settings is None else settings
    if demo:
        settings = DEFAULT_AUTHENTICATION
        resolved_users = [{**user, "faceAuthenticationEnabled": False,
                           "fingerprintAuthenticationEnabled": False} for user in users]
    else:
        resolved_users = configured_users(users, settings)
    users_json = json.dumps(resolved_users, ensure_ascii=True, separators=(",", ":"))
    sessions_json = json.dumps(sessions, ensure_ascii=True, separators=(",", ":"))
    face = any(user["faceAuthenticationEnabled"] for user in resolved_users)
    fingerprint = any(user["fingerprintAuthenticationEnabled"] for user in resolved_users)
    return "\n".join(
        (
            "// Generated by scripts/generate-system-data.py; do not edit.",
            "import QtQuick",
            "",
            "QtObject {",
            f"    readonly property bool isDemo: {str(demo).lower()}",
            f"    readonly property bool passwordAuthenticationEnabled: {str(settings['password']).lower()}",
            f"    readonly property bool faceAuthenticationEnabled: {str(face).lower()}",
            f"    readonly property bool fingerprintAuthenticationEnabled: {str(fingerprint).lower()}",
            f"    readonly property var users: {users_json}",
            f"    readonly property var systems: {sessions_json}",
            "}",
            "",
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--demo", action="store_true",
                        help="Use fictional accounts without inspecting the host")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--config", type=pathlib.Path, help="Authentication TOML file for host inventory")
    args = parser.parse_args()

    if args.demo:
        args.output = args.output or DEFAULT_OUTPUT
        users = [{"username": "operator", "label": "OPERATOR", "role": "LOCAL OPERATOR"}]
        sessions = [
            {"id": "hyprland-uwsm", "label": "HYPRLAND / UWSM", "detail": "WAYLAND",
             "command": ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]},
            {"id": "hyprland", "label": "HYPRLAND", "detail": "WAYLAND",
             "command": ["/usr/bin/start-hyprland"]},
        ]
    else:
        if args.output is None:
            parser.error("Host inventory requires --output outside the source tree; use --demo for previews")
        project = pathlib.Path(__file__).resolve().parents[1]
        if args.output.resolve().is_relative_to(project):
            parser.error("Host inventory must stay outside the source tree")
        users = user_inventory()
        sessions = session_inventory()
        if not users:
            print("No eligible login users were found.", file=sys.stderr)
            return 1
        if not sessions:
            print("No launchable desktop sessions were found.", file=sys.stderr)
            return 1
    try:
        settings = None if args.demo else load_authentication_config(args.config)
        document = qml_document(users, sessions, demo=args.demo, settings=settings)
    except (ValueError, OSError) as error:
        parser.error(str(error))

    if args.check:
        if not args.output.is_file() or args.output.read_text() != document:
            print(f"Generated system data is stale: {args.output}", file=sys.stderr)
            return 1
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + f".tmp.{os.getpid()}")
    temporary.write_text(document)
    os.chmod(temporary, 0o644)
    os.replace(temporary, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
