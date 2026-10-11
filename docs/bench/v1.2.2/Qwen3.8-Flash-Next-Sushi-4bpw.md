# Qwen3.8-Flash-Next-Sushi-4bpw — 1.2.2

Version: **1.2.2**. Commit: `bb9adb6a`. Binary SHA-256: `d8c741577e52dfc2301554fc96642a3df4f289405e302fe4444e605c91fc11e9`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **mtp**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/Qwen3.8-Flash-Next-Sushi-4bpw --port 12345 --kv-quant 8 --no-update-check --mtp`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m Qwen3.8-Flash-Next-Sushi-4bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 93.0 | 90.9 | 91.9 | 90.9 | 93.0 |
| Prefill tok/s | 2512.9 | 2468.8 | 2490.9 | 2468.8 | 2512.9 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2109 | 2 | 1871 | 77.9 | 1.1 | 3.42 |
| 4k | 4082 | 2 | 2113 | 72.8 | 1.9 | 3.16 |
| 8k | 8271 | 2 | 2192 | 85.2 | 3.8 | 3.71 |
| 16k | 16273 | 2 | 2187 | 90.3 | 7.4 | 3.53 |
| 32k | 32895 | 2 | 2262 | 82.6 | 14.5 | 3.74 |
| 64k | 65478 | 2 | 2225 | 78.3 | 29.4 | 3.59 |
| 128k | 131151 | 2 | 2178 | 71.3 | 60.2 | 3.84 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 5.25 |
| Speculative verdict | effective |
| Prefix cache speedup | 5.8× |
| Cached / prompt tokens | 1509 / 1540 |
| Batch streams | 4 |
| Single stream tok/s | 60.6 |
| Aggregate tok/s | 88.8 |
| Batch efficiency | 0.37 |
| Sustained initial / final tok/s | 91.9 / 79.9 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
