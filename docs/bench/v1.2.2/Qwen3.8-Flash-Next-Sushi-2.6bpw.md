# Qwen3.8-Flash-Next-Sushi-2.6bpw — 1.2.2

Version: **1.2.2**. Commit: `bb9adb6a`. Binary SHA-256: `d8c741577e52dfc2301554fc96642a3df4f289405e302fe4444e605c91fc11e9`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **mtp**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/Qwen3.8-Flash-Next-Sushi-2.6bpw --port 12345 --kv-quant 8 --no-update-check --mtp`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m Qwen3.8-Flash-Next-Sushi-2.6bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 96.5 | 100.7 | 98.6 | 96.5 | 100.7 |
| Prefill tok/s | 2539.0 | 2487.4 | 2513.2 | 2487.4 | 2539.0 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2112 | 2 | 2144 | 92.3 | 1.0 | 3.24 |
| 4k | 4081 | 2 | 2355 | 86.1 | 1.7 | 3.24 |
| 8k | 8270 | 2 | 2413 | 88.8 | 3.4 | 4.32 |
| 16k | 16276 | 2 | 2414 | 89.2 | 6.7 | 3.60 |
| 32k | 32892 | 2 | 2399 | 90.9 | 13.7 | 3.68 |
| 64k | 65479 | 2 | 2348 | 83.1 | 27.9 | 3.81 |
| 128k | 131152 | 2 | 2255 | 79.6 | 58.2 | 3.69 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 5.92 |
| Speculative verdict | effective |
| Prefix cache speedup | 5.5× |
| Cached / prompt tokens | 1508 / 1539 |
| Batch streams | 4 |
| Single stream tok/s | 66.1 |
| Aggregate tok/s | 97.7 |
| Batch efficiency | 0.37 |
| Sustained initial / final tok/s | 98.6 / 89.5 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
