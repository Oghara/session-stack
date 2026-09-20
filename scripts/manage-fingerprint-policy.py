#!/usr/bin/env python3
"""Optional fprintd verification permission for one account's systemd user manager."""
import argparse
import json
import os
from pathlib import Path
import pwd
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("show", "apply", "remove"))
    parser.add_argument("username", help="desktop account receiving fingerprint verification access")
    args = parser.parse_args()
    try:
        account = pwd.getpwnam(args.username)
    except KeyError:
        parser.error("Unknown account: " + args.username)
    if account.pw_uid == 0:
        parser.error("Choose a non-root desktop account")
    unit = f"user-{account.pw_uid}.service"
    rule = f'''// Managed by Session Stack's optional fingerprint setup.
// This covers all processes in this account's user manager, not just the lockscreen.
polkit.addRule(function(action, subject) {{
    if (action.id === "net.reactivated.fprint.device.verify"
            && subject.user === {json.dumps(account.pw_name)}
            && subject.system_unit === {json.dumps(unit)}) {{
        return polkit.Result.YES;
    }}
}});
'''
    target = Path(f"/etc/polkit-1/rules.d/49-session-stack-fingerprint-{account.pw_uid}.rules")
    if args.action == "show":
        print(rule, end="")
        print(f"\nTarget: {target}")
        return
    if os.geteuid() != 0:
        parser.error("Run apply/remove with sudo")
    if target.is_symlink() or (target.exists() and target.read_text() != rule):
        parser.error(f"Refusing to change an existing modified rule: {target}")
    if args.action == "remove":
        target.unlink(missing_ok=True)
        print(f"Removed Session Stack's rule: {target}. Other policies are unchanged.")
        return
    print(f"Granting net.reactivated.fprint.device.verify to {account.pw_name} in {unit}.")
    print("This includes all user services, including those started remotely. "
          "It does not check for an active local session or grant enrollment/deletion.")
    target.parent.mkdir(parents=True, exist_ok=True)
    # Replace atomically so polkit never reads a partial rule.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(rule)
            os.fchmod(stream.fileno(), 0o644)
            os.fchown(stream.fileno(), 0, 0)
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f"Installed {target}. Polkit reloads rules automatically.")


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
