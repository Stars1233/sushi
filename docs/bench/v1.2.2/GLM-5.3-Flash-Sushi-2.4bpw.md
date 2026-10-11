# GLM-5.3-Flash-Sushi-2.4bpw — 1.2.2

Version: **1.2.2**. Commit: `29107ce9`. Binary SHA-256: `98d1760b197132213dc0d17d211cc64a4ce540bbfad16644adfc17a967978195`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **dflash**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/GLM-5.3-Flash-Sushi-2.4bpw --port 12345 --kv-quant 8 --no-update-check`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m GLM-5.3-Flash-Sushi-2.4bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 55.7 | 54.5 | 55.1 | 54.5 | 55.7 |
| Prefill tok/s | 867.1 | 857.6 | 862.3 | 857.6 | 867.1 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2078 | 2 | 859 | 50.1 | 2.4 | 2.50 |
| 4k | 4087 | 2 | 833 | 51.8 | 4.9 | 2.55 |
| 8k | 8267 | 2 | 821 | 48.7 | 10.1 | 2.48 |
| 16k | 16311 | 2 | 816 | 46.4 | 20.0 | 2.45 |
| 32k | 32776 | 2 | 805 | 47.4 | 40.7 | 3.09 |
| 64k | 65660 | 2 | 737 | 46.6 | 89.1 | 2.83 |
| 128k | 131085 | 2 | 645 | 44.2 | 203.3 | 2.92 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 3.56 |
| Speculative verdict | effective |
| Prefix cache speedup | 6.6× |
| Cached / prompt tokens | 1388 / 1419 |
| Batch streams | 4 |
| Single stream tok/s | 37.2 |
| Aggregate tok/s | 50.3 |
| Batch efficiency | 0.34 |
| Sustained initial / final tok/s | 55.1 / 46.5 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k, reasoning default — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
