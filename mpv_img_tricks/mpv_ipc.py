"""Unix-socket IPC helpers for mpv (parity with embedded Python in ``scripts/mpv-pipeline.sh``)."""

from __future__ import annotations

import json
import socket
import time


def send_json(socket_path: str, json_payload: str) -> bool:
    """Send one JSON IPC line. Returns True on connect+send success."""
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(0.6)
        client.connect(socket_path)
        client.send((json_payload + "\n").encode("utf-8"))
        try:
            client.recv(65535)
        except OSError:
            pass
        client.close()
        return True
    except OSError:
        return False


def get_property(socket_path: str, prop_name: str) -> str:
    payload = json.dumps({"command": ["get_property", prop_name]})
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(0.6)
        client.connect(socket_path)
        client.send((payload + "\n").encode("utf-8"))
        response = client.recv(65535).decode("utf-8", errors="ignore")
        client.close()
        if not response.strip():
            return ""
        data = json.loads(response.splitlines()[0])
        value = data.get("data")
        if isinstance(value, bool):
            return "true" if value else "false"
        if value is None:
            return ""
        return str(value)
    except OSError:
        return ""


def wait_until_ready(socket_path: str, *, timeout_s: float = 30.0, poll_s: float = 0.05) -> bool:
    """True when the IPC socket accepts connections and answers a property query."""
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if get_property(socket_path, "pid"):
            return True
        time.sleep(poll_s)
    return False
