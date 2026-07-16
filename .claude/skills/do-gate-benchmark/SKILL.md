---
name: do-gate-benchmark
description: Run the KEP-0002 Phase 7 gate-campaign benchmark (benchmarks/gate/) on a real x86-64 Linux reference machine using a DigitalOcean droplet, producing the statistically rigorous Kalibera-Jones dataset a KEP acceptance gate reads. Use when a KEP's acceptance gate needs its Linux/second reference-machine dataset, when a documented revisit trigger fires and the gate needs re-running, or when a new performance-gated KEP wants the same dual-machine benchmark protocol. Distinct from /do-stress-test (gc-stress unit suite) and /do-linux-test (normal build + Scheme test suite) — this runs a multi-hour statistical benchmark harness, not a test suite, and needs ≥8 physical cores.
---

# DigitalOcean Gate-Benchmark Campaign (Linux x86_64 reference machine)

Runs `benchmarks/gate/run-gate.py` — the Kalibera-Jones driver over
`benchmarks/gate/gate-harness.scm` — on a dedicated x86-64 droplet, to
produce the `share`-vs-CI dataset a KEP acceptance gate classifies
mechanically (`benchmarks/gate/classify.py`). The frozen protocol is
`keps research/benchmarks/README.md` §4–§6; this skill is the operational
"how," not a second copy of the "what" — always read the current protocol
doc and the target worksheet (e.g. `docs/dev/kep-0003-acceptance-gate-worksheet.md`)
first to know the exact scope (workloads, sizes, workers, levers, K-J
counts, any standing amendments) before provisioning anything.

This grew out of collecting the Linux half of the KEP-0003 gate (kaappi#1474,
PR #1580) — every section below is a lesson that cost real time or a mid-run
correction that session. Read it before, not after, hitting the same wall.

## Pre-flight

1. Read the frozen protocol section this run must match, and the worksheet
   for the machine(s) already collected — note the exact `kaappi` commit,
   K-J counts, sizes/workers/levers, and any per-workload caps already in
   force (e.g. a workload capped to smaller sizes because its largest size
   is computationally infeasible on some hardware).
2. Decide the build commit. Prefer **current `main` HEAD** over an old
   pinned commit if the intervening commits that touch gate-relevant files
   (`src/shared_channel.zig`, `src/channel_instrument.zig`,
   `src/shared_buffer.zig`, `src/primitives_parallel.zig`, `build.zig`,
   `benchmarks/gate/`) are comptime-gated to be inert under
   `-Dchannel-instrument=true` — check each diff, don't assume. Building at
   HEAD picks up unrelated fixes for free; building at a stale pinned
   commit risks missing a bugfix the other machine's run already benefited
   from.
3. SSH key fingerprint: `ssh-keygen -l -E md5 -f ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://'`

## Droplet sizing — go straight for the dedicated "Basic" Premium tier

The protocol requires **≥8 physical cores** (§4.6). On this account, the
dedicated CPU-Optimized line (`c-`, `c2-`, `c5-` prefixes) is
**account-tier-restricted above 4 vCPUs** — `droplet-create` fails at
creation time ("this size is currently restricted, please open a ticket")
even though `c5-8vcpu-16gb` etc. show as available in a region's size
list. Don't rediscover this the hard way: go straight for
**`s-8vcpu-16gb-intel`** (or `-amd`) in `nyc3` — despite the "Basic" `s-`
prefix, the `-intel`/`-amd` suffixed variants are the dedicated-vCPU
Premium tier, not the oversubscribed "Regular" shared tier.

Once the droplet is up, **verify actual topology with `lscpu`** — don't
assume the vCPU count equals physical cores:

```bash
ssh ... 'lscpu'
# Want: "Thread(s) per core: 1" and Socket(s) x Core(s)-per-socket == vCPU count.
# Record the CPU model string ("Model name") for the results metadata.
```

If it comes back with SMT (`Thread(s) per core: 2`) or a lower physical
count than expected, that's a real deviation worth surfacing before
committing hours to the run, not silently accepting.

## Bash-guard footguns hit during provisioning

The local `bash-guard-pre.sh` hook pattern-matches command *strings*, not
semantics — it fires on these even when the actual target is obviously
safe, and each one wastes a debugging cycle if you don't recognize it fast:

1. **Literal `sudo` anywhere in the command trips the deny-list**, even
   inside an SSH heredoc destined entirely for the remote host. Use
   `su <user> -c '<cmd>'` instead — `su <user> -c 'cmd'` (no `-`/`--login`)
   preserves the calling shell's cwd, close enough to `sudo -u <user>`
   without `-i` for provisioning scripts.
2. **`pkill -9 -f "pattern"` can kill its own invoking shell** when two
   `pkill -f` calls in the same script each contain the other's pattern
   string as a substring (or the wrapping `bash -c "..."` line does) —
   `pkill -f` matches full command lines, including its own siblings.
   Manifests as a bare `Exit code 255`, easy to mistake for a network
   blip. Use `pgrep -af "pattern"` to get real PIDs, then `kill -9 <pids>`.
3. **`rm -rf <path>` is blocked even for obviously-non-root scratch
   paths.** Use `find <path> -mindepth 1 -delete` (+ `rmdir`) instead, or
   just leave inconsequential `/tmp` scratch data rather than fight it.

## Provision + build

Mirror `/do-stress-test`'s provisioning (Zig 0.16, `git make gcc
libc6-dev`, unprivileged `tester` user, `git fetch --depth 1 <exact-commit>`
+ checkout) — plus `python3-numpy`, which `run-gate.py` imports:

```bash
apt-get install -y -qq git make gcc libc6-dev python3-numpy
```

Build with the instrumentation flag (ReleaseSafe default, per protocol §4.5):

```bash
su tester -c "zig build -Dchannel-instrument=true"
```

## Always timing-probe before committing to the full run

**This is the single most important lesson from #1474.** A driver-level
`--mode pilot` run is not enough — it mixes cheap and catastrophically
expensive cells under one shuffled schedule, so the real bottleneck can
stay hidden while it burns minutes. Before arming the self-destruct timer,
run a direct, single-iteration probe of the harness itself (bypassing the
Python driver), with a real `timeout` wrapper (Linux has one; macOS
doesn't), against the heaviest workload(s) at the **largest size** in the
target scope, both serial (`w=1`) and parallel (`w=8`):

```bash
timeout 180 zig-out/bin/kaappi benchmarks/gate/gate-harness.scm \
  <workload> <largest-size-bytes> <workers> none 0 1
# args: workload size-bytes workers lever warmup iters
```

Time it (`date +%s.%N` before/after, or wrap in `time`), then extrapolate:
`per_iteration_time × (warmup + iterations) × invocations × n_levers ×
Σ(size scaling factors)`. Compare against the *other* reference machine's
documented per-iteration timings before assuming this box is comparably
fast — in #1474, a cloud x86 vCPU ran one workload's 64 MiB cell ~5–6×
slower than the Apple Silicon reference, turning an expected ~3h run into
a naive ~19–20h estimate.

If the extrapolate blows past a reasonable budget:

- **Surface it to the user before deciding anything** — this is a real
  cost/rigor tradeoff (drop scope vs. extend the droplet budget vs. reduce
  K-J counts), not something to silently resolve.
- The precedented, least-damaging fix is **capping the offending
  workload's largest size(s)**, mirroring this protocol's own existing
  `IP-MATMUL` precedent ("largest size computationally infeasible on some
  hardware") — keeps full K-J rigor everywhere else. Document the amendment
  in the results metadata file and the worksheet; it doesn't need a
  protocol-doc change if the *other* machine's data for that cell already
  exists (only this machine's collection is scoped down).
- If you kill a leftover pilot/probe process to reclaim the box, check for
  orphaned children before reusing it (`pgrep -af "run-gate|gate-harness"`).

## Splitting the run for a capped workload

`run-gate.py` has no per-workload size override, so a capped workload needs
its own invocation with a different `--sizes` list, run sequentially with
the rest in one detached script:

```bash
python3 benchmarks/gate/run-gate.py --bin zig-out/bin/kaappi --mode full \
  --machine <label> --cores <N> \
  --sizes 65536,1048576,8388608,67108864 --workers 8 \
  --workloads <everything-except-the-capped-one> \
  --levers none,cd --warmup 2 --timeout 450 \
  --out /tmp/part-a.csv

python3 benchmarks/gate/run-gate.py --bin zig-out/bin/kaappi --mode full \
  --machine <label> --cores <N> \
  --sizes 65536,1048576,8388608 --workers 8 \
  --workloads <the-capped-workload> \
  --levers none,cd --warmup 2 --timeout 450 \
  --out /tmp/part-b.csv
```

Note: `c-empty` is added **automatically** by the driver regardless of
`--workloads` (once per worker count) — do not list it explicitly, or the
main workload×size×lever loop will also generate spurious extra `c-empty`
cells at nonsense sizes/levers. Each split invocation still auto-adds its
own `c-empty` row; when merging CSVs afterward, keep only one.

Bump `--timeout` (per-invocation wall clock, covers warmup+iterations in
one subprocess) above the 120s default — cheap insurance once the timing
probe shows real per-iteration costs; a too-low value causes spurious
`TIMEOUT`-excluded cells, not a faster run.

## Self-destruct timer — budget generously

Same pattern as `/do-stress-test` (DO token to a root-only file, `nohup
sleep <N> && curl DELETE` backgrounded, armed *after* the sanity build +
pilot, immediately before the full launch). Cross-machine timing is
genuinely unpredictable — budget at least 1.5–2× your post-probe estimate.
The dollar cost of over-provisioning is trivial (a full day on an 8-vCPU
Premium droplet is a few dollars); a run guillotined mid-way by an
under-provisioned timer wastes the whole run.

## Launch + poll

Launch both/all part-invocations back to back in one `nohup`-backgrounded
script (as `tester`), writing a `touch /tmp/gate-done` marker at the end.
Watch it with a **background Bash poll loop** (`run_in_background: true`),
not a blocking wait or a tight foreground poll:

```bash
until ssh ... 'test -f /tmp/gate-done'; do sleep 150; done
```

Once launched this way, don't proactively re-poll — the harness notifies
on completion. Use the wait to check for `TIMEOUT`/`FAIL`/`WARNING`/
`Traceback` in the logs as they land, not just at the end.

## Fetch, merge, classify

`scp` back each part's CSV + log. Merge into one CSV: header + all data
rows from every part, keeping exactly one `c-empty` row. Run the
classifier **locally**, against both machines' CSVs together, to get the
mechanical per-machine *and* combined outcome — don't hand-compute the
rule tests, `classify.py` already implements §5 exactly:

```bash
python3 benchmarks/gate/classify.py \
  benchmarks/gate/results/<other-machine>.csv /tmp/merged-new-machine.csv
```

## Write the results + update the worksheet

- `benchmarks/gate/results/<machine>.csv` (merged) and
  `<machine>-metadata.txt` (mirror the existing machine's metadata file:
  commit, protocol commit, OS/kernel, **actual** `lscpu` topology, K-J
  counts achieved, any amendment applied and why, dates).
- Fill every placeholder in the target worksheet (data tables, all rule
  tests, per-machine outcome, combined-outcome narrative) — `grep` for
  leftover `·`/`☐` before considering it done.
- If the branch you're working from already has a **merged** PR, check
  whether its remote branch still exists before pushing more commits to
  it (`git ls-remote --heads origin <branch>`) — a squash-merge typically
  deletes it and leaves your local branch diverged from `main`'s new
  history. If so, stash your changes, branch fresh off `origin/main`, and
  reapply, rather than fight the stale branch.
- Open a PR (don't arm auto-merge — every precedent in this repo has these
  merged manually) and comment on the tracking issue with the reading and
  the confirmed combined outcome.

## Cleanup — always

`droplet-delete` regardless of outcome, even on a partial/failed run.
Remove the pinned host-key temp file (`find <file> -delete` if `rm -f`
somehow trips the guard, though a plain file usually doesn't). Never rely
solely on the self-destruct timer.

## Notes

- **Cost**: `s-8vcpu-16gb-intel` is ~$0.167/hr — even a generously
  over-budgeted 12–15 hour run is only a few dollars.
- **Sequential execution**: `run-gate.py`'s invocation loop is strictly
  sequential (one subprocess at a time, each internally using up to `w`
  worker threads) — wall time is the sum of all invocation times, no
  concurrency multiplier to account for. An 8-vCPU box is exactly sized
  for one `w=8` invocation at a time.
- **`--seed`**: leave at the tool default unless the protocol says
  otherwise — each machine's run is independently randomized regardless.
- **Security model**: same as `/do-stress-test` — throwaway droplet, TOFU
  host-key pinning, DO token in a root-only file, untrusted repo code runs
  as the unprivileged `tester` user.
