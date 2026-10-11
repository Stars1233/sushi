# GLM-5.3-Flash-Sushi-2bpw — 1.2.2

Version: **1.2.2**. Commit: `29107ce9`. Binary SHA-256: `98d1760b197132213dc0d17d211cc64a4ce540bbfad16644adfc17a967978195`. Date: 2026-10-11 (Asia/Bangkok).

Measured runs: **2**, one server boot. Speculative mode: **dflash**, verified from engagement logs. Hardware, thermal protocol and common settings: [version summary](summary.md).

Server command: `sushi --serve --model <model-dir>/GLM-5.3-Flash-Sushi-2bpw --port 12345 --kv-quant 8 --no-update-check`.

Probe command: `npx llmprobe@0.6.15 localhost:12345 --bench-only -m GLM-5.3-Flash-Sushi-2bpw --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`.

## Scenario samples

| Metric | Run 1 | Run 2 | Median | Min | Max |
|---|---:|---:|---:|---:|---:|
| Decode tok/s | 51.5 | 47.2 | 49.4 | 47.2 | 51.5 |
| Prefill tok/s | 781.1 | 753.2 | 767.1 | 753.2 | 781.1 |

## Context ladder

| Target context | Actual input tokens | Runs | Prefill tok/s | Decode tok/s | First token s | Tok/step |
|---|---:|---:|---:|---:|---:|---:|
| 2k | 2078 | 2 | 883 | 47.5 | 2.4 | 2.46 |
| 4k | 4087 | 2 | 780 | 48.8 | 5.2 | 2.53 |
| 8k | 8267 | 2 | 739 | 47.7 | 11.2 | 2.47 |
| 16k | 16311 | 2 | 724 | 47.1 | 22.5 | 2.85 |
| 32k | 32776 | 2 | 713 | 43.8 | 46.0 | 2.59 |
| 64k | 65660 | 2 | 649 | 44.8 | 101.1 | 2.77 |
| 128k | 131085 | 2 | 570 | 44.5 | 229.9 | 2.49 |

## Additional benchmark results

| Metric | Value |
|---|---|
| Tokens per decode step | 3.53 |
| Speculative verdict | effective |
| Prefix cache speedup | 7.3× |
| Cached / prompt tokens | 1388 / 1419 |
| Batch streams | 4 |
| Single stream tok/s | 39.1 |
| Aggregate tok/s | 50.9 |
| Batch efficiency | 0.33 |
| Sustained initial / final tok/s | 49.4 / 48.2 |

## Probe notes

- custom setup: 2 runs per scenario, rungs 2k, 4k, 8k, 16k, 32k, 64k, 128k, reasoning default — not comparable to default runs
- engine ignored ignore_eos/min_tokens — decode length follows the model's own stop, so decode figures cover model-dependent amounts of work
