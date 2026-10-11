# GLM-5.3-Flash-Sushi-2.4bpw — 1.2.2

Version: **1.2.2**. Commit: `bb9adb6a`. Binary SHA-256: `d8c741577e52dfc2301554fc96642a3df4f289405e302fe4444e605c91fc11e9`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **dflash**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/GLM-5.3-Flash-Sushi-2.4bpw --port 12345 --kv-quant 8 --no-update-check`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m GLM-5.3-Flash-Sushi-2.4bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 58.5 | 54.4 | 56.5 | 54.4 | 58.5 |
| Prefill tok/s | 867.0 | 850.1 | 858.6 | 850.1 | 867.0 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2078 | 2 | 830 | 47.4 | 2.5 | 2.51 |
| 4k | 4087 | 2 | 837 | 52.7 | 4.9 | 2.60 |
| 8k | 8267 | 2 | 821 | 49.4 | 10.1 | 2.56 |
| 16k | 16311 | 2 | 819 | 46.1 | 19.9 | 2.72 |
| 32k | 32776 | 2 | 800 | 49.5 | 41.0 | 2.72 |
| 64k | 65660 | 2 | 742 | 47.7 | 88.5 | 2.88 |
| 128k | 131085 | 2 | 650 | 44.8 | 201.7 | 2.94 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 3.59 |
| Speculative verdict | effective |
| Prefix cache speedup | 6.6× |
| Cached / prompt tokens | 1388 / 1419 |
| Batch streams | 4 |
| Single stream tok/s | 35.1 |
| Aggregate tok/s | 48.6 |
| Batch efficiency | 0.35 |
| Sustained initial / final tok/s | 56.5 / 50.1 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k, reasoning default — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
