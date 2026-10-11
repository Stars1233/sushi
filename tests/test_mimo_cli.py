#!/usr/bin/env python3
"""Exercise `run` on a real TTY, including startup, one chat turn, and /bye."""
import os
import pathlib
import pty
import re
import select
import socket
import subprocess
import sys
import tempfile
import time


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    model = os.environ.get("MIMO_STREAM_MODEL")
    if not model:
        print("SKIP: set MIMO_STREAM_MODEL to a converted pack", file=sys.stderr)
        return 2
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    (root / ".zig-cache").mkdir(exist_ok=True)
    out = pathlib.Path(tempfile.mkdtemp(prefix="mimo-cli-", dir=root / ".zig-cache"))
    home = pathlib.Path(os.environ.get("MIMO_CLI_TEST_HOME", str(out / "home")))
    (home / ".sushi" / "models").mkdir(parents=True, exist_ok=True)
    command = [
        str(root / "zig-out/bin/sushi"), "run", str(pathlib.Path(model).resolve()),
        "--host", "127.0.0.1", "--port", str(port),
        "--ssd-budget-gb", os.environ.get("MIMO_SSD_BUDGET_GB", "100"),
        "--kv-quant", "8", "--ctx-size", "4096", "--prefill-chunk", "512",
        "--max-tokens", "32", "--no-mtp", "--no-vision",
        "--prefix-cache-entries", "0", "--log-file", str(out / "server.log"),
    ]
    master, slave = pty.openpty()
    child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                             env={**os.environ, "HOME": str(home)}, start_new_session=True)
    os.close(slave)
    transcript = bytearray()
    sent = finished = False
    deadline = time.monotonic() + float(os.environ.get("MIMO_CLI_TEST_TIMEOUT", "60"))
    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.25)
            if readable:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                transcript.extend(data)
                if not sent and b"chat is live" in transcript:
                    os.write(master, b"Reply with one short greeting.\n")
                    sent = True
                if sent and not finished and re.search(rb"\[\d+ tokens, [\d.]+ tok/s\]", transcript):
                    os.write(master, b"/bye\n")
                    finished = True
            if child.poll() is not None:
                break
    finally:
        if child.poll() is None and finished:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        if child.poll() is None:
            child.terminate()
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        os.close(master)
        (out / "transcript.txt").write_bytes(transcript)
    if not sent or not finished or child.returncode != 0:
        print(f"FAIL: chat_ready={sent}, reply_completed={finished}, exit={child.returncode}; diagnostics: {out}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
