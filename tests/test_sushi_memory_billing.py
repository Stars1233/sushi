#!/usr/bin/env python3
"""Serial live Sushi billing, KV override, and context refusal validation.

Requires the box GPU lock and real Qwen/MiMo packs. Runs no workload until
invoked explicitly; compilation and --help do not start a server.
"""

import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request


PACKS = {
    "Qwen3.8-Flash-Next-Sushi-2.6bpw": (47_463_796_730, 45_355_923_482),
    "MiMo-V2.6-Flash-Sushi-2.3bpw": (96_265_841_408, 93_619_252_096),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", type=Path, default=Path(os.environ.get("SUSHI_MODELS_DIR", str(Path.home() / "llm" / "models"))))
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pack", choices=list(PACKS), action="append")
    parser.add_argument("--refusals-only", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    binary = args.binary.resolve()
    assert binary.is_file(), binary
    args.output.mkdir(parents=True, exist_ok=True)
    packs = args.pack or list(PACKS)
    for name in packs:
        assert (args.models / name / "config.json").is_file(), name
    env = dict(os.environ)
    env.pop("SUSHI_MTP_DRAFT_HEAD_BITS", None)  # Native defaults: Qwen 3 bits, MiMo 2 bits.
    owner = f"sushi-memory-live-{os.getpid()}"
    lock = root / "scripts/gpu-lock.sh"

    def port():
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            return probe.getsockname()[1]

    def request(base, route, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(base + route, data=data, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as response:
            return response.code, json.load(response)

    def run_server(label, context, model=None, flags=(), exercise=None, refuses=False):
        run_port = port()
        base = f"http://127.0.0.1:{run_port}"
        log_path = args.output / f"{label}.log"
        command = [str(binary), "serve", "--host", "127.0.0.1", "--port", str(run_port),
                   "--ctx-size", str(context), "--prefill-chunk", "512" if context < 1_000_000 else "2048",
                   "--max-tokens", "8", "--prefix-cache-entries", "0", "--no-drafter"]
        command += ["--model", str(model)] if model else ["--model-dir", str(args.models)]
        command += list(flags)
        subprocess.run([str(lock), "acquire", owner], check=True)
        child = None
        try:
            with log_path.open("w") as log:
                child = subprocess.Popen(["taskpolicy", "-a", *command], stdout=log,
                                         stderr=subprocess.STDOUT, env=env)
                if refuses:
                    exit_code = child.wait(timeout=120)
                    assert exit_code > 0, f"expected clean refusal, got exit {exit_code}: {label}"
                else:
                    deadline = time.monotonic() + 300
                    while time.monotonic() < deadline:
                        assert child.poll() is None, f"server exited; see {log_path}"
                        try:
                            if request(base, "/health")[0] == 200:
                                break
                        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
                            time.sleep(0.5)
                    else:
                        raise AssertionError(f"startup timeout; see {log_path}")
                    exercise(base, log_path)
        finally:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            subprocess.run([str(lock), "release", owner], check=True)
            # Metal unwires buffers asynchronously after a process exits.
            time.sleep(2)
        text = log_path.read_text()
        if refuses:
            maximum = re.search(r"Maximum context with this memory budget: (\d+) tokens", text)
            assert maximum, f"numeric startup refusal missing; see {log_path}"
            assert "Loading model-" not in text, "refusal happened after shard loading"
            print(f"PASS {label}: maximum context {maximum.group(1)}", flush=True)
        return text

    if not args.refusals_only:
        for name in packs:
            for enabled in (True, False):
                label = f"{name}-{'enabled' if enabled else 'disabled'}"
                wanted = PACKS[name][0 if enabled else 1]

                def exercise(base, log_path, name=name, enabled=enabled, wanted=wanted, label=label):
                    status, models = request(base, "/v1/models")
                    assert status == 200, models
                    loaded = next(m for m in models["data"] if m.get("loaded"))
                    assert loaded["bytes_resident"] == wanted, (loaded["bytes_resident"], wanted)
                    assert loaded["meta"]["mtp_loaded"] == enabled, loaded["meta"]
                    assert ("image" in loaded["input_modalities"]) == enabled, loaded["input_modalities"]
                    status, props = request(base, "/props")
                    assert status == 200, props
                    assert props["settings"]["kv_cache"]["scheme"] == "kv8", props["settings"]
                    assert props["settings"]["kv_quant"] == "8", props["settings"]
                    assert props["settings"]["mtp"]["loaded"] == enabled, props["settings"]["mtp"]
                    assert props["settings"]["mtp"]["default_on"] == enabled, props["settings"]["mtp"]
                    preflight = re.search(r"\[preflight\] weights ~([0-9.]+) GB, needs ~([0-9.]+) GB", log_path.read_text())
                    assert preflight, log_path
                    weights, needed = map(float, preflight.groups())
                    warmup = 0.25 if name.startswith("MiMo") else (1.25 if enabled else 0.125)
                    assert needed - weights >= 1.0 + warmup - 0.01, (weights, needed, warmup)
                    assert props["memory"]["peak_bytes"] <= (needed + 0.005) * 2**30, props["memory"]
                    (args.output / f"{label}.props.json").write_text(json.dumps(props, indent=2))
                    status, reply = request(base, "/v1/chat/completions", {
                        "model": loaded["id"], "messages": [{"role": "user", "content": "Reply with one greeting."}],
                        "kv_quant": 4, "max_tokens": 8, "temperature": 0, "stream": False,
                        "enable_thinking": False,
                    })
                    assert status == 200 and reply.get("choices"), reply
                    assert reply["usage"]["completion_tokens"] > 0, reply
                    assert "kv-quant override: affine 4-bit (per-request)" in log_path.read_text()
                    (args.output / f"{label}.reply.json").write_text(json.dumps(reply, indent=2))
                    print(f"PASS {label}: {wanted} bytes, KV8 default, KV4 request", flush=True)

                run_server(label, 4096, args.models / name,
                           ("--mtp",) if enabled else ("--no-mtp", "--no-vision"), exercise)

    for name in packs:
        run_server(f"{name}-startup-refusal", 4_000_000_000, args.models / name, ("--mtp",), refuses=True)

    def cold(base, log_path):
        for name in packs:
            for attempt in range(2):
                status, body = request(base, "/v1/load-model", {"model": name})
                assert status == 503 and body["error"]["type"] == "out_of_memory", (status, body)
                maximum = re.search(r"Maximum context: (\d+) tokens", body["error"]["message"])
                assert maximum, body
                (args.output / f"{name}-cold-refusal-{attempt}.json").write_text(json.dumps(body, indent=2))
                print(f"PASS {name} cold refusal {attempt}: maximum context {maximum.group(1)}", flush=True)
        _, props = request(base, "/props")
        assert props["memory"]["active_bytes"] < 512 * 1024 * 1024, props["memory"]
        assert "Loading model-" not in log_path.read_text()

    run_server("cold-refusal", 4_000_000_000, flags=("--mtp",), exercise=cold)


if __name__ == "__main__":
    main()
