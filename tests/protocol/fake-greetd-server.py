#!/usr/bin/env python3
"""Exercise QuickShell's native Greetd singleton over the real IPC framing."""

from __future__ import annotations

import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time


PROJECT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = PROJECT / "quickshell/session-stack-greeter"
SECRET = "native-protocol-test"


def receive_exact(connection: socket.socket, length: int) -> bytes:
    chunks = []
    remaining = length
    while remaining:
        chunk = connection.recv(remaining)
        if not chunk:
            raise RuntimeError("greetd client closed the socket mid-frame")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def receive_frame(connection: socket.socket) -> dict[str, object]:
    length = struct.unpack("<I", receive_exact(connection, 4))[0]
    if length > 1024 * 1024:
        raise RuntimeError(f"refusing oversized greetd frame: {length}")
    return json.loads(receive_exact(connection, length))


def send_frame(connection: socket.socket, payload: dict[str, object]) -> None:
    encoded = json.dumps(payload, separators=(",", ":")).encode()
    connection.sendall(struct.pack("<I", len(encoded)) + encoded)


class ProtocolServer(threading.Thread):
    def __init__(self, socket_path: pathlib.Path, outcome: str):
        super().__init__(daemon=True)
        self.socket_path = socket_path
        self.outcome = outcome
        self.additional_prompt_sent = threading.Event()
        self.ready = threading.Event()
        self.create_received = threading.Event()
        self.allow_prompt = threading.Event()
        self.method_prompt_sent = threading.Event()
        self.complete = threading.Event()
        self.requests: list[dict[str, object]] = []
        self.failure: BaseException | None = None

    def run(self) -> None:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(str(self.socket_path))
                listener.listen(1)
                listener.settimeout(10)
                self.ready.set()
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(20)
                    create = receive_frame(connection)
                    self.requests.append(create)
                    if create != {"type": "create_session", "username": "beta"}:
                        raise RuntimeError(f"invalid create_session request: {create}")
                    self.create_received.set()
                    if not self.allow_prompt.wait(5):
                        raise RuntimeError("test never released the delayed method prompt")

                    # No response is valid before greetd requests one.
                    connection.settimeout(0.25)
                    try:
                        premature = receive_frame(connection)
                    except socket.timeout:
                        premature = None
                    finally:
                        connection.settimeout(20)
                    if premature is not None:
                        raise RuntimeError(
                            f"client responded before the method prompt: {premature}"
                        )
                    send_frame(
                        connection,
                        {
                            "type": "auth_message",
                            "auth_message_type": "secret",
                            "auth_message": "Authentication method:",
                        },
                    )
                    self.method_prompt_sent.set()

                    selector = receive_frame(connection)
                    self.requests.append(selector)
                    if selector != {
                        "type": "post_auth_message_response",
                        "response": "session-stack-greeter:password:v1",
                    }:
                        raise RuntimeError("native client sent an invalid method selector")
                    send_frame(
                        connection,
                        {
                            "type": "auth_message",
                            "auth_message_type": "secret",
                            "auth_message": "Password:",
                        },
                    )

                    password = receive_frame(connection)
                    self.requests.append(password)
                    if password != {
                        "type": "post_auth_message_response",
                        "response": SECRET,
                    }:
                        raise RuntimeError("native client sent an invalid credential response")
                    if self.outcome == "reprompt":
                        send_frame(connection, {"type": "auth_message", "auth_message_type": "error",
                                                "auth_message": "Try again"})
                        acknowledgement = receive_frame(connection)
                        self.requests.append(acknowledgement)
                        if acknowledgement.get("type") != "post_auth_message_response" \
                                or acknowledgement.get("response") is not None:
                            raise RuntimeError(f"unexpected informational-message acknowledgement: {acknowledgement!r}")
                        send_frame(connection, {"type": "auth_message", "auth_message_type": "secret",
                                                "auth_message": "Password:"})
                        self.additional_prompt_sent.set()
                        password = receive_frame(connection)
                        self.requests.append(password)
                        if password != {"type": "post_auth_message_response", "response": SECRET + "-retry"}:
                            raise RuntimeError("invalid response to additional password prompt")
                    if self.outcome == "reject":
                        send_frame(connection, {"type": "error", "error_type": "auth_error",
                                                "description": "Authentication rejected"})
                        cancelled = receive_frame(connection)
                        self.requests.append(cancelled)
                        if cancelled != {"type": "cancel_session"}:
                            raise RuntimeError("expected cancellation after rejection")
                        send_frame(connection, {"type": "success"})
                        if connection.recv(1):
                            raise RuntimeError("request after terminal failure; expected greeter exit")
                        self.complete.set()
                        return
                    send_frame(connection, {"type": "success"})

                    start = receive_frame(connection)
                    self.requests.append(start)
                    command = start.get("cmd")
                    if start.get("type") != "start_session" \
                            or command != ["/usr/bin/start-hyprland"]:
                        raise RuntimeError(f"invalid start_session request: {start}")
                    send_frame(connection, {"type": "success"})
                    self.complete.set()
        except BaseException as error:  # surfaced in the controlling test process
            self.failure = error
            self.ready.set()
            self.complete.set()


def ipc_call(function: str, argument: str | None = None) -> subprocess.CompletedProcess[str]:
    command = [
        "quickshell",
        "ipc",
        "--any-display",
        "--path",
        str(CONFIG),
        "call",
        "sessionStackGreeter",
        function,
    ]
    if argument is not None:
        command.append(argument)
    return subprocess.run(command, text=True, capture_output=True, check=False, timeout=3)


def wait_for_method_prompt(
    process: subprocess.Popen[str], server: ProtocolServer
) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if server.failure:
            raise RuntimeError("fake greetd server failed") from server.failure
        if server.method_prompt_sent.is_set():
            return
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout else ""
            raise RuntimeError(
                f"QuickShell exited before the greetd prompt:\n{output}"
            )
        time.sleep(0.1)
    raise RuntimeError("timed out waiting for QuickShell's method prompt")


def wait_for_ipc(process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout else ""
            raise RuntimeError(f"QuickShell exited before IPC was ready:\n{output}")
        status = ipc_call("status")
        if status.returncode == 0 and status.stdout.strip().startswith("{"):
            return
        time.sleep(0.1)
    raise RuntimeError("timed out waiting for QuickShell IPC")


def run_case(biometrics: bool, outcome: str) -> None:
    with tempfile.TemporaryDirectory(prefix="session-stack-greetd-test.") as temp:
        socket_path = pathlib.Path(temp) / "greetd.sock"
        server = ProtocolServer(socket_path, outcome)
        server.start()
        if not server.ready.wait(3) or server.failure:
            raise RuntimeError(
                f"fake greetd server failed to start: {server.failure!r}"
            ) from server.failure

        environment = os.environ.copy()
        environment.update(
            {
                "GREETD_SOCK": str(socket_path),
                "QT_QPA_PLATFORM": "offscreen",
                "SESSION_STACK_GREETER_MODE": "protocol-test",
                "SESSION_STACK_GREETER_BIOMETRIC_TEST": "1" if biometrics else "0",
            }
        )
        process = subprocess.Popen(
            ["quickshell", "--no-duplicate", "--path", str(CONFIG)],
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        try:
            wait_for_ipc(process)
            status = json.loads(ipc_call("status").stdout)
            if not status["passwordEnabled"] or status["faceEnabled"] != biometrics \
                    or status["fingerprintEnabled"] != biometrics:
                raise RuntimeError("unexpected authentication options in test case")
            selected = ipc_call("selectUser", "beta")
            if selected.returncode != 0 or selected.stdout.strip() != "selected":
                raise RuntimeError(f"pre-auth selection failed: {selected.stderr}")
            selected_system = ipc_call("selectSystem", "hyprland")
            if selected_system.returncode != 0 \
                    or selected_system.stdout.strip() != "selected":
                raise RuntimeError(
                    f"pre-auth system selection failed: {selected_system.stderr}"
                )
            if server.create_received.wait(0.5):
                raise RuntimeError(
                    "selection created a greetd session before authentication"
                )
            submitted = ipc_call("submit", SECRET)
            if submitted.returncode != 0 or submitted.stdout.strip() != "submitted":
                raise RuntimeError(f"credential submission failed: {submitted.stderr}")
            if not server.create_received.wait(5):
                raise RuntimeError("QuickShell never created the greetd session")
            locked = ipc_call("selectUser", "gamma")
            if locked.returncode != 0 or locked.stdout.strip() != "locked":
                raise RuntimeError(
                    "selection changed during authentication: "
                    f"stdout={locked.stdout!r} stderr={locked.stderr!r}"
                )
            locked_system = ipc_call("selectSystem", "hyprland-uwsm")
            if locked_system.returncode != 0 \
                    or locked_system.stdout.strip() != "locked":
                raise RuntimeError(
                    "system changed during authentication: "
                    f"stdout={locked_system.stdout!r} "
                    f"stderr={locked_system.stderr!r}"
                )
            server.allow_prompt.set()
            wait_for_method_prompt(process, server)
            if outcome == "reprompt":
                if not server.additional_prompt_sent.wait(5):
                    raise RuntimeError("additional password prompt was not sent")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    status = json.loads(ipc_call("status").stdout)
                    if status["phase"] == 2:
                        if status["busy"]:
                            raise RuntimeError("additional password prompt left input disabled")
                        break
                    time.sleep(0.05)
                else:
                    raise RuntimeError("additional password prompt never became interactive")
                if ipc_call("submit", SECRET + "-retry").stdout.strip() != "submitted":
                    raise RuntimeError("additional password submission was refused")
            if outcome == "reject":
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if ipc_call("retryAuthentication").stdout.strip() == "retrying":
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("password rejection never offered recovery")
            try:
                output, _ = process.communicate(timeout=20)
            except subprocess.TimeoutExpired as error:
                process.kill()
                output, _ = process.communicate(timeout=3)
                raise RuntimeError(
                    "QuickShell did not finish the authentication conversation; "
                    f"requests={server.requests!r}\n{output}"
                ) from error
            expected_exit = 1 if outcome == "reject" else 0
            if process.returncode != expected_exit:
                raise RuntimeError(f"QuickShell exited with {process.returncode}:\n{output}")
            if not server.complete.wait(2):
                raise RuntimeError("native client never completed start_session")
            if server.failure:
                raise RuntimeError("fake greetd protocol failure") from server.failure
            request_types = [request.get("type") for request in server.requests]
            expected_requests = ["create_session", "post_auth_message_response", "post_auth_message_response"]
            if outcome == "reprompt":
                expected_requests.extend(["post_auth_message_response", "post_auth_message_response"])
            expected_requests.append("cancel_session" if outcome == "reject" else "start_session")
            if request_types != expected_requests:
                raise RuntimeError(f"unexpected request sequence: {request_types}")
        finally:
            server.allow_prompt.set()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)

    methods = "biometrics enabled" if biometrics else "password only"
    print(f"Native protocol, selection lock, and UI handoff passed: {methods}, {outcome}.", flush=True)


def main() -> int:
    for biometrics, outcome in ((False, "success"), (False, "reprompt"),
                                (False, "reject"), (True, "success")):
        run_case(biometrics, outcome)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"greetd protocol integration failed: {error}", file=sys.stderr)
        if error.__cause__:
            print(f"caused by: {error.__cause__}", file=sys.stderr)
        raise SystemExit(1)
