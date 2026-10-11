# Sushi 🍣 1.2.2 benchmarks

Version: **1.2.2**. Date: 2026-10-11 (Asia/Bangkok). Qwen and MiMo ran a binary built from `bb9adb6a`. Their source is unchanged in the release commit `29107ce9`. GLM ran the release binary itself, which adds the GLM DFlash2 in-place commit fix.

Hardware: **Apple M5 Max, 128 GB unified memory**, AC power for every run. ReleaseFast, `taskpolicy -a`, one model per server, GPU lock per model, fans at maximum and 3 minutes idle before each server. All rates are tok/s.

`npx llmprobe@0.6.15 localhost:12345 --bench-only -m <model> --rungs 2k,4k,8k,16k,32k,64k,128k --runs 2`. Scenario warmups are discarded; the table holds llmprobe medians. Server flags: `--kv-quant 8`, default context and vision, `--mtp` on Qwen and MiMo, DFlash2 auto-detected on GLM.

| Sushi 🍣 1.2.2 | | 2k | 4k | 8k | 16k | 32k | 64k | 128k |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **Qwen 3.8 Flash-Next-2.6bpw** | Prefill | 2,144 | 2,355 | 2,413 | 2,414 | 2,399 | 2,348 | 2,255 |
|  | Decode | 92.3 | 86.1 | 88.8 | 89.2 | 90.9 | 83.1 | 79.6 |
| **Qwen 3.8 Flash-Next-4bpw** | Prefill | 1,871 | 2,113 | 2,192 | 2,187 | 2,262 | 2,225 | 2,178 |
|  | Decode | 77.9 | 72.8 | 85.2 | 90.3 | 82.6 | 78.3 | 71.3 |
| **MiMo V2.6 Flash-2.3bpw** | Prefill | 1,308 | 1,227 | 1,225 | 1,144 | 994 | 891 | 679 |
|  | Decode | 56.7 | 55.4 | 56.2 | 65.5 | 54.9 | 57.2 | 50.2 |
| **GLM 5.3 Flash-2.4bpw** | Prefill | 859 | 833 | 821 | 816 | 805 | 737 | 645 |
|  | Decode | 50.1 | 51.8 | 48.7 | 46.4 | 47.4 | 46.6 | 44.2 |

| Model run | Measured runs | Speculative mode | Commit | Binary SHA-256 |
|---|---:|---|---|---|
| [Qwen3.8-Flash-Next-Sushi-2.6bpw](Qwen3.8-Flash-Next-Sushi-2.6bpw.md) | 2 | mtp | `bb9adb6a` | `d8c741577e52dfc2` |
| [Qwen3.8-Flash-Next-Sushi-4bpw](Qwen3.8-Flash-Next-Sushi-4bpw.md) | 2 | mtp | `bb9adb6a` | `d8c741577e52dfc2` |
| [MiMo-V2.6-Flash-Sushi-2.3bpw](MiMo-V2.6-Flash-Sushi-2.3bpw.md) | 2 | mtp | `bb9adb6a` | `d8c741577e52dfc2` |
| [GLM-5.3-Flash-Sushi-2.4bpw](GLM-5.3-Flash-Sushi-2.4bpw.md) | 2 | dflash | `29107ce9` | `98d1760b19713221` |

Qwen 2.6bpw and 4bpw ran in the first pass. That pass's MiMo and GLM runs crossed onto battery, which slowed GLM 8–18%. Both were rerun on AC in fresh servers. The MiMo row is that rerun. GLM was run once more on the release binary, after the in-place commit fix, and that run is the row above. These throughput measurements do not establish long-context answer quality. Raw reports and server logs are indexed in the private measurement ledger.
