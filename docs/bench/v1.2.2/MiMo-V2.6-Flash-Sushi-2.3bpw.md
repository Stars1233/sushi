# MiMo-V2.6-Flash-Sushi-2.3bpw — 1.2.2

Version: **1.2.2**. Commit: `bb9adb6a`. Binary SHA-256: `d8c741577e52dfc2301554fc96642a3df4f289405e302fe4444e605c91fc11e9`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **mtp**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/MiMo-V2.6-Flash-Sushi-2.3bpw --port 12345 --kv-quant 8 --no-update-check --mtp`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m MiMo-V2.6-Flash-Sushi-2.3bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 45.0 | 68.6 | 56.8 | 45.0 | 68.6 |
| Prefill tok/s | 1300.0 | 1286.1 | 1293.1 | 1286.1 | 1300.0 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2090 | 2 | 1308 | 56.7 | 1.6 | 3.30 |
| 4k | 4088 | 2 | 1227 | 55.4 | 3.3 | 3.30 |
| 8k | 8269 | 2 | 1225 | 56.2 | 6.8 | 3.27 |
| 16k | 16334 | 2 | 1144 | 65.5 | 14.3 | 2.72 |
| 32k | 32725 | 2 | 994 | 54.9 | 33.0 | 2.99 |
| 64k | 65627 | 2 | 891 | 57.2 | 73.7 | 3.37 |
| 128k | 131064 | 2 | 679 | 50.2 | 193.0 | 3.31 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 6.19 |
| Speculative verdict | effective |
| Prefix cache speedup | 11.3× |
| Cached / prompt tokens | 1536 / 1537 |
| Batch streams | 4 |
| Single stream tok/s | 35.3 |
| Aggregate tok/s | 80.8 |
| Batch efficiency | 0.57 |
| Sustained initial / final tok/s | 56.8 / 57.9 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
