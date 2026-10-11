# Launch flags

A flag exists for a setting a user picks: a real tradeoff (`--qwen-gdn fp32` for long-context precision at some speed cost, `--expert-pick-tolerance` for speed against exactness) or a fit to their own machine (`--mtp-min-depth` / `--mtp-max-depth` per Apple chip, memory and context limits). Operator settings qualify too: ports, API key, paths, logging. A flag that offers no real choice is bloat: a developer A/B switch, a kill switch for an adopted default, a rejected or never-measured experiment, a flag that does nothing, two flags that set the same thing, a flag whose every useful value is the default. A test that needs to force an arm gets a test seam or a temporary env knob ([envvar](envvar.md)), not a flag.

Precedence: an explicit flag outranks `model-settings.json`, which outranks the default ([server-lifecycle](server-lifecycle.md#settings)). A flag that mirrors a settings key adds the precedence and nothing else; that is not bloat by itself.

The map is the code's: every argument the parsers accept, at `main` 393228b9. `main.zig` is the one parser for `run`, `serve` and the bare `sushi [options]` form; `launch`, `update` and `kld` parse their own. `pull` and `list` take no flags.

**Reading the columns.** *default → effect* ends with the parse site. *who* is `user` (a tradeoff), `machine` (fits a Mac), `operator` (port, auth, paths, logging), `dev` (A/B, debug, bench), `test` (only a test needs it), `dead` (no effect left). *documented* names `help` (`sushi --help` or the subcommand's), `usage` (`docs/usage.md`), `README`, the topic docs, and how many `tests/` scripts pass it (`scripts/` counted apart); *hidden* means parsed but absent from `--help`. *recommendation* starts with `keep`, `cut`, `merge` (names the target) or `owner call` (the evidence that decides it is under [Owner calls](#owner-calls)).

**Summary.** 117 rows: 79 shared by `run`, `serve` and the bare form, 38 in `run`, `launch`, `update` and `kld`. By who: user 27, operator 27, machine 19, dev 33, dead 9, test 2. By recommendation: keep 87, cut 17, merge 3, owner call 10. Among the 79 shared rows: keep 51, cut 16, merge 3, owner call 9.

## Serving, network and auth

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--serve` | off → HTTP server mode; the headless `--serve --model-dir` form is what the app launches (main.zig:620) | operator | help, server-lifecycle; 123 tests | keep: the app depends on it; overlaps the `serve` subcommand only in spelling |
| `--host` | `127.0.0.1` → bind address, `0.0.0.0` opens the LAN (main.zig:617) | operator | help, server-lifecycle; 52 tests | keep |
| `--port` | `12345` → bind port (main.zig:614) | operator | help, server-lifecycle; 139 tests | keep |
| `--api-key` | none → required on every request, loopback exempt (main.zig:728) | operator | help, server-http-apis; 2 tests | keep |
| `--api-key-strict` | off → also require the key from loopback (main.zig:732) | operator | help; 1 test | keep: embedders on shared machines |
| `--api-key-env` | none → read the key from a named env var so argv does not carry it (main.zig:734) | operator | help, envvar; 0 tests | keep: the only way to keep the key out of the process table |
| `--metrics` | off → Prometheus `/metrics` and `/metrics.json` (main.zig:726) | operator | help, server-http-apis; 10 tests, 2 scripts | keep |
| `--max-concurrent` | `1` → only sizes the submit queue (`n + 32`) and floors the prefix-cache capacity; slots batch at any value (main.zig:913) | dead | hidden; server-lifecycle; 21 tests, 2 scripts | cut: the queue depth is fixed, batching is the model's answer, not this number |
| `--parent-pid` | none → exit when that pid dies (main.zig:811) | operator | help, server-http-apis; 1 test | keep: for a host that embeds the engine |
| `--timeout` | `300` → stall timeout in seconds, 0 = none (main.zig:690) | operator | help, server-http-apis; 1 test | keep |
| `--no-prevent-sleep` | off → allow idle sleep during inference (main.zig:697) | operator | help; 1 test | keep |
| `--gpu-warm-secs` | `60` → keep the GPU awake this long after a request (main.zig:953) | machine | help, server-lifecycle; 0 tests | keep: a power-against-latency choice |
| `--no-tool-autocorrect` | off → stop coercing tool-call arguments to the schema's types (main.zig:706) | dev | help, server-tool-calling; 0 tests | cut: kill switch of an adopted default, no test, no measurement |
| `--embedding-max-length` | `auto` = the model window → lower per-input ceiling for `/v1/embeddings` (main.zig:681) | operator | help; 0 tests | owner call |
| `--no-update-check` | off → never ask GitHub for a newer release (main.zig:818) | operator | help, server-lifecycle; 2 tests | keep |

## Model, memory and context

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--model` | `~/.sushi/models` default → model directory (main.zig:611) | operator | help, usage; 135 tests | keep |
| `--model-dir` | none → repeatable discovery root, up to 8 (main.zig:916) | operator | help, server-lifecycle; 27 tests | keep |
| `--max-resident-models` | `3` → cap on loaded models, bad value falls back to 3 (main.zig:933) | machine | help; 5 tests | keep |
| `--max-resident-mem` | `auto` = 80% of the wired limit → cap on summed resident bytes (main.zig:939) | machine | help, server-lifecycle; 0 tests | keep |
| `--idle-evict-secs` | off → unload a model idle this long (main.zig:959) | machine | help; 1 test | keep |
| `--ctx-size` | model max → context length; also `ctx_size` in settings (main.zig:663) | machine | help, usage, README; 40 tests | keep |
| `--config-overrides` | none → JSON deep-merged into every model's `config.json`, e.g. YaRN extension (main.zig:666) | user | help; 0 tests | keep: the context-extension lever; add a test |
| `--hf-overrides` | alias of `--config-overrides` (main.zig:667) | dead | help (as alias); 0 tests | merge into `--config-overrides`: a second name for the same setting |
| `--vision` / `--no-vision` | tower loads on a resident model, not on a streamed one → force it on or save its memory; also `vision` in settings (main.zig:693) | machine | help, README, topic docs; 17 tests | keep |
| `--skip-mem-preflight` | off → bypass the free-RAM check before a load (main.zig:699) | machine | help, engine-memory-admission, qwen4-perf; 0 tests | keep: the refusal text names it; the M2 Max runs need it |
| `--wired-margin-gib` | `1` → headroom under `iogpu.wired_limit_mb`, 1..32 (main.zig:898) | machine | help, README, engine-memory-admission; 0 tests | keep |
| `--ssd-budget-gb` | none → stream experts from SSD within a TOTAL resident target; also `ssd_budget_gb` in settings (main.zig:985) | machine | help, README, engine-expert-streaming; 9 tests | keep |
| `--expert-cache-gb` | none → stream experts with a fixed decimal-GB cache; outranks `--ssd-budget-gb` (main.zig:979) | machine | help, engine-expert-streaming; 1 test | owner call |
| `--expert-pick-tolerance` | `0` exact → swap a missed streamed expert for a cached one within n, 0..0.6 (main.zig:904) | user | help, README, engine-expert-streaming; 1 test | keep: a measured speed-for-exactness tradeoff |
| `--prefill-chunk` | `8192` → ceiling on tokens per prefill chunk, auto-capped per model (main.zig:824) | machine | help, usage, engine-memory-admission; 11 tests, 2 scripts | keep |
| `--prefill-decode-share` | `0` → target decode share of wall time during another request's prefill, 0..0.9 (main.zig:910) | user | help, server-lifecycle; 1 test | keep: latency of live streams against prefill speed |
| `--warmup-eager` / `--no-warmup-eager` | on → pre-fault weights and pre-compile at boot; the flag reaches the boot model only, a cold load always warms (main.zig:820) | test | hidden; 2 tests | cut: `--warmup-eager` is the default, `--no-warmup-eager` only shortens test boots |
| `--no-safety` | accepted and ignored (main.zig:701) | dead | hidden; 0 tests | cut: a no-op kept for launchers that no longer exist in this tree |

## KV and attention

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--kv-quant` | `8` → KV scheme 8, 4 or 16 (`off` = BF16); also `kv_quant` in settings and per request (main.zig:972) | user | help, usage, engine-kv-cache; 21 tests | keep |
| `--kv-attn-mode` | `auto` → `dense` or `fused` packed-KV read at decode, `auto` fuses from 8K prompt tokens (main.zig:991) | dev | help, engine-kv-cache; 1 test | cut: the one test uses it as its A/B arm; `auto` is the shipped answer and a per-request field remains |
| `--qwen-gdn` | `bf16` → store the GatedDeltaNet state in `fp32`, Qwen only (main.zig:966) | user | help, engine-kernels, quality-kld; 0 tests (kld parse test) | keep: the long-context precision tradeoff; add a serve-side test |
| `--decode-attn-quant` | on already → the explicit "on" form; the default is on (main.zig:764) | dead | help, engine-kv-cache; 1 test | cut: states the default |
| `--no-decode-attn-quant` | requantizes DENSE attention projections to int8 g32 for decode and verify, lossy, only when a pack ships dense attention; this restores exact decode (main.zig:766) | user | help, engine-kv-cache; 0 tests | owner call |
| `--mtp-head-kv-quant` | off → Qwen's MTP head KV follows `--kv-quant`; no effect on MiMo (main.zig:762) | machine | help, usage, README, engine-mtp; 0 tests | keep: the long-context memory bills use it |

## Speculation (MTP, prompt lookup, drafter)

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--mtp` / `--no-mtp` | on for Qwen and MiMo, off for GLM → force the head on (required for a streamed pack) or off; also `mtp` in settings (main.zig:754) | user | help, usage, engine-mtp; 22 tests | keep |
| `--mtp-min-depth` | `1` → fewest tokens a round drafts, 1..8 (main.zig:771) | machine | help, engine-mtp; 5 tests | keep: depth range is a property of the chip; launch-only by design |
| `--mtp-max-depth` | adaptive, up to 8 on eligible M5 → most tokens a round drafts, 1..8 (main.zig:771) | machine | help, engine-mtp; 5 tests | keep |
| `--mtp-depth` | removed, exits naming the two above (main.zig:768) | dead | hidden; engine-mtp | cut: tombstone, drop after the next release |
| `--mtp-typical` | off, exact → typical acceptance, d > 0, lossy for sampled requests; also `mtp_acceptance` in settings (main.zig:780) | user | help, engine-mtp; 1 test | keep: measured 15-20% on sampled decode; docs warn it has looped |
| `--mtp-tokenv3` | off → TokenV3 cascade acceptance, 0..1, lossy (main.zig:783) | user | help; 2 tests | owner call |
| `--mtp-cascade` | alias of `--mtp-tokenv3` (main.zig:783) | dead | help (as alias); 0 tests | merge into `--mtp-tokenv3` |
| `--mtp-greedy-tail` | off → sampled requests draft only the first token by sampling; also in settings (main.zig:786) | user | help, engine-mtp, mimo2-perf; 1 test | keep: measured to pay only beside `--mtp-typical` |
| `--fast` | off → profile: MTP, typical acceptance, greedy tail, kv8; between flags and the file (main.zig:788) | user | help, engine-mtp, server-lifecycle; 3 tests | owner call |
| `--max-mtp-ctx` | `0` no ceiling → MTP off past n context tokens (main.zig:790) | machine | help, `/props`; 0 tests | owner call |
| `--mtp-history-window` | `0` full → head history for only the last n tokens of prompts past 16384 (main.zig:793) | dev | help; 0 tests | cut: its own A/B lost acceptance for no prefill gain, default stays 0 |
| `--no-mtp-lookup` | off → drop prompt-lookup drafts inside MTP rounds and GLM DFlash2 chains (cli.zig:708) | dev | help, engine-mtp; 2 tests | cut: kill switch of an adopted default; one arm per boot is why a bench wants it |
| `--pld` | on already → the explicit "on" form of standalone prompt lookup; only changes the reported source (main.zig:703) | dead | help; 9 tests | cut: states the default; no settings key to outrank |
| `--no-pld` | standalone PLD on, but it runs only when MTP and the drafter are both off, never on Qwen (main.zig:710) | test | help, engine-mtp; 27 tests | owner call |
| `--pld-draft-len` | `5` → max draft tokens per PLD step (main.zig:713) | dev | help; 1 test | cut: never measured, the one test only checks it is wired |
| `--pld-key-len` | `3` → n-gram key length for PLD (main.zig:716) | dev | help; 1 test | cut: same |
| `--drafter` | none → path of a GLM DFlash2 assistant stored elsewhere (main.zig:719) | operator | hidden; usage, glm5-arch; 7 tests | keep: add it to `--help` |
| `--no-drafter` | on when the assistant is found → never load it, saves its memory (main.zig:752) | machine | hidden; usage, glm5-arch; 9 tests | keep: add it to `--help` |
| `--draft-block-size` | the assistant's own block → clamp it down; it can only lower (main.zig:722) | dev | hidden; 0 tests | cut: undocumented, unmeasured, the machine cap is already automatic |

## Prefix cache

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--prefix-cache-entries` | `32` → hot-cache capacity, `0` disables all reuse; a bad value silently becomes 1 (main.zig:840) | user | help, usage, engine-prefix-cache; 41 tests, 2 scripts | keep |
| `--prefix-cache-mem` | off → RAM retention with this byte budget, `0` or `off` keeps it off (main.zig:843) | machine | help, usage, engine-prefix-cache; 19 tests, 2 scripts | keep |
| `--no-prefix-cache-ram` | RAM retention is already off → wins over `--prefix-cache-mem` (main.zig:837) | dead | help, engine-prefix-cache; 2 tests | merge into `--prefix-cache-mem off`: same result, a second spelling |
| `--prefix-cache-disk` | min(sized + 2 GiB, 20 GiB, free - 4 GiB) → SSD tier budget, `0` or `off` disables (main.zig:854) | machine | help, usage, engine-prefix-cache; 16 tests, 2 scripts | keep |
| `--ssm-checkpoint-stride` | `256` → hybrid (Qwen) state checkpoint every n tokens, `0` bypasses the hot cache; a bad value silently becomes 128 (main.zig:888) | machine | help; 3 tests | owner call |
| `--ssm-checkpoint-max` | `16` → checkpoints kept per entry, `0` unlimited (main.zig:895) | dev | help; 2 tests, 2 scripts | cut: the scripts pass the default and the cache byte budget already bounds it |
| `--tokenize-cache-entries` | `4` → per-model LRU of rendered and tokenized prompts, `0` disables (main.zig:882) | dev | help; 0 tests | cut: a micro-cache size no user has a reason to move |

## Sampling and reasoning defaults

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--max-tokens` | `100` offline; serve: default for requests that omit it (main.zig:649) | operator | help, usage; 9 tests | keep |
| `--temp` | `0` offline; serve: default temperature before `generation_config.json` (main.zig:653) | operator | help, usage; 2 tests | keep |
| `--top-p` | model config → serve default for requests that omit it (main.zig:657) | operator | help; 1 test | keep |
| `--top-k` | model config → serve default for requests that omit it (main.zig:660) | operator | help; 1 test | keep |
| `--reasoning-budget` | unlimited → max thinking tokens per request (main.zig:799) | user | help, server-http-apis; 2 tests | keep |
| `--preserve-thinking` | template default → keep every turn's thinking, `on` or `off`; also in settings (main.zig:876) | user | help, usage; 0 tests (settings test) | keep |
| `--think-penalty` | `0` off → lower overthinking-marker logits inside the reasoning span; also in settings (main.zig:868) | user | help, server-http-apis; 2 tests | keep |
| `--logit-bias-file` | none → JSON or CSV of scoped token penalties and rewards, "experimental" in `--help`; also in settings (main.zig:865) | user | help, server-http-apis; 1 test | owner call |

## Logging, diagnostics and info

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `--log-level` | `info` → error, warn, info or debug; a bad value is silently ignored (main.zig:802) | operator | help; 81 tests | keep |
| `--log-file` | `~/.sushi/logs/sushi-<port>.log` → path, or `off` (main.zig:808) | operator | help; 16 tests | keep |
| `--prefill-trace` | off → prefill phase timings at info; `--log-level debug` already prints them (main.zig:835) | dev | hidden; 0 tests | cut: redundant with debug logging |
| `--version` | prints app, MLX, mlx-c and NAX status and exits (main.zig:573) | operator | help; 2 tests, 1 script | keep: the app and `update` parse it |
| `--guest-manifest` | prints the host-check JSON and exits (main.zig:592) | operator | help; 2 tests | keep: `update` and the release gate run it |
| `--help` / `-h` | prints usage (main.zig:608) | operator | help; 5 tests | keep |

## Subcommands

`pull <model>` and `list` take no flags (`HF_TOKEN` is read from the environment). `serve` and `run <model>` take every flag above.

| flag | default → effect | who | documented | recommendation |
|---|---|---|---|---|
| `run`: `--think` | model default → reasoning effort, per model (main.zig:623) | user | help, server-http-apis; 2 tests | keep |
| `run`: `--tool` | `off` → REPL tools: web, fetch, read files in the folder (main.zig:631) | user | help, server-http-apis; 1 test | keep |
| `run`: `--edit` | `off` → add `write_file` and `edit_file` inside that folder (main.zig:637) | user | help, server-http-apis; 2 tests | keep |
| `run`: `--prompt` / `-p` | none → one prompt and exit (cli.zig:2354) | user | help; 4 tests | keep |
| `run`: `--stream` | off → stream tokens with `--prompt` (main.zig:644) | user | help; 1 test | keep |
| `launch`: `--model` | the server's default → model id (launch.zig:867) | operator | help, usage; 0 tests | keep |
| `launch`: `--url` | `http://127.0.0.1:<port>` → server base URL (launch.zig:871) | operator | help; test_launch_cmd, test_zcode_launch | keep |
| `launch`: `--port` | `12345` → server port for the default URL (launch.zig:875) | operator | help; 0 tests | keep |
| `launch`: `--print` | off → write configs and print the script instead of running (launch.zig:879) | user | help, usage; test_launch_cmd | keep |
| `launch`: `--no-start` | accepted and ignored (launch.zig:881) | dead | hidden; test_launch_cmd, test_zcode_launch | cut: a no-op "for existing scripts"; the two tests only need it accepted |
| `launch`: `--` | none → everything after goes to the agent (launch.zig:864) | user | help, usage; test_launch_cmd | keep |
| `update`: `--check` | off → report only (update.zig:709) | user | help; 1 test | keep |
| `update`: `--pre` | off → consider prereleases (update.zig:711) | user | help; 0 tests | keep |
| `update`: `--force` | off → update while a sushi of this install runs (update.zig:713) | user | help; 0 tests | keep |
| `update`: `--rollback` | off → swap `<install>.previous` back (update.zig:715) | user | help; 1 test | keep |
| `update`: `--relaunch --` | internal: the updater restarts the server with its argv (update.zig:717) | dev | hidden; 1 test | keep: plumbing, not a user flag |
| `kld`: `--model` | required → pack to score or capture (kld.zig:99) | dev | help, quality-kld | keep |
| `kld`: `--prompts` | required for capture → `standard4`, a fixture dir, `*.txt` dir or `.jsonl` (kld.zig:100) | dev | help, quality-kld | keep |
| `kld`: `--out` | required for capture → fixture output dir (kld.zig:101) | dev | help, quality-kld | keep |
| `kld`: `--fixture` | required for compare → teacher fixture dir (kld.zig:102) | dev | help, quality-kld | keep |
| `kld`: `--json` | none → compare writes the numbers here (kld.zig:103) | dev | help, quality-kld | keep |
| `kld`: `--label` | `sushi` → run label in the output (kld.zig:104) | dev | help, quality-kld | keep |
| `kld`: `--tokens` | `64` → greedy tokens captured per prompt (kld.zig:105) | dev | help, quality-kld | keep |
| `kld`: `--top-k` | `10` → top_k recorded in `baseline.json` (kld.zig:106) | dev | help, quality-kld | keep |
| `kld`: `--limit` | `0` all → first n prompts only (kld.zig:107) | dev | help, quality-kld | keep |
| `kld`: `--no-template` | off → feed raw prompt text (kld.zig:143) | dev | help, quality-kld | keep |
| `kld`: `--ctx-size` | model max → context override (kld.zig:108) | dev | help | keep |
| `kld`: `--kv-quant` | dense BF16 → KV scheme; the teacher adds no quantization of its own (kld.zig:109) | dev | help, quality-kld | keep |
| `kld`: `--qwen-gdn` | `bf16` → fp32 GDN state for a teacher that prices that rounding (kld.zig:110) | dev | help, quality-kld | keep |
| `kld`: `--ssd-budget-gb` | none → expert streaming budget (kld.zig:111) | dev | help, quality-kld | keep |
| `kld`: `--expert-cache-gb` | none → streamed cache size, outranks the budget (kld.zig:112) | dev | help | owner call: follows the serve flag |
| `kld`: `--expert-pick-tolerance` | `0` → compare only, lossy swap of a missed expert (kld.zig:113) | dev | help, quality-kld; 1 test | keep |
| `kld`: `--wired-margin-gib` | `1` → headroom under the wired limit (kld.zig:114) | dev | help | keep |
| `kld`: `--mtp` / `--no-mtp` | head not resident → keep the head loaded (kld.zig:145) | dev | help (`--mtp` only); quality-kld | keep: list `--no-mtp` in its help |
| `kld`: `--layer-major` | off → native GLM BF16 teacher in batches, layer by layer, resumable (kld.zig:151) | dev | help, quality-kld, glm5-arch | keep |
| `kld`: `--batch-windows` | from the budget → windows per layer-major batch (kld.zig:115) | dev | help, quality-kld | keep |
| `kld`: `--imatrix-windows` | all → layer-major imatrix covers the first n windows (kld.zig:116) | dev | help, engine-expert-streaming | keep |
| `kld`: `--pause-file` | none → layer-major idles while the file exists (kld.zig:117) | dev | help, quality-kld | keep |

## Cut list

Delete the flag, its parse arm, its help line and the code only its off arm reaches. Where a test needs the arm, that test gets a temporary env knob or a test seam first ([envvar](envvar.md)).

- **Serving**
  - `--max-concurrent`: only sizes a submit queue (`n + 32`) and a prefix-cache floor; decode batching is decided by the model. 21 tests and 2 scripts pass it, so drop the argument there in the same landing; `/props max_concurrent` and the boot line go with it.
  - `--no-tool-autocorrect`: kill switch of the schema-coercion default, no test, no measurement.
- **Model and memory**
  - `--warmup-eager`, `--no-warmup-eager`: the first is the default; the second reaches the boot model only (a cold load always warms) and exists to shorten three test boots.
  - `--no-safety`: accepted and ignored; nothing in the tree passes it.
- **KV and attention**
  - `--kv-attn-mode`: one test uses it to force the dense arm against the fused arm; `auto` is the shipped choice and the per-request `kv_attn_mode` field stays.
  - `--decode-attn-quant`: states the default; nothing reads the "explicit" bit it sets on a served arch.
- **Speculation**
  - `--mtp-depth`: tombstone that exits naming `--mtp-min-depth` and `--mtp-max-depth`.
  - `--mtp-history-window`: the A/B behind its default 0 lost acceptance for no prefill gain, so no value but 0 is useful.
  - `--no-mtp-lookup`: kill switch of an adopted default; a bench that wants one arm per boot needs an env knob, not a flag.
  - `--pld`: the default; it only changes the reported source label.
  - `--pld-draft-len`, `--pld-key-len`: never measured, undocumented; the single test checks they reach the request defaults and would go with them.
  - `--draft-block-size`: hidden, undocumented and it can only clamp the assistant's block below the automatic machine cap.
- **Prefix cache**
  - `--ssm-checkpoint-max`: the byte budget already bounds the cache; the two scripts pass the default `16`.
  - `--tokenize-cache-entries`: a four-entry render cache with no tradeoff to pick.
- **Logging**
  - `--prefill-trace`: `--log-level debug` prints the same phase line.
- **Subcommands**
  - `launch --no-start`: a no-op.
- **Merge (cut the second name)**
  - `--hf-overrides` into `--config-overrides`; `--mtp-cascade` into `--mtp-tokenv3`; `--no-prefix-cache-ram` into `--prefix-cache-mem off`.

## Owner calls

What would decide each.

- `--embedding-max-length`: whether any deployment lowers the embedding ceiling below the model's window. No test, no doc, no script passes it; the 400-on-overflow behavior at the window is the default. Cut if nobody does.
- `--expert-cache-gb` (and `kld --expert-cache-gb`): whether any run needs a cache size apart from the total budget. One test (a BF16 source checkpoint at 60 GB) uses it; if `--ssd-budget-gb` can state that run, merge into `--ssd-budget-gb`.
- `--no-decode-attn-quant`: boot each served pack and read `[decode-attn-quant] engaged` or `/props settings.decode_attn_quant`. The code says a fully quantized pack decodes the same with or without it and the default-on characterization was on an arch this tree no longer serves. If no served pack engages, cut it; if one does, keep this as the exactness switch and measure its KLD against dense decode.
- `--mtp-tokenv3`: a same-boot 16x512 sampled A/B, two seeds, exact against typical against TokenV3 (tok/s and emitted-text NLL, as `engine-mtp` records for typical). None is recorded; it was ported with the upstream verifiers. Cut if it does not beat typical.
- `--fast`: the cause of the sampled looping seen under typical acceptance. If typical is the cause, drop `--fast` or its typical part; if not, keep the preset as the one-flag speed profile. Either way the README and cards recommend neither today.
- `--max-mtp-ctx`: whether the adaptive speculate-or-serial vote (on by default) already switches MTP off at the contexts a ceiling would, on the M1/M2/M5 long-context ladders. Run `--max-mtp-ctx n` against the default with the vote on; cut if the vote covers every chip.
- `--no-pld`: whether standalone PLD ever engages and wins on a served configuration (GLM with `--no-drafter`, a streamed pack with MTP off). Never on Qwen. If it never wins, remove standalone PLD and its request field with it; if it does, keep `--no-pld` as the off switch only.
- `--ssm-checkpoint-stride`: warm-reuse hit rate and checkpoint bytes at strides 128, 256 and 1024 on a multi-turn agent trace. None is recorded, and on MoE targets the stride is raised to the prefill chunk anyway. Cut if the default wins everywhere.
- `--logit-bias-file`: whether any user or agent ships a bias file. It is marked experimental in `--help` and requests already carry `logit_bias`; cut if there is no user.

## Help and parse mismatches

- **Parsed, absent from `--help`:** `--drafter`, `--no-drafter`, `--draft-block-size` (the first two are in `docs/usage.md`), `--max-concurrent`, `--warmup-eager`, `--no-warmup-eager`, `--prefill-trace`, `--no-safety`, `--mtp-depth`; `launch --no-start`; `kld --no-mtp` (only `--mtp` is listed); `update --relaunch` is internal on purpose. `kld --model`, `--prompts`, `--out` and `--fixture` appear in its usage lines but not its options block.
- **In `--help`, not parsed:** none. The text-scan hits `--prompt` and `--no-mtp-lookup` are parsed through helpers (`isPromptFlag`, `isNoMtpLookupFlag`).
- **Stale text:** `--mtp` and `--no-mtp` say "both served models" and there are three, GLM's head staying off. The `launch` line in `--help` lists agents without `grok`, which `AgentKind.names` and the error text include; `docs/usage.md` omits `zcode`.
- **Silent value fallbacks**, where the serve loop otherwise exits naming the flag: `--prefix-cache-entries` bad value becomes 1, `--tokenize-cache-entries` 4, `--ssm-checkpoint-stride` 128 (help and the server default say 256), `--ssm-checkpoint-max` 16, `--max-concurrent` 1, `--max-resident-models` 3, `--idle-evict-secs` off; `--log-level` and `--prefill-chunk` ignore an unknown or zero value.
- **Silent extra arguments:** `sushi pull <model> --anything` and `sushi list --anything` ignore what follows, where the serve loop exits with `unrecognized argument`.
- **Accepted, no effect in the mode:** `--tool` under `serve` (it only gates the REPL and conflicts with `-p`); `--stream` without `--prompt`.
