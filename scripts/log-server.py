#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "google-cloud-logging",
# ]
# ///

"""Persistent log server daemon for Ralph Loop structured event logging.

Listens on a Unix socket for newline-delimited JSON events, writes them to a
dated local JSONL file, and optionally forwards to GCP Cloud Logging.

Usage:
    uv run scripts/log-server.py
"""

from __future__ import annotations

import json
import logging
import os
import signal
import socket
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import types

_DEGA_CORE_HOME = Path(os.environ.get("DEGA_CORE_HOME", Path.home() / ".degacore"))
LOG_DIR = _DEGA_CORE_HOME / "state" / "logs"
RALPH_LOG_DIR = LOG_DIR / "ralph"
SOCKET_PATH = LOG_DIR / "log.sock"
PID_FILE = LOG_DIR / "log-server.pid"
GCP_CREDS_PATH = _DEGA_CORE_HOME / "config" / "gcp-sa.json"
GCP_LOG_NAME = "ralph"

_logger = logging.getLogger(__name__)


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )


def _init_gcp_client() -> object | None:
    """Load GCP credentials and return a Cloud Logging client, or None.

    Checks $DEGA_CORE_HOME/config/gcp-sa.json then $GOOGLE_APPLICATION_CREDENTIALS.
    Emits a startup warning and returns None if credentials are absent.

    Returns:
        google.cloud.logging.Client on success, None for local-only mode.
    """
    creds_env = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    creds_path = Path(creds_env) if creds_env else GCP_CREDS_PATH
    if not creds_path.exists():
        _logger.warning(
            "GCP credentials not found at %s — running in local-only mode",
            creds_path,
        )
        return None
    try:
        import google.cloud.logging  # type: ignore[import-untyped]

        os.environ.setdefault("GOOGLE_APPLICATION_CREDENTIALS", str(creds_path))
        client = google.cloud.logging.Client()
        _logger.info("GCP Cloud Logging enabled (log: %s)", GCP_LOG_NAME)
        return client
    except Exception as exc:  # noqa: BLE001
        _logger.warning("GCP init failed (%s) — local-only mode", exc)
        return None


def _gcp_write(client: object, event: dict[str, object]) -> None:
    """Write a single event to GCP Cloud Logging.

    Intended to run in a background daemon thread; failures are logged at
    DEBUG level and silently discarded to avoid blocking the server.

    Args:
        client: A google.cloud.logging.Client instance.
        event: The parsed event dict to forward.
    """
    try:
        gcp_logger = client.logger(GCP_LOG_NAME)  # type: ignore[attr-defined]
        gcp_logger.log_struct(event)
    except Exception as exc:  # noqa: BLE001
        _logger.debug("GCP write failed: %s", exc)


def _write_local(event: dict[str, object]) -> None:
    """Append an event to today's local JSONL file.

    Creates $DEGA_CORE_HOME/state/logs/ralph/ if it does not exist.

    Args:
        event: The parsed event dict to persist.
    """
    RALPH_LOG_DIR.mkdir(parents=True, exist_ok=True)
    date_str = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")
    log_file = RALPH_LOG_DIR / f"{date_str}.jsonl"
    with log_file.open("a") as f:
        f.write(json.dumps(event) + "\n")


def _handle_line(line: str, gcp_client: object | None) -> None:
    """Parse one newline-delimited JSON line and dispatch it.

    Writes the event locally and, if a GCP client is available, spawns a
    daemon thread to forward it asynchronously.

    Args:
        line: A raw JSON string received from the socket.
        gcp_client: GCP client for cloud forwarding, or None.
    """
    line = line.strip()
    if not line:
        return
    try:
        event: dict[str, object] = json.loads(line)
    except json.JSONDecodeError as exc:
        _logger.warning("Invalid JSON (ignored): %.80s — %s", line, exc)
        return
    _write_local(event)
    if gcp_client is not None:
        threading.Thread(
            target=_gcp_write,
            args=(gcp_client, event),
            daemon=True,
        ).start()


def _handle_connection(conn: socket.socket, gcp_client: object | None) -> None:
    """Process all lines from a single client connection.

    Reads from the socket until EOF, splitting on newlines. A partial
    final line (no trailing newline) is flushed on connection close.

    Args:
        conn: The accepted client socket.
        gcp_client: GCP client for cloud forwarding, or None.
    """
    with conn:
        buf = ""
        while True:
            try:
                chunk = conn.recv(4096).decode("utf-8", errors="replace")
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                _handle_line(line, gcp_client)
        if buf.strip():
            _handle_line(buf, gcp_client)


class LogServer:
    """Unix-socket log server daemon.

    Accepts newline-delimited JSON on SOCKET_PATH, persists each event to a
    dated JSONL file under RALPH_LOG_DIR, and optionally forwards to GCP.
    """

    def __init__(self) -> None:
        self._sock: socket.socket | None = None
        self._gcp_client: object | None = None

    def start(self) -> None:
        """Initialize directories, bind socket, and enter the accept loop."""
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()))
        self._gcp_client = _init_gcp_client()
        self._sock = self._bind()
        signal.signal(signal.SIGTERM, self._on_sigterm)
        _logger.info("log-server listening on %s (pid %d)", SOCKET_PATH, os.getpid())
        self._serve()

    def _bind(self) -> socket.socket:
        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(SOCKET_PATH))
        sock.listen(16)
        return sock

    def _serve(self) -> None:
        sock = self._sock
        if sock is None:
            return
        while True:
            try:
                conn, _ = sock.accept()
            except OSError:
                break
            threading.Thread(
                target=_handle_connection,
                args=(conn, self._gcp_client),
                daemon=True,
            ).start()

    def _on_sigterm(self, signum: int, frame: types.FrameType | None) -> None:
        _logger.info("SIGTERM received — shutting down")
        self._cleanup()
        sys.exit(0)

    def _cleanup(self) -> None:
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
        SOCKET_PATH.unlink(missing_ok=True)
        PID_FILE.unlink(missing_ok=True)


def main() -> None:
    """Entry point."""
    _setup_logging()
    LogServer().start()


if __name__ == "__main__":
    main()
