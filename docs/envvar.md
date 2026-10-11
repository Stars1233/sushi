# Environment variables

Every environment variable the engine reads, what it does, how hot its read is, and whether it should stay. The rule it is judged against ([CLAUDE.md](../CLAUDE.md)): an env lever exists only for a path with two arms worth comparing (lossy or a tradeoff), never for an obvious win or a fix, and a diagnostic env is read through `diagEnvOn` (absent or `0` = off), never `getenv != null`. Scope: `src/` at `eacf1f00` (the three served architectures and their shared code), minus the vars the Removed list under the cut list records; `HOME`, `TMPDIR` and the agent-launch scripts `sushi launch` writes are not levers and are left out. Tooling that only `scripts/` and `tests/` read is in the last table. Recommendations are proposals; where no measurement was found the row says so.

**Reading the columns.** *where* is file:line of each read site (non-test first). *hot path?* is `cached` (read once lazily on the served path), `boot` / `load` (once at startup or model load), `request` (once per request), `per-call` (an uncached `getenv` on a repeated path) or `test` (never on the served path). *documented?* is a hit in the public docs, `README.md` or `--help`. Flags that already cover a var are named in its row. Read semantics matter: a presence read (`!= null`, `envFlagCached`) treats `=0` as on; the rows that do this say so.

**Summary.** 254 vars. By kind: tradeoff levers 17, diagnostics 31, microbenches 62, test-only seams 43, paths and config 7, kill switches and sweep knobs 94. By recommendation: keep (env) 139, keep, fix read 27, promote to flag 0, merge 6, cut 82. 88 of 254 (35%) are cut or merge candidates; 27 keep but read uncached or by presence.

Cutting a kill switch has one cost: `tests/greedy_ab.sh` and `tests/prefill_ab.sh` take any env var as the arm switch, and a few integration scripts boot an off arm to prove an arm engaged (named in the rows). Move those to a flag or a test seam in the same change.

## Tradeoff levers (17)

Two arms that trade speed, memory or exactness, or a policy a user may want to move.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `MLX_ENABLE_TF32` | `glm5_kld_capture.zig:196, transformer.zig:4241` | default on: QSA score GEMM may use TF32 on NAX; `0` keeps f32. GLM teacher capture requires `0` | cached | yes: quality-kld, glm5-kernels, glm5-kld, ... | **keep (env)**: MLX's own switch, read by sushi too; load-bearing for the GLM KLD teacher (quality-kld) |
| `QWEN4_PLE_PREFETCH_PREFILL` | `qwen4_exp.zig:976` | wide n-gram gather arm: absent = kv gate (pool from 256k keys, serial walk below), `0` serial, `1` pool | cached | yes: qwen4-arch, qwen4-perf | **keep (env)**: both arms measured and the best one flips with table residency (qwen4-perf#ngram-arm, qwen4-arch); forcing is the A/B |
| `SUSHI_DECODE_ASYNC_LADDER` | `transformer.zig:15746, transformer.zig:15749` | unset: batched Qwen4 decode ladders every 4th layer, serial off; `0\|off` off, `auto` every 8th, `<n>` every n-th | boot | yes: qwen4-perf, engine-kernels | **keep (env)**: measured +12% per-stream at 4K batched (qwen4-perf#qwen4-decode-ladder); the serial arm is still unmeasured |
| `SUSHI_DFLASH_QUANT_BITS` | `dflash.zig:456` | affine width of the DFlash sidecar requant (default 8; `0\|off` dense bf16) | boot | no | **keep (env)**: draft-side quality/bytes tradeoff; no measurement of the other widths found, owner call |
| `SUSHI_GDN_PIPELINED` | `transformer.zig:568` | GDN prefill recurrence: unset = pipelined on NAX Qwen4, `0` keeps the blocked kernel, `1` forces pipelined; not bit-identical | cached | yes: engine-kernels | **keep (env)**: a real numerics/speed arm (engine-kernels); becomes the route selector if SUSHI_GDN_BLOCKED is merged into it |
| `SUSHI_KV_ATTN_MIN_TK` | `transformer.zig:14937` | per-layer kv-length floor for the fused quantized-attention kernel (default 2048) | cached | yes: tests/CLAUDE | **keep (env)**: correctness tests set it to 1 to force the arms (tests/test_kv_quant_fused_equivalence.sh); a test seam on the served path |
| `SUSHI_LMHEAD_FULL` | `transformer.zig:25134` | `1` reads the full lm_head instead of the greedy top-32 shortlist (not certified exact) | per-call | yes: engine-mtp | **keep, fix read**: the exactness escape for a measured lossy default (engine-mtp#greedy-shortlist); `diagEnvOn` per greedy forward, cache it |
| `SUSHI_LOOP_TRIM` | `scheduler.zig:6249` | default on: trims displayed loop-stop replies; `0` keeps the whole degenerate tail for strict bytes | cached | yes: server-http-apis, tests/CLAUDE | **keep (env)**: presentation/exactness tradeoff documented in server-http-apis; tests/test_loop_stop_signal.sh uses it |
| `SUSHI_MTP_ADAPTIVE_SERIAL` | `generate.zig:10102` | default on; `0` disables the adaptive speculate-vs-serial vote at long KV | cached | yes: mimo2-perf, tests/CLAUDE | **keep (env)**: a real spec-vs-serial tradeoff measured on MiMo and Qwen (mimo2-perf#mimo-adaptive-serial); tests/test_mtp_adaptive.sh boots both arms |
| `SUSHI_MTP_DENSE_ROWS` | `mtp_dense_rows.zig:10` | `1` runs the dense-row router GEMV for MTP verify rows (default off) | cached | yes: qwen4-perf, engine-mtp | **keep (env)**: read +2-3% on Qwen but one equivalence run failed and seven reruns passed (engine-mtp#reproducibility); unresolved, owner call: re-run the gate then land or cut |
| `SUSHI_MTP_DRAFT_HEAD_BITS` | `mimo_mtp.zig:33, mtp.zig:841` | draft-only lm_head requant width (default 3, MiMo 2, `0\|off` disables); verification is untouched | boot | yes: mimo2-mtp | **keep (env)**: draft-side bytes/acceptance tradeoff, documented in mimo2-mtp; also read by tests/test_sushi_memory_billing.py |
| `SUSHI_MTP_HEAD_PERSIST` | `generate.zig:619` | default on: Qwen4 MTP head history rides the prefix cache; `0` turns it off | cached | yes: tests/CLAUDE | **keep (env)**: tests/test_qwen4_mtp_head_persist.sh needs the off arm and no flag exists; revisit if the arm is retired |
| `SUSHI_MTP_HEAD_QUANT_BITS` | `mtp.zig:1811` | requant width of dense MTP head trunks at load (default 4, g64; `0` off) | boot | yes: engine-mtp | **keep (env)**: memory/acceptance tradeoff, documented in engine-mtp |
| `SUSHI_NGRAM_WARM` | `qwen4_exp.zig:146` | default on: pread the Flash-Next n-gram table at load; `0` skips it | cached | yes: qwen4-arch, qwen4-perf | **keep (env)**: residency-for-prefill tradeoff with measured arms that flip with page-cache state (qwen4-perf#ngram-arm) |
| `SUSHI_PREFILL_INTERLEAVE` | `scheduler.zig:6646` | default on: a cold prefill yields to decode streams; `0` restores run-to-completion and drops the share cap | cached | yes: server-lifecycle, tests/CLAUDE | **keep (env)**: the off arm is the byte-identity reference of `tests/test_prefill_interleave.sh` (owner rule: an env a correctness test depends on stays); read once and cached |
| `SUSHI_QSA_SCORE_SHEET_MB` | `transformer.zig:6468` | QSA block-score sheet budget in MB (default 256); the memory bill reads it too | cached | no | **keep (env)**: memory-for-speed tradeoff billed in admission; logs when moved |
| `SUSHI_ROUND_COST_PERSIST` | `round_cost.zig:907` | `1` persists the measured MTP round-cost table across boots (default off) | request | yes: mimo2-perf, qwen4-perf, engine-mtp, ... | **keep (env)**: opt-in by design; benches that export `=0` are setting the default (tidy the scripts) |

## Diagnostics (31)

Log, trace or dump output; off by default.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `QWEN4_DEBUG_SCORES` | `qwen4_qsa.zig:1333, qwen4_qsa.zig:1382` | prints QSA pooled shapes and score rows | cached | no | **keep, fix read**: `envFlagCached` is presence-only: `=0` turns it on; read through `diagEnvOnCached` |
| `QWEN4_DUMP_QSA_BLOCKS` | `qwen4_qsa.zig:625` | `<path>` dumps the selected QSA block indices | cached | no | **keep (env)**: already `diagEnvValueOn`, read once |
| `QWEN4_FIXTURE_ROWS` | `transformer.zig` | prints per-row cos/margin in the Qwen4 fixture test | test | no | **keep (env)**: already `diagEnvOn` |
| `QWEN4_GDN_CHECK` | `transformer.zig:19328, transformer.zig:19471` | runs the composed GDN prework beside the fused kernel and compares | per-call | no | **keep, fix read**: second read (`diagEnvOn` per GDN layer per prefill chunk) is uncached; reuse `gdn_check_env` |
| `QWEN4_NO_POOLED` | `qwen4_qsa.zig:1241` | forces `QsaPooledRequired` to exercise the pooled-key fallback | cached | no | **keep, fix read**: presence-only read; use `diagEnvOnCached` |
| `QWEN4_OPCOUNT` | `qwen4_forward.zig:2916` | FFI op counts per block of the Qwen4 forward | per-call | no | **keep, fix read**: `diagEnvOn` in `Qwen4FwdProf.init`, once per forward; cache it |
| `QWEN4_PROFILE_FWD` | `qwen4_exp.zig:781, qwen4_forward.zig:1425, qwen4_forward.zig:2912, +3` | `1` times S 2..16 forwards per block with a sync each, `all` every S; also arms PLE read logging | per-call | no | **keep, fix read**: read uncached in `Qwen4FwdProf.init` (per forward), `qwen4VerifyRowsEligible` (per verify) and the PLE pool; the cache `qwen4_profile_fwd_env` exists |
| `QWEN4_PROFILE_QSA` | `qwen4_forward.zig:2473, qwen4_qsa.zig:1358` | logs synced QSA indexer/gather laps | per-call | no | **keep, fix read**: cached at qwen4_qsa.zig:1358 but `diagEnvOn` per layer at qwen4_forward.zig:2473; use the existing cache |
| `QWEN4_STANDIN` | `qwen4_forward.zig:2874` | comma list (`gdn,attn,mlp,hc,moe_*,...`) replaces blocks with free stand-ins for ablation under the decode meter | cached | yes: qwen4-perf, engine-kernels | **keep (env)**: documented method for decode attribution (engine-kernels); value list, read once |
| `QWEN4_STREAM_F32` | `qwen4_forward.zig:1489, qwen4_forward.zig:1751, qwen4_forward.zig:1935` | runs the Qwen4 residual streams in f32 (math oracle) | cached | yes: qwen4-arch | **keep, fix read**: presence-only read (`envFlagCached`); use `diagEnvOnCached` |
| `SUSHI_DECODE_FWD_GRAPH` | `scheduler.zig:4485` | `<path>` writes one decode forward's primitive list at the fwd microbench | load | yes: mimo2-arch | **keep (env)**: tape dump for dispatch counting (mimo2-arch); inert without SUSHI_DECODE_FWD_UBENCH |
| `SUSHI_DECODE_PROFILE` | `transformer.zig:23254, transformer.zig:23262` | presence arms the decode sub-block profiler; `=<rows>` also times verify widths | cached | no | **keep, fix read**: `SUSHI_DECODE_PROFILE=0` reads as ON (`!= null`); use `diagEnvOnCached` |
| `SUSHI_DFLASH_TRACE` | `generate.zig:9283` | `1` per-phase DFlash round wall-time trace | cached | no | **keep (env)**: read once through `readEnvBool` (exactly `1`) |
| `SUSHI_DISPATCH_PROBE` | `transformer.zig:26243` | `<n>` injects n small dependent dispatches per forward to price a dispatch | cached | yes: mimo2-perf, tests/CLAUDE | **keep (env)**: documented price source (~1.7 us, mimo2-perf) |
| `SUSHI_DUMP_RESTORE` | `restore_dump.zig:31` | `<dir>` dumps prefix-restore tensors | cached | no | **keep (env)**: already `diagEnvValueOn`-style (empty/`0` off), read once |
| `SUSHI_EXL3_SWIGLU_MAXABS` | `exl3/expert_exl3_kernels.zig:104` | dumps SwiGLU activation maxima (f16 overflow hunt) | cached | yes: engine-exl3-experts | **keep (env)**: already `diagEnvValueOn`, read once |
| `SUSHI_EXL3_UNION_HIST` | `exl3/expert_exl3_kernels.zig:164` | logs per-layer expert-count histograms (`[exl3-counts]`) on prefill | cached | yes: engine-exl3-experts, qwen4-perf | **keep (env)**: already `diagEnvValueOn`; feeds the GEMM-arms replay |
| `SUSHI_EXPERT_DEFER_SYNC` | `qwen4_forward.zig:1974` | `1` forces synchronous expert verification for an exact schedule comparison | cached | yes: engine-expert-streaming | **keep (env)**: already `diagEnvOnCached`; documented in engine-expert-streaming |
| `SUSHI_FORCE_GPU_FAMILY_FALLBACK` | `exl3/expert_exl3_kernels.zig:1255, exl3/expert_exl3_kernels.zig:7497, transformer.zig:1829` | `1` pretends the matrix units are absent to rehearse the M1-M4 path on an M5 | per-call | yes: glm5-kernels, qwen4-perf, glm5-perf, ... | **keep, fix read**: QA rehearsal documented in glm5-kernels; `gemmNaxAvailable()` (EXL3) reads it before its cache on every dispatch |
| `SUSHI_KVQ_PARITY_TRACE`, `SUSHI_MIMO_VISION_DIAG` | `transformer.zig, mimo_vision.zig` | prints extra parity / vision diagnostics inside a test | test | no | **keep (env)**: already `diagEnvOn` |
| `SUSHI_LAYER_CAP` | `transformer.zig:23198` | `<n>` runs only the first n layers so a ms-vs-layers slope is measurable | cached | yes: tests/CLAUDE | **keep (env)**: used by tests/fwd_ubench.sh; read once |
| `SUSHI_LMHEAD_SHORTLIST_AUDIT` | `transformer.zig:16188` | `1` re-reads the full head on every shortlist row and counts disagreements | per-call | yes: mimo2-perf, engine-mtp | **keep, fix read**: `diagEnvOn` per greedy forward; cache it |
| `SUSHI_MOE_DUMP` | `transformer.zig:23344` | `<dir>` writes one forward's MoE tensors as raw f32 | cached | no | **keep (env)**: read once |
| `SUSHI_MOE_GATHER_TRACE`, `SUSHI_VQMM_PARITY_DEBUG`, `REPLAY_DUMP_SOFT` | `transformer.zig, tool_traffic_replay_test.zig` | extra prints inside a test (`!= null`) | test | no | **keep, fix read**: presence-only read; `=0` turns them on |
| `SUSHI_MTP_TRACE` | `generate.zig:9393, round_cost.zig:931` | `1` per-round MTP phase trace; also disarms round-cost persistence | cached | yes: mimo2-perf, qwen4-perf, tests/CLAUDE | **keep (env)**: read once (`readEnvBool`, exactly `1`); used by the perf docs and test_mtp_adaptive.sh |
| `SUSHI_MTP_TRACE_SYNC` | `generate.zig:7351` | drains the GPU before the verify build so the `sync` lap is separable | per-call | no | **keep, fix read**: presence-only, but only read while tracing |
| `SUSHI_PROFILE_ATTN` | `qwen4_forward.zig:3000` | `1` logs synced indexer/projection/QSA/tail laps per Qwen4 forward | cached | yes: qwen4-qsa-long-context | **keep (env)**: read once through `diagEnvOn` |
| `SUSHI_RAW_DUMP_FILE` | `server.zig:12011, server.zig:17273` | `<abs path>` appends the full pre-parse buffer of every tools request | request | yes: server-tool-calling, CLAUDE.md | **keep (env)**: corpus-harvest aid; only read at debug log level, per tool request |

## Microbenches (62)

In-process meters. Load-time meters run on the served binary; the rest are `#[test]` gates that skip when unset.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `SUSHI_ATTN_PD_UBENCH`, `SUSHI_ATTN_PD_UBENCH_ABL`, `SUSHI_ATTN_PD_UBENCH_ABL_KL`, `SUSHI_ATTN_PD_UBENCH_ALT`, `SUSHI_ATTN_PD_UBENCH_BUDGETS`, `SUSHI_ATTN_PD_UBENCH_KL`, `SUSHI_ATTN_PD_UBENCH_LEAN`, `SUSHI_ATTN_PD_UBENCH_QL`, `SUSHI_ATTN_PD_UBENCH_REPS` | `transformer.zig` | MiMo prefill-attention chunk meter and its sweep lists (gate + ablation, kv lengths, budgets, reps) | test | yes: mimo2-perf, engine-kernels | **keep (env)**: documented in mimo2-perf/engine-kernels; `_ALT` reads with a bare `getenv` |
| `SUSHI_DECODE_FWD_UBENCH` | `scheduler.zig:4339` | `<n>` times n decode-width forwards at load (no sampling, no cache bookkeeping), then resets the KV | load | yes: mimo2-arch, mimo2-perf, qwen4-perf, ... | **keep (env)**: the repo's decode A/B unit (tests/fwd_ubench.sh, perf-baselines) |
| `SUSHI_DECODE_FWD_UBENCH_GDN_ARMS` | `scheduler.zig:4390` | off,on,on,off passes of the GDN chain vs the fused step | load | yes: engine-kernels | **keep, fix read**: presence-only (`!= null`) |
| `SUSHI_DECODE_FWD_UBENCH_GDN_FOLD_ARMS` | `scheduler.zig:4392` | off,on,on,off passes of the verify fold | load | yes: qwen4-perf, engine-kernels | **keep (env)**: same-process A/B seam (`diagEnvOn`) |
| `SUSHI_DECODE_FWD_UBENCH_GLOBAL_ROWS_ARMS` | `scheduler.zig:4408` | MiMo global verify rows one dispatch each vs grouped | load | no | **keep (env)**: same-process A/B seam |
| `SUSHI_DECODE_FWD_UBENCH_KV` | `scheduler.zig:4365` | `<tokens>` prefill before timing | load | no | **keep (env)**: sub-option of the fwd meter |
| `SUSHI_DECODE_FWD_UBENCH_LMHEAD_ARMS` | `scheduler.zig:4405` | argmax-only forwards on full head vs shortlist | load | no | **keep (env)**: same-process A/B seam |
| `SUSHI_DECODE_FWD_UBENCH_PROFILE` | `scheduler.zig:4363` | one extra profiled pass per width | load | no | **keep, fix read**: presence-only (`!= null`) |
| `SUSHI_DECODE_FWD_UBENCH_QKV_PREP_ARMS` | `scheduler.zig:4400` | MiMo composed rope+kv8 quantize vs one-dispatch prep | load | yes: mimo2-arch | **keep (env)**: same-process A/B seam |
| `SUSHI_DECODE_FWD_UBENCH_QSA_POOL_ARMS` | `scheduler.zig:4396` | composed QSA pooled-key chain vs fused kernel | load | yes: qwen4-qsa-long-context | **keep (env)**: same-process A/B seam |
| `SUSHI_DECODE_FWD_UBENCH_ROW_ARMS` | `scheduler.zig:4387` | MiMo verify width run prefill-shaped, then as rows | load | no | **keep, fix read**: presence-only (`!= null`) |
| `SUSHI_DECODE_FWD_UBENCH_S` | `scheduler.zig:4353` | `<rows>[,...]` verify widths to time | load | yes: perf-baselines | **keep (env)**: sub-option of the fwd meter |
| `SUSHI_DECODE_TICK_UBENCH` | `exl3/expert_exl3_kernels.zig:1221, generate.zig:94` | `<n>` times n decode ticks end to end | cached | no | **keep (env)**: already `diagEnvValueOn`, read once |
| `SUSHI_EXL3_CODEBOOK_AB`, `SUSHI_EXL3_GEMM_ARMS`, `SUSHI_EXL3_LOWK_UBENCH` | `exl3/expert_exl3_kernels.zig` | EXL3 codebook A/B, served-vs-reference GEMM arms, low-rate decode chain | test | yes: engine-exl3-experts, mimo2-perf | **keep (env)**: documented in engine-exl3-experts |
| `SUSHI_EXL3_GEMM_COUNTS` | `exl3/expert_exl3_kernels.zig` | `<file>` replays per-layer expert counts (`[exl3-counts]`) into the GEMM-arms meter | test | yes: engine-exl3-experts | **keep (env)**: documented in engine-exl3-experts |
| `SUSHI_EXL3_LAYER_UBENCH` | `exl3/expert_exl3_kernels.zig:82, transformer.zig:29871` | prints per-stage EXL3 expert timings (adds syncs) | cached | yes: engine-exl3-experts, qwen4-perf, CLAUDE.md | **keep (env)**: already `diagEnvValueOn`, read once; named in CLAUDE.md as the diagnostic example |
| `SUSHI_FP8_UBENCH`, `SUSHI_FP8_UBENCH_SHAPE`, `SUSHI_FP8_UBENCH_SWEEP` | `fp8_block.zig` | FP8 trunk GEMV meter (`<reps>`, shape filter, `direct` sweep) | test | yes: mimo2-perf | **keep (env)**: documented in mimo2-perf |
| `SUSHI_GDN_UBENCH`, `SUSHI_LMHEAD_UBENCH`, `SUSHI_MOE_GATHER_UBENCH`, `SUSHI_PREFILL_QMM_UBENCH`, `SUSHI_VERIFY_WIDTH_UBENCH`, `SUSHI_VQMM_MIXED_UBENCH`, `SUSHI_VQMM_UBENCH` | `transformer.zig` | GDN, lm_head, gather-qmv, prefill qmm, verify-width and verify-qmm meters | test | no | **keep, fix read**: gated by presence (`getenv == null` / `orelse`): `=0` runs the bench; use `diagEnvOn` |
| `SUSHI_GLM_ARMS_UBENCH`, `SUSHI_GLM_ATTN_UBENCH`, `SUSHI_GLM_LONGCTX_UBENCH`, `SUSHI_GLM_LONGCTX_UBENCH_CTX`, `SUSHI_GLM_LONGCTX_UBENCH_REPS`, `SUSHI_GLM_QMM_UBENCH` | `glm5_model.zig, glm5_attention.zig, glm5_dflash_qmm.zig` | GLM NAX-arm, sparse-attention, long-context and qmm meters (+ ctx/reps lists) | test | yes: glm5-perf, glm5-kernels | **keep (env)**: documented in glm5-perf/glm5-kernels |
| `SUSHI_GLM_ROUND_UBENCH` | `scheduler.zig:4613, scheduler.zig:6506` | `<n>` greedy DFlash2 rounds per arm at load | load | yes: glm5-perf | **keep (env)**: GLM round meter (glm5-perf) |
| `SUSHI_GLM_ROUND_UBENCH_CTX` | `scheduler.zig:6507` | context list in tokens | load | no | **keep (env)**: sub-option |
| `SUSHI_GLM_ROUND_UBENCH_TEXT` | `scheduler.zig:6510` | `<file>` text prompt | load | no | **keep (env)**: sub-option |
| `SUSHI_GLM_ROWS_UBENCH` | `scheduler.zig:4331, scheduler.zig:6486` | `<n>` rounds per width B in 1..4 of plain decode at load | load | yes: glm5-kernels, perf-baselines | **keep (env)**: GLM grouped-rows meter (glm5-kernels) |
| `SUSHI_GLM_ROWS_UBENCH_CTX` | `scheduler.zig:6487` | context list in tokens | load | no | **keep (env)**: sub-option |
| `SUSHI_GLM_ROWS_UBENCH_TEXT` | `scheduler.zig:6490` | `<file>` text prompt | load | no | **keep (env)**: sub-option |
| `SUSHI_KVQ_MPP_UBENCH`, `SUSHI_KVQ_MPP_UBENCH_KV4`, `SUSHI_KVQ_SPLITK_UBENCH`, `SUSHI_KVQ_UBENCH` | `transformer.zig, kv_quant.zig` | quantized-KV attention meters (`_KV4` switches the 8-bit meter to 4-bit) | test | no | **keep (env)**: undocumented; same shape as the rest |
| `SUSHI_MIMO_ROWS_UBENCH`, `SUSHI_MIMO_VISION_UBENCH`, `SUSHI_QWEN_VISION_UBENCH` | `transformer.zig, mimo_vision.zig, qwen_vision.zig` | MiMo verify-rows attention meter, MiMo-ViT and Qwen vision encoder meters (`<reps>`) | test | yes: mimo2-perf, tests/CLAUDE | **keep (env)**: MIMO_ROWS documented in mimo2-perf; vision meters in tests/CLAUDE |
| `SUSHI_PREFILL_UBENCH` | `scheduler.zig:4330, scheduler.zig:6528` | `<n>` cold one-chunk prefills per arm at load | load | yes: mimo2-perf, qwen4-perf, engine-kernels | **keep (env)**: prefill meter (mimo2-perf, engine-kernels) |
| `SUSHI_PREFILL_UBENCH_ARMS` | `scheduler.zig:6548` | arm list for the prefill meter | load | no | **keep (env)**: sub-option |
| `SUSHI_PREFILL_UBENCH_ROWS` | `scheduler.zig:6529` | chunk rows (capped at the admitted chunk, default 2025) | load | no | **keep (env)**: sub-option |
| `SUSHI_PREFILL_UBENCH_TEXT` | `scheduler.zig:6539` | `<file>` real text instead of synthetic ids | load | no | **keep (env)**: sub-option |
| `SUSHI_SWA_FUSED_UBENCH`, `SUSHI_QSA_PREFILL_UBENCH`, `SUSHI_QSA_WIDE_UBENCH` | `transformer.zig` | sliding-window fused kernel and QSA prefill/wide meters | test | no | **keep (env)**: undocumented |

## Test-only seams (43)

Inputs and hooks that real-pack tests and scripts use.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `DFLASH_FIXTURES`, `DFLASH_ASSISTANT_DIR`, `DFLASH2_FIXTURES`, `DFLASH2_ASSISTANT_DIR` | `dflash.zig` | DFlash oracle fixtures and sidecar dirs | test | no | **keep (env)**: set by tests/dump_dflash*_fixtures.py |
| `MIMO_V2_MODEL`, `MIMO_V2_SOURCE`, `MIMO_V2_FIXTURE`, `MIMO_V2_MTP_FIXTURE`, `MIMO_VISION_ORACLE`, `MIMO_STREAM_FIXTURE`, `MIMO_SLICED_REAL_FIXTURE`, `MIMO_SLICED_OUTPUT`, `MIMO_DIFFERENTIAL_FIXTURE`, `MIMO_DIFFERENTIAL_LAYER`, `MIMO_DIFFERENTIAL_PACK`, `MIMO_PACK_REFERENCE` | `generate.zig, mimo_mtp.zig, transformer.zig, chat.zig, mimo_vision.zig, model.zig, model_discovery.zig` | MiMo pack, source checkpoint and oracle-fixture inputs for real-pack tests | test | yes: tests/CLAUDE, mimo2-arch | **keep (env)**: tests skip without them; most undocumented |
| `MTP_TEST_MODEL`, `MTP_LMHEAD_TEST_FILE`, `SINGLE_MTP_TEST_CONTEXT` | `generate.zig, transformer.zig` | MTP real-pack tests (pack, lm_head blob, context length) | test | yes: tests/CLAUDE | **keep (env)**: tests skip without them |
| `QWEN4_FIXTURE`, `QWEN4_FIXTURE_BF16`, `QWEN4_FIXTURE_VISION`, `QWEN4_ROWS_OLD`, `QWEN4_TEST_HF_MODEL`, `QWEN4_TEST_PREFIX_TOKENS`, `QWEN4_VERIFY_BENCH`, `QWEN4_YARN_FIXTURES`, `QWEN4_BF16_STREAM_MODEL` | `transformer.zig, mrope.zig, expert_io.zig` | oracle fixtures, HF source dir and probe switches for the Qwen4 oracle tests | test | yes: tests/CLAUDE | **keep (env)**: fixture dumpers set them; documented in tests/CLAUDE |
| `QWEN4_TEST_MODEL` | `generate.zig, mtp.zig, transformer.zig` | `<pack dir>` for ~30 real-pack Qwen4 tests | test | yes: server-lifecycle, mlx-serve-sync, tests/CLAUDE | **keep (env)**: generic-looking but documented (tests/CLAUDE, server-lifecycle); tests skip without it |
| `QWEN_VISION_TEST_MODEL`, `QWEN_VISION_FIXTURE`, `QWEN_PREPROCESS_FIXTURE`, `QV_GH`, `QV_GW`, `QWEN_MID_SYSTEM_MODEL_DIR` | `qwen_vision.zig, chat.zig` | Qwen vision/preprocess oracle inputs and a chat-template pack | test | yes: server-tool-calling, tests/CLAUDE | **keep (env)**: tests skip without them; `QV_*` is a two-letter unprefixed name |
| `SUSHI_FORCE_BATCHED` | `scheduler.zig:1461` | `1` routes single-slot ticks through the batched kernel | boot | yes: tests/CLAUDE | **keep (env)**: test hook; tests/test_batched_equivalence.sh |
| `SUSHI_MEMORY_AUDIT_MODEL`, `SUSHI_TOKENIZER_PARITY_FIXTURE` | `scheduler.zig, server.zig, tokenizer.zig` | memory-bill audit pack and tokenizer parity fixture | test | no | **keep (env)**: tests/test_tokenizer_reference.sh sets the fixture |
| `SUSHI_MLX_FAULT_CHUNK` | `mlx.zig:911` | `<n>` latches a synthetic Metal OOM at the n-th prefill-chunk check | cached | yes: tests/CLAUDE | **keep (env)**: release-build fault injection for tests/test_mlx_error_recovery.sh |
| `SUSHI_MLX_FAULT_STEP` | `mlx.zig:912` | `<n>` same, at the n-th decode step | cached | no | **keep (env)**: same script |
| `SUSHI_MODELS_DIR` | `test_models.zig:7` | root for real-pack tests and scripts (`${SUSHI_MODELS_DIR:-~/.sushi/models}`) | test | yes: CLAUDE.md, tests/CLAUDE | **keep (env)**: the engine itself does not read it (`--model-dir` and `~/.sushi/models` do); test_models.zig and ~100 scripts do |
| `SUSHI_NO_SUCH_DIAG_SWITCH_PROBE` | `transformer.zig` | unit probe that `diagEnvOnCached` honors `0`/empty/set | test | no | **keep (env)**: the guard for the `diagEnvOn` rule |
| `SUSHI_UPDATE_API` | `update.zig:28` | replaces `https://api.github.com` for the update check | request | yes: server-lifecycle, tests/CLAUDE | **keep (env)**: documented test-only hook for tests/test_self_update.sh |

## Paths and config (7)

A path, a credential or an output location.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `HF_TOKEN` | `cli.zig:295` | Bearer token added to `sushi pull` downloads | boot | no | **keep (env)**: standard Hugging Face convention; no flag; add one line to usage docs |
| `SUSHI_HIDDEN_OUT` | `hidden_capture.zig:23` | `<abs dir>` enables hidden-state block-boundary capture | boot | yes: quality-kld, engine-expert-streaming, glm5-arch | **keep (env)**: private tooling |
| `SUSHI_HIDDEN_SPOOL_BYTES` | `hidden_capture.zig:24` | spool budget for hidden-state capture windows | boot | yes: quality-kld | **keep (env)**: private tooling |
| `SUSHI_HIDDEN_SPOOL_FIRST` | `hidden_capture.zig:25` | first spool window index | boot | yes: quality-kld | **keep (env)**: private tooling |
| `SUSHI_IMATRIX_OUT` | `imatrix.zig:34` | `<abs>.safetensors` enables expert-imatrix capture | boot | yes: quality-kld, engine-expert-streaming | **keep (env)**: private tooling |
| `SUSHI_NGRAM_BF16_DIR` | `model.zig:1174` | serves a Flash-Next pack with the original bf16 n-gram table (KLD isolation) | boot | yes: quality-kld, qwen4-arch, engine-expert-streaming | **keep (env)**: quality-gate input, documented |
| `SUSHI_PREFIX_CACHE_DIR` | `kv_disk_cache.zig:4332` | absolute directory for the SSD prefix cache (default under `~/.sushi`) | boot | yes: engine-prefix-cache, --help | **keep (env)**: a path, documented, named in `--help`; tests give each boot a private one |

## Kill switches and sweep knobs for adopted arms (94)

An old arm kept reachable by an env, or a constant that was swept and then fixed.

| var | where | default → effect | hot path? | documented? | recommendation |
|---|---|---|---|---|---|
| `DFLASH_GATE_WARMUP` | `generate.zig:2117` | rounds before the DFlash acceptance gate may trip (default 8, 1..64) | per-call | no | **cut**: sweep knob; `getenv` per DFlash round; unprefixed name |
| `QWEN4_NO_HCFUSE` | `qwen4_forward.zig:321` | presence skips `mlx_compile` of the four HC elementwise tails | load | no | **cut**: compile is the obvious win; read once at load but presence-only |
| `QWEN4_PLE_PREFETCH` | `qwen4_exp.zig:865` | `0` disables the n-gram prefetch pool | cached | yes: qwen4-arch | **cut**: pool 11x over a serial cold walk (qwen4-perf#ngram-arm); kill switch |
| `QWEN4_PLE_PREFETCH_PREFILL_MIN_KV` | `qwen4_exp.zig:964` | kv threshold of the wide-gather arm (default 262144) | cached | no | **cut**: sweep knob; calibration picks the arm per load (qwen4-arch) |
| `SPEC_GATE_WARMUP` | `generate.zig:2046` | attempts before the PLD acceptance gate may trip (default 5, 1..64) | per-call | no | **cut**: sweep knob with the constant chosen; `getenv` on each gate call |
| `SPEC_YIELD_WARMUP` | `generate.zig:2159` | steps before the PLD yield gate may trip (default 8, 1..256) | per-call | no | **cut**: sweep knob, "yield-gate warmup is 8" test holds the sweep; `getenv` per PLD step |
| `SUSHI_ATTN_PD_NAX` | `transformer.zig:2716` | `0` keeps the SIMD kernel for MiMo 192/128 prefill attention on NAX | cached | yes: mimo2-arch, engine-kernels | **cut**: NAX arm ~3x per global layer (mimo2-arch); kill switch |
| `SUSHI_DFLASH_MARKOV` | `generate.zig:9265` | `0` drafts a DSpark sidecar from uncorrected base logits | cached | no | **keep (env)**: kill switch of the default-on DSpark Markov chain, not an opt-in experiment (stopped, owner call); read once and cached |
| `SUSHI_DFLASH_SELECTOR` | `generate.zig:9272` | `0` forces the v1 draft arms on a DFlash2 sidecar | cached | no | **cut**: A/B-only kill switch of the shipped selector |
| `SUSHI_EXL3_GEMM_WIN` | `exl3/expert_exl3_kernels.zig:1163, exl3/glm_prefill_grid.zig:71` | prefill GEMM window rows (default 32) | per-call | yes: engine-exl3-experts | **keep, fix read**: documented window-geometry A/B lever; `glm_prefill_grid.tryMoe` reads it per MoE call |
| `SUSHI_EXL3_WIN_ALIGN` | `exl3/expert_exl3_kernels.zig:1176, exl3/glm_prefill_grid.zig:72` | `0` unaligns the prefill window | per-call | yes: engine-exl3-experts | **keep, fix read**: same lever; read per call in `glm_prefill_grid.tryMoe` |
| `SUSHI_EXPERT_BF16_KERNELS` | `transformer.zig:27805` | `0` restores the `gather_mm` composite for streamed bf16 experts | cached | yes: engine-expert-streaming | **cut**: kill switch of the adopted kernels (engine-expert-streaming) |
| `SUSHI_F16_NARROW_1D` | `model.zig:2952` | `0` stops narrowing 1-D f16 tables at load | load | no | **cut**: kill switch of an adopted load fix |
| `SUSHI_FUSED_256` | `transformer.zig:2812` | `0` disables the hd-256 `sushi_attn_p256` kernel | cached | yes: mimo2-arch, qwen4-perf | **keep (env)**: cited as a KLD rounding-only control (qwen4-perf); otherwise a kill switch, owner call |
| `SUSHI_FUSED_256_BUDGET` | `transformer.zig:2869` | kv-chunk dispatch budget (default 250M; `0` single dispatch) | cached | no | **cut**: sweep knob of a landed budget |
| `SUSHI_FUSED_256_CAUSAL` | `transformer.zig:2898` | `0` restores composed causal prefill | cached | no | **merge**: second switch for the same kernel; fold into SUSHI_FUSED_256 |
| `SUSHI_GDN_BLOCKED` | `transformer.zig:344` | `0` leaves the blocked-seq GDN prefill kernel | cached | no | **merge**: one of three GDN routes; fold into SUSHI_GDN_PIPELINED as a route selector |
| `SUSHI_GDN_BLOCK_T` | `transformer.zig:405` | block tokens of the blocked kernel (16, 32, 48; default 32) | cached | no | **cut**: sweep knob |
| `SUSHI_GDN_DECODE_FUSED` | `transformer.zig:24446` | `0` disables the fused GDN decode dispatch | cached | yes: engine-kernels | **cut**: bit-identical fused step is the default (engine-kernels); kill switch |
| `SUSHI_GDN_PREFILL_FUSED` | `transformer.zig:24518` | `0` disables the fused GDN prefill prework | cached | yes: engine-kernels | **cut**: kill switch of the adopted fusion |
| `SUSHI_GDN_PREWORK` | `transformer.zig:24432` | `0` disables the whole GDN prework kernel | cached | no | **cut**: kill switch, same family |
| `SUSHI_HC_FUSED` | `qwen4_hc.zig:791` | `0` composes the Qwen4 hyper-connection reads | cached | yes: qwen4-arch, engine-kernels | **cut**: fused read is the shipped arm (qwen4-arch); used by tests/qwen4_ab.sh |
| `SUSHI_HC_PREFILL` | `hc_prefill.zig:16` | `0` disables the fused HC prefill kernels | cached | yes: engine-kernels | **cut**: kill switch |
| `SUSHI_KV_ATTN_FUSED` | `transformer.zig:14917` | `0` disables fused quantized-KV attention | cached | yes: mimo2-arch | **keep (env)**: the only switch for MiMo's global-layer decode (`--kv-attn-mode` no longer reaches it, mimo2-arch); `--kv-attn-mode dense` covers the other archs only |
| `SUSHI_KV_ATTN_KERNEL` | `transformer.zig:13962` | `0` drops the decode kernel only | cached | no | **merge**: second switch under `--kv-attn-mode` |
| `SUSHI_KV_ATTN_VERIFY` | `transformer.zig:14230` | `0` drops the verify kernel | cached | yes: engine-kv-cache | **merge**: third switch under `--kv-attn-mode` (default is on regardless of silicon) |
| `SUSHI_KV_GROW` | `transformer.zig:7672` | `linear` restores linear KV growth | cached | no | **cut**: proportional growth is the win (1544 MB vs 274 MB pool in the code comment) |
| `SUSHI_KV_RESERVE` | `transformer.zig:7619` | `0` restores proportional growth past 32k | cached | yes: qwen4-qsa-long-context | **cut**: kill switch; admission bills assume the reserve |
| `SUSHI_MLX_ERROR_LATCH` | `mlx.zig:815` | `0` restores mlx-c's exit-on-error handler | boot | no | **cut**: kill switch of the #353 fix |
| `SUSHI_MOE_DOWN_REDUCE_FUSED` | `transformer.zig:27195` | `0` disables fused down+reduce | cached | no | **cut**: bit-identity pinned by a test; kill switch |
| `SUSHI_MOE_GATEUP_FUSED` | `transformer.zig:26597` | `0` disables the fused gate+up+SwiGLU kernel | cached | no | **cut**: kill switch of the shipped kernel |
| `SUSHI_MOE_GATHER_DECODE` | `transformer.zig:23758, transformer.zig:23766, transformer.zig:23784` | presence forces stock `gather_qmm` | cached | no | **cut**: A/B control arm of the adopted gather-qmv kernels; presence read |
| `SUSHI_MOE_ROUTER_FUSED` | `transformer.zig:22976` | `0` disables the fused router | cached | no | **cut**: kill switch |
| `SUSHI_MOE_ROWS_FUSED` | `transformer.zig:26797` | `0` disables the row-axis fused MoE for batched ticks | cached | no | **cut**: kill switch |
| `SUSHI_MTP_ADAPTIVE` | `generate.zig:9316` | `0` swaps the EV depth controller for the windowed one | cached | yes: engine-mtp, --help | **keep (env)**: `0` selects the windowed controller, a different depth algorithm that can also disable MTP; `--mtp-min-depth n --mtp-max-depth n` pins a depth but cannot express it |
| `SUSHI_MTP_ADAPTIVE_CONFIRM` | `generate.zig:10142` | votes before the adaptive serial switch (default 3, 1..64) | cached | no | **cut**: sweep knob |
| `SUSHI_MTP_ADAPTIVE_MARGIN` | `generate.zig:10111` | loss margin of the switch (default 0.05) | cached | no | **cut**: sweep knob |
| `SUSHI_MTP_ADAPTIVE_MIN_KV` | `generate.zig:10131, generate.zig:10132` | kv floor of the switch (default 32768 Qwen, 65536 MiMo) | cached | no | **cut**: sweep knob; presence read |
| `SUSHI_MTP_BATCHED` | `scheduler.zig:8726` | `0` disables the MiMo MTP crowd policy | cached | yes: mimo2-arch, mimo2-perf | **cut**: kill switch of the shipped policy (mimo2-arch) |
| `SUSHI_MTP_BATCH_CORR` | `generate.zig:6688` | `0` disables batched corrections | cached | no | **cut**: kill switch |
| `SUSHI_MTP_COST_TABLE` | `generate.zig:8741` | `0` uses the prior only, no measured round costs | cached | yes: engine-mtp, tests/CLAUDE | **cut**: kill switch; the pinned-depth path avoids the table |
| `SUSHI_MTP_DRAFT_GREEDY` | `generate.zig:8199` | `1` greedy drafts always, `0` sampled always | cached | no | **cut**: A/B-only override of the per-request default |
| `SUSHI_MTP_DRAFT_RERANK` | `mtp.zig:890` | `0` full readout, `1` forces the coarse rerank (default auto) | load | yes: engine-mtp | **cut**: kill switch of the shipped rerank (engine-mtp) |
| `SUSHI_MTP_DRAFT_TEMP` | `generate.zig:8248` | draft temperature override (0.01..4) | cached | no | **cut**: "the sweep lever for the next head"; per-family value shipped |
| `SUSHI_MTP_EARLY_DISPATCH` | `generate.zig:9355` | `0` restores the serial round shape | cached | no | **cut**: kill switch (round pipelining) |
| `SUSHI_MTP_EV_COSTS` | `generate.zig:9455` | `draft,per_pos_lo,per_pos_hi,sync` overrides EV costs | request | no | **cut**: override of measured costs, read per request; no docs |
| `SUSHI_MTP_EV_SEED` | `generate.zig:9334` | `0` keeps request planning independent | cached | no | **cut**: kill switch of the cross-request EV seed |
| `SUSHI_MTP_EXT_DRY` | `generate.zig:9544` | `0` restores the fixed dry-spell gate | cached | no | **cut**: kill switch |
| `SUSHI_MTP_GROUP_PLANNER` | `mtp_group_planner.zig:431` | `0` disables the grouped-verify planner | cached | yes: engine-mtp, tests/CLAUDE | **cut**: kill switch of the shipped planner; `enable_batch_mtp:false` is the per-request opt-out |
| `SUSHI_MTP_KV_ONLY` | `mtp.zig:2885` | `0` restores the full-forward head history path | cached | no | **cut**: kill switch |
| `SUSHI_MTP_LIVECOST` | `generate.zig:9774` | `0` fixes the dry-exploration threshold | cached | no | **cut**: kill switch |
| `SUSHI_MTP_PREDRAFT` | `generate.zig:9375` | `0` disables cross-round pre-draft | cached | no | **cut**: kill switch (round pipelining) |
| `SUSHI_MTP_QWEN4_PROFILE` | `mtp.zig:360` | `0` revokes the measured Qwen4 cost profile | cached | yes: engine-mtp | **cut**: kill switch |
| `SUSHI_MTP_REGIME` | `generate.zig:9757` | `0` disables the regime gate | cached | no | **cut**: kill switch |
| `SUSHI_NAX_SDPA` | `transformer.zig:1858` | `0` restores `sushi_attn_p256` for hd-256 causal prefill | cached | yes: engine-kernels | **cut**: stock NAX sdpa is the shipped hd-256 arm (engine-kernels); kill switch |
| `SUSHI_PREFILL_CHUNK_ADAPTIVE` | `server.zig:6939` | `0` turns off the per-chunk adaptive width | request | no | **cut**: kill switch |
| `SUSHI_PREFILL_CHUNK_CTX_BAR` | `server.zig:3488` | `0` drops the ctx bar from the rung gate | cached | no | **cut**: kill switch |
| `SUSHI_PREFILL_CHUNK_PER_REQUEST` | `server.zig:6821` | `0` restores the load-time chunk pin | request | yes: engine-memory-admission, mimo2-arch | **cut**: kill switch (engine-memory-admission) |
| `SUSHI_PREFILL_DQ_GEMM` | `transformer.zig:28082` | `0` disables the dequant + GEMM prefill route | cached | no | **cut**: kill switch |
| `SUSHI_PREFIX_SSD_FIRST` | `prefix_cache.zig:422` | `0` restores RAM-first prefix caching | cached | no | **cut**: SSD-first is the owner-set default; kill switch |
| `SUSHI_QK_NORM_ROPE_FUSED` | `transformer.zig:23991` | `0` disables the fused QK-norm + RoPE kernel | cached | no | **cut**: kill switch |
| `SUSHI_QSA_ATTN_BALANCED` | `transformer.zig:5005` | `1` balances tile remainders (default off) | cached | no | **cut**: "invalidates the sweep" (transformer.zig:5000); sweep knob |
| `SUSHI_QSA_ATTN_BK` | `transformer.zig:4995` | tile depth 8..32 (default 16) | cached | no | **cut**: sweep knob |
| `SUSHI_QSA_ATTN_KERNEL` | `transformer.zig:5043` | `0` declines the split-K kernel | cached | yes: qwen4-qsa-long-context | **cut**: kill switch (qwen4-qsa-long-context) |
| `SUSHI_QSA_ATTN_MIN_S` | `transformer.zig:4929` | lowest query width the fused kernel serves (default 1) | cached | yes: qwen4-qsa-long-context | **cut**: floor knob; tests/test_qwen4_exp.sh sets it, move that to a seam |
| `SUSHI_QSA_ATTN_NSPLIT` | `transformer.zig:4918` | forces the split count (default 16) | cached | no | **cut**: sweep knob |
| `SUSHI_QSA_BATCHED_GATHER` | `transformer.zig:3217` | `0` disables the batched gather | cached | no | **cut**: kill switch; tests/bench_batched_qsa_gather.sh uses it |
| `SUSHI_QSA_DECODE_GATHER` | `transformer.zig:3203` | `0` restores the dense decode mask arm | cached | no | **cut**: kill switch |
| `SUSHI_QSA_FUSED` | `transformer.zig:3076` | `0` restores the stock array-mask sdpa | cached | no | **cut**: kill switch |
| `SUSHI_QSA_GATHER` | `transformer.zig:3143` | `0` restores the dense [S, kv] prefill mask arm | cached | no | **cut**: kill switch |
| `SUSHI_QSA_GATHER_BK` | `transformer.zig:3184` | gather key tile 16 or 32 (default 32) | cached | no | **cut**: sweep knob |
| `SUSHI_QSA_GATHER_MIN_KV` | `qwen4_qsa.zig:69, transformer.zig:3160` | kv floor of the prefill gather | cached | no | **merge**: one of two gather floors; keep a single floor var if any |
| `SUSHI_QSA_HISTORY_SHARE` | `transformer.zig:3248` | `0` restores the end-of-prefill QSA history copy | cached | no | **cut**: kill switch; the bill assumes one copy |
| `SUSHI_QSA_NAX` | `transformer.zig:3477, transformer.zig:3564` | `0` disables the NAX QSA path | cached | no | **cut**: kill switch; used by tests/test_qsa_nax_prefill.py |
| `SUSHI_QSA_SCORE_FUSED` | `transformer.zig:4175` | `0` composes the score sheet | cached | yes: qwen4-qsa-long-context | **cut**: kill switch (qwen4-qsa-long-context) |
| `SUSHI_QSA_SELECT_KERNEL` | `transformer.zig:4115` | `0` restores the argpartition chain | cached | no | **cut**: kill switch |
| `SUSHI_QSA_SELECT_SPLIT` | `transformer.zig:4134` | `0` disables the split select | cached | yes: qwen4-qsa-long-context | **cut**: kill switch (qwen4-qsa-long-context) |
| `SUSHI_QSA_SELECT_TG` | `transformer.zig:4057` | select threads 256, 512 or 1024 | cached | no | **cut**: sweep knob ("the A/B") |
| `SUSHI_QSA_VERIFY_GATHER` | `transformer.zig:5785` | `0` restores the dense verify mask | cached | no | **cut**: kill switch |
| `SUSHI_QSA_VERIFY_GATHER_MIN_KV` | `transformer.zig:5811` | kv floor of the verify gather (32768 dense, 16384 quantized) | cached | no | **merge**: second gather floor; merge with SUSHI_QSA_GATHER_MIN_KV |
| `SUSHI_RESTORE_MOVE` | `prefix_cache.zig:440` | `0` restores the refcount-share restore | cached | no | **cut**: kill switch |
| `SUSHI_SDPA_SPLIT` | `transformer.zig:6804` | `0` disables the split causal/masked sdpa | cached | no | **cut**: kill switch |
| `SUSHI_SLIDING_BLOCK_TRIM` | `transformer.zig:7194` | `0` disables the sliding block-width trim | cached | no | **cut**: kill switch; test_dflash.sh uses it |
| `SUSHI_SSD_CHUNK_SHARE` | `kv_disk_cache.zig:4389` | `0` writes everything on commit | cached | no | **cut**: kill switch |
| `SUSHI_SSD_WRITE_THROUGH` | `scheduler.zig:6739` | `0` takes the write-through out of the prefill loop | cached | no | **cut**: kill switch |
| `SUSHI_SUPPRESS_RESERVED` | `generate.zig:1085` | `0` disables reserved-token suppression | load | no | **cut**: kill switch of a correctness fix |
| `SUSHI_SWIGLU_FUSED` | `transformer.zig:26142` | `0` disables the fused SwiGLU kernel | cached | no | **cut**: kill switch |
| `SUSHI_VERIFY_QMM` | `transformer.zig:1381` | `0` disables every verify-lane qmm kernel | cached | no | **cut**: kill switch of the shipped lanes |
| `SUSHI_VERIFY_QMM_MIXED_PLAIN` | `transformer.zig:1469` | `0\|1` forces the mixed-plain arms | cached | no | **cut**: A/B forcing knob |
| `SUSHI_VERIFY_QMM_NAX_MIN_M` | `transformer.zig:1950` | M floor of the NAX lane | cached | no | **cut**: "M5-day A/B knob"; sweep knob |
| `SUSHI_VERIFY_QMM_NAX_MIXED` | `transformer.zig:1908` | `0` disables NAX for mixed-bit packs | cached | no | **cut**: kill switch |
| `SUSHI_VISION_CHUNKED` | `generate.zig:1559` | `0` restores the whole-prompt vision prefill | cached | yes: tests/CLAUDE | **cut**: kill switch of the #197 fix; tests/test_vision_chunked_prefill.sh boots both arms |
| `SUSHI_VQMM_BN` | `transformer.zig:1158` | forced column tile | cached | no | **cut**: sweep knob |
| `SUSHI_VQMM_KPARTS` | `transformer.zig:1193` | forced K parts 1..8 | cached | no | **cut**: sweep knob |

## Cut list (82 cut, 6 merge)

The owner's actionable list, by subsystem and reason. `merge` rows are named with their target. If a field escape hatch for the adopted kernels is still wanted after this, one `SUSHI_KERNELS_OFF=<name,...>` can replace the whole kill-switch group.

### Speculation: MTP planner, drafting and DFlash (23)

- *kill switch of an adopted arm*: `SUSHI_MTP_BATCHED`, `SUSHI_MTP_BATCH_CORR`, `SUSHI_MTP_COST_TABLE`, `SUSHI_MTP_DRAFT_RERANK`, `SUSHI_MTP_EARLY_DISPATCH`, `SUSHI_MTP_EV_SEED`, `SUSHI_MTP_EXT_DRY`, `SUSHI_MTP_GROUP_PLANNER`, `SUSHI_MTP_KV_ONLY`, `SUSHI_MTP_LIVECOST`, `SUSHI_MTP_PREDRAFT`, `SUSHI_MTP_QWEN4_PROFILE`, `SUSHI_MTP_REGIME`
- *sweep or A/B-only knob*: `DFLASH_GATE_WARMUP`, `SPEC_GATE_WARMUP`, `SPEC_YIELD_WARMUP`, `SUSHI_DFLASH_SELECTOR`, `SUSHI_MTP_ADAPTIVE_CONFIRM`, `SUSHI_MTP_ADAPTIVE_MARGIN`, `SUSHI_MTP_ADAPTIVE_MIN_KV`, `SUSHI_MTP_DRAFT_GREEDY`, `SUSHI_MTP_DRAFT_TEMP`, `SUSHI_MTP_EV_COSTS`

### Attention and KV kernels (30)

- *kill switch of an adopted arm*: `SUSHI_ATTN_PD_NAX`, `SUSHI_KV_GROW`, `SUSHI_KV_RESERVE`, `SUSHI_NAX_SDPA`, `SUSHI_QK_NORM_ROPE_FUSED`, `SUSHI_QSA_ATTN_KERNEL`, `SUSHI_QSA_BATCHED_GATHER`, `SUSHI_QSA_DECODE_GATHER`, `SUSHI_QSA_FUSED`, `SUSHI_QSA_GATHER`, `SUSHI_QSA_HISTORY_SHARE`, `SUSHI_QSA_NAX`, `SUSHI_QSA_SCORE_FUSED`, `SUSHI_QSA_SELECT_KERNEL`, `SUSHI_QSA_SELECT_SPLIT`, `SUSHI_QSA_VERIFY_GATHER`, `SUSHI_SDPA_SPLIT`, `SUSHI_SLIDING_BLOCK_TRIM`
- *sweep or A/B-only knob*: `SUSHI_FUSED_256_BUDGET`, `SUSHI_QSA_ATTN_BALANCED`, `SUSHI_QSA_ATTN_BK`, `SUSHI_QSA_ATTN_MIN_S`, `SUSHI_QSA_ATTN_NSPLIT`, `SUSHI_QSA_GATHER_BK`, `SUSHI_QSA_SELECT_TG`
- *merge*: `SUSHI_FUSED_256_CAUSAL` into `SUSHI_FUSED_256`, `SUSHI_KV_ATTN_KERNEL` under `--kv-attn-mode`, `SUSHI_KV_ATTN_VERIFY` under `--kv-attn-mode`, `SUSHI_QSA_GATHER_MIN_KV` with `SUSHI_QSA_VERIFY_GATHER_MIN_KV` into one floor, `SUSHI_QSA_VERIFY_GATHER_MIN_KV` with `SUSHI_QSA_GATHER_MIN_KV` into one floor

### MoE, verify-qmm and expert kernels (14)

- *kill switch of an adopted arm*: `SUSHI_EXPERT_BF16_KERNELS`, `SUSHI_MOE_DOWN_REDUCE_FUSED`, `SUSHI_MOE_GATEUP_FUSED`, `SUSHI_MOE_ROUTER_FUSED`, `SUSHI_MOE_ROWS_FUSED`, `SUSHI_PREFILL_DQ_GEMM`, `SUSHI_SWIGLU_FUSED`, `SUSHI_VERIFY_QMM`, `SUSHI_VERIFY_QMM_NAX_MIXED`
- *sweep or A/B-only knob*: `SUSHI_MOE_GATHER_DECODE`, `SUSHI_VERIFY_QMM_MIXED_PLAIN`, `SUSHI_VERIFY_QMM_NAX_MIN_M`, `SUSHI_VQMM_BN`, `SUSHI_VQMM_KPARTS`

### Qwen4 GDN, hyper-connections and PLE (10)

- *kill switch of an adopted arm*: `QWEN4_NO_HCFUSE`, `QWEN4_PLE_PREFETCH`, `SUSHI_GDN_DECODE_FUSED`, `SUSHI_GDN_PREFILL_FUSED`, `SUSHI_GDN_PREWORK`, `SUSHI_HC_FUSED`, `SUSHI_HC_PREFILL`
- *sweep or A/B-only knob*: `QWEN4_PLE_PREFETCH_PREFILL_MIN_KV`, `SUSHI_GDN_BLOCK_T`
- *merge*: `SUSHI_GDN_BLOCKED` into `SUSHI_GDN_PIPELINED` as a route selector

### Memory, prefill, cache and load policy (11)

- *kill switch of an adopted arm*: `SUSHI_F16_NARROW_1D`, `SUSHI_MLX_ERROR_LATCH`, `SUSHI_PREFILL_CHUNK_ADAPTIVE`, `SUSHI_PREFILL_CHUNK_CTX_BAR`, `SUSHI_PREFILL_CHUNK_PER_REQUEST`, `SUSHI_PREFIX_SSD_FIRST`, `SUSHI_RESTORE_MOVE`, `SUSHI_SSD_CHUNK_SHARE`, `SUSHI_SSD_WRITE_THROUGH`, `SUSHI_SUPPRESS_RESERVED`, `SUSHI_VISION_CHUNKED`

### Removed

Cut from the list and from the code; the tables above no longer carry them.

- *dead or leftover*: `CODEX_SANDBOX`, `HY3_MODEL_DIR`, `MINICPM5_MODEL_DIR`, `PERF_REPORT`, `REAL_BLOB`, `SUSHI_DSV4_DSPARK` (with the `--dspark` flag).
- *a flag already covers it*: `SUSHI_DFLASH` (`--no-drafter` skips the sidecar and its bill on every arm, GLM included), `SUSHI_MTP_TOKENV3` and `SUSHI_MTP_TYPICAL` (`--mtp-tokenv3`, `--mtp-typical`), `SUSHI_PREFILL_CHUNK` (`--prefill-chunk`; the env also bypassed the safety cap), `SUSHI_PREFILL_DECODE_SHARE` (`--prefill-decode-share`), `SUSHI_PREFILL_TRACE` (`--prefill-trace`), `SUSHI_DECODE_ATTN_QUANT` (`--decode-attn-quant`; the env outranked the flag).
- *the nvfp4 tail of `--decode-attn-quant`*: `SUSHI_DECODE_ATTN_QUANT_NVFP4_FROM`, with the tail itself (every side copy is the int8-g32 copy).
- *rejected, unmeasured or opt-in experiment* (env, the code arm it alone gated, and its tests): `SUSHI_DFLASH_CHOOSER`, `SUSHI_DFLASH_DRAFT_HEAD_BITS`, `SUSHI_DFLASH_SAMPLED_DRAFTS`, `SUSHI_MTP_ADAPTIVE_REENTRY_TOKENS`, `SUSHI_MTP_BATCHED_QWEN4`, `SUSHI_FUSED_QKV`, `SUSHI_LMHEAD_PRUNE`, `SUSHI_LMHEAD_PRUNE_TRACE`, `SUSHI_MOE_BATCHED_DECODE`, `SUSHI_MOE_VERIFY_PAIRED_GU`, `SUSHI_VERIFY_QMM_CROSSROW`, `SUSHI_ADD_RMSNORM_FUSED` (the gated entry only; the kernel stays, MiMo wires it), `SUSHI_COMPILE_FORWARD`.
- *promote-to-flag candidates, cut instead (the owner wants no new flags)*: `SUSHI_CACHE_LIMIT` (the cap is always `mlxCacheLimitBytes`, never raising a tighter one), `SUSHI_WIRED` and `SUSHI_WIRED_SLACK_MB` (the policy is always `max`). `SUSHI_PREFILL_INTERLEAVE` is kept, see its row.
- *a flag is the same switch*: `SUSHI_NO_UPDATE_CHECK` (`--no-update-check`).
- *duplicate of another env*: `SUSHI_KVQ_FORCE_SPLITK` (`SUSHI_FORCE_GPU_FAMILY_FALLBACK=1` takes the same arm), `SUSHI_MOE_GATHER_QMV_OFF` (`SUSHI_MOE_GATHER_DECODE` gates both call sites), `SUSHI_VERIFY_QMM_NAX` (`SUSHI_VERIFY_QMM=0` or the fallback switch).

### Flag twins that are not equivalents

Kept because the flag cannot express what the env does: `SUSHI_KV_ATTN_FUSED` (MiMo's global-layer decode ignores `--kv-attn-mode`), `SUSHI_KV_ATTN_KERNEL` and `SUSHI_KV_ATTN_VERIFY` (each drops one kernel and falls to the composed packed-qmm chain, which `--kv-attn-mode dense`, a dense rebuild, is not), `SUSHI_MTP_ADAPTIVE` (selects the windowed controller; a pinned depth is not that algorithm), `SUSHI_PREFILL_CHUNK_ADAPTIVE` and `SUSHI_PREFILL_CHUNK_PER_REQUEST` (`--prefill-chunk` pins a width, it does not restore the load-time pin or switch the ladder off), `SUSHI_PREFIX_CACHE_DIR` (`--prefix-cache-disk` sets a size, not a directory), `SUSHI_MODELS_DIR` (tooling, not read by the engine).

### Not cut, but act

- **Fix the read** (cache it, or read through `diagEnvOn`/`diagEnvOnCached` so `=0` is off): `QWEN4_DEBUG_SCORES`, `QWEN4_GDN_CHECK`, `QWEN4_NO_POOLED`, `QWEN4_OPCOUNT`, `QWEN4_PROFILE_FWD`, `QWEN4_PROFILE_QSA`, `QWEN4_STREAM_F32`, `SUSHI_DECODE_FWD_UBENCH_GDN_ARMS`, `SUSHI_DECODE_FWD_UBENCH_PROFILE`, `SUSHI_DECODE_FWD_UBENCH_ROW_ARMS`, `SUSHI_DECODE_PROFILE`, `SUSHI_EXL3_GEMM_WIN`, `SUSHI_EXL3_WIN_ALIGN`, `SUSHI_FORCE_GPU_FAMILY_FALLBACK`, `SUSHI_GDN_UBENCH`, `SUSHI_LMHEAD_UBENCH`, `SUSHI_MOE_GATHER_UBENCH`, `SUSHI_PREFILL_QMM_UBENCH`, `SUSHI_VERIFY_WIDTH_UBENCH`, `SUSHI_VQMM_MIXED_UBENCH`, `SUSHI_VQMM_UBENCH`, `SUSHI_LMHEAD_FULL`, `SUSHI_LMHEAD_SHORTLIST_AUDIT`, `SUSHI_MOE_GATHER_TRACE`, `SUSHI_VQMM_PARITY_DEBUG`, `REPLAY_DUMP_SOFT`, `SUSHI_MTP_TRACE_SYNC`.
- **Per-call `getenv` on a repeated path** (cache first, the cheapest fix): `QWEN4_PROFILE_FWD`, `QWEN4_OPCOUNT`, `QWEN4_PROFILE_QSA`, `QWEN4_GDN_CHECK`, `SUSHI_LMHEAD_FULL`, `SUSHI_LMHEAD_SHORTLIST_AUDIT`, `SUSHI_FORCE_GPU_FAMILY_FALLBACK` (EXL3 prefill dispatch), `SUSHI_EXL3_GEMM_WIN` / `SUSHI_EXL3_WIN_ALIGN` (GLM prefill grid), and the three warmup knobs above.
- **Stale scripts**: benches that export `SUSHI_ROUND_COST_PERSIST=0` set the default (persistence is opt-in); `SUSHI_PADWASTE_ARM` and `SUSHI_QSA_NAX_PRECISION` are script-side only.

## Tooling-only variables

Read by `scripts/` and `tests/` (shell and Python), not by the engine. Engine vars the scripts export are in the tables above.

| var | used by | meaning |
|---|---|---|
| `SUSHI_BINARY`, `SUSHI_BIN` | ~50 `tests/*.sh`, bench scripts | the binary under test; a control binary must sit in `zig-out/bin/` for its rpath |
| `SUSHI_MODELS_DIR` | ~100 scripts, `src/test_models.zig` | pack root, `${SUSHI_MODELS_DIR:-$HOME/.sushi/models}/<pack>`; the engine does not read it |
| `SUSHI_TEST_MODEL`, `SUSHI_TEST_EXTRA_ARGS` | `integration_test.sh` and ~19 scripts | default model dir; extra server flags appended to every boot |
| `QWEN4_MODEL`, `QWEN4_EXP_MODEL`, `QWEN_MODEL`, `QWEN_VISION_MODEL`, `MIMO_MODEL`, `MIMO_MEDIA_MODEL`, `MIMO_STREAM_MODEL`, `MIMO_SSD_BUDGET_GB`, `GLM_MODEL`, `MTP_ADAPTIVE_MODEL`, `MTP_BATCHED_MODEL`, `MLX_HYBRID_MODEL`, `DFLASH_TEST_MODEL`, `DFLASH_TEST_DRAFTER` | per-script live tests | a per-script pack override that wins over `SUSHI_MODELS_DIR` |
| `DFLASH_TEST_PORT`, `DFLASH_ON_REQS`, `DFLASH_SKIP_DISK`, `QWEN4_AB_PORT`, `QWEN4_AB_OUT`, `BENCH_PORT`, `BENCH_MODEL`, `BENCH_OUT`, `BENCH_LABEL` | `test_dflash.sh`, `qwen4_ab.sh`, bench scripts | ports, labels and output roots |
| `GPU_LOCK_DIR`, `GPU_LOCK_OWNER`, `GPU_LOCK_POLL_S` | `scripts/gpu-lock.sh`, scripts that take the lock | lock directory, holder name, poll interval |
| `SUSHI_RUNS_DIR`, `RUNS_DIR`, `RUNS_ROOT`, `RUN_DIR`, `LLMPROBE`, `LLMPROBE_DIR`, `LLMPROBE_MJS` | bench and validator scripts | run output roots and the llmprobe checkout |
| `MTP_FORCE_ENABLE`, `MTP_EXPECT_AUTO_DEPTH`, `MTP_EXPECT_AUTO_PROFILE`, `MTP_TEST_OUTPUT_DIR`, `MIMO_BATCH_OUTPUT_DIR`, `SUSHI_PROMPT_MODEL`, `SUSHI_PROMPT_OUTPUT_DIR`, `MIMO_CLI_TEST_HOME`, `MIMO_CLI_TEST_TIMEOUT` | MTP, batched and CLI tests | expected profile/depth pins, output dirs, private HOME |
| `SUSHI_PADWASTE_ARM` | `test_batched_equivalence.sh` | opt-in pad-waste arm; not read by the engine |
| `SUSHI_QSA_NAX_PRECISION` | `qsa_nax_precision.py` | verbose mode of the Python precision harness; not read by the engine |
| `QWEN4_REF_DTYPE`, `QWEN4_TEACHER_FIXTURE`, `MIMO_V2_REF`, `MIMO_V2_FIXTURE_DEBUG`, `HF_HUB_OFFLINE`, `PYTHONPATH`, `KLD_JSON`, `QWEN_PREPROCESS_FIXTURE`-family (`QWEN_PREPROCESS_MIN_PIXELS`, `_MAX_PIXELS`, `_DOWNSCALE_*`) | `tests/dump_*_fixtures.py`, parity scripts | oracle dumpers and preprocessing parity inputs |
| `MLX_SRC`, `MLX_SHA`, `MLXC_SRC`, `MLXC_SHA`, `MLXC_PATCH`, `MLX_DEPLOYMENT_TARGET`, `MLX_STAGE`, `ZIG`, `ZIG_VERSION`, `GH_REPO` | `scripts/build-mlx.sh`, `fetch-zig.sh`, `release.sh` | pinned build inputs and release plumbing |
