---
name: do-stress-test
description: Run the Kaappi unit suite under -Dgc-stress=true on a real x86-64 Linux machine using a DigitalOcean droplet with a 3-hour lifetime. Use when the user asks to stress-test on Linux, run the gc-stress suite on real hardware, verify GC rooting under stress on x86-64, or stress test on DigitalOcean. Complements /do-linux-test (normal suite, ~1-hour droplet) — this variant runs the collection-per-allocation build, which takes hours, not minutes.
---

# DigitalOcean GC-Stress Test (3-hour droplet)

Build Kaappi with `-Dgc-stress=true` (a collection is attempted on every
allocation) and run the full unit suite on a temporary x86-64 DigitalOcean
droplet. The droplet self-destructs after **3 hours** and is **always**
destroyed when done.

Key differences from `/do-linux-test`:
- The stress suite is CPU-bound for **1.5–3 hours** (every test VM bootstrap
  performs tens of thousands of collections; ~40 min on an M-series Mac).
- It runs detached (`nohup`) on the droplet and is **polled**, never awaited
  in a single SSH command — no SSH command may outlive the Bash tool timeout.
- The testing allocator's metadata churn inflates RSS by gigabytes, so the
  droplet gets more memory plus a swap file.

## Pre-flight

### 1. Record branch and check for unpushed work

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Branch: $BRANCH"
git status --porcelain
git ls-remote --heads origin "$BRANCH"
```

Only pushed commits are tested. If the branch has no remote tracking, ask the
user to push first.

### 2. Get SSH key fingerprint

```bash
ssh-keygen -l -E md5 -f ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://'
```

## Create the droplet

Use `mcp__digitalocean-droplets__droplet-create`:
- **Name**: `kaappi-stress-<branch>` (replace `/` with `-`, truncate to 60 chars)
- **Size**: `s-4vcpu-8gb-amd` (premium AMD — the suite is single-core-bound,
  so per-core speed matters; fall back to `s-4vcpu-8gb` if unavailable)
- **Region**: `nyc3`
- **ImageSlug**: `ubuntu-24-04-x64`
- **SSHKeys**: `["<fingerprint>"]`
- **Tags**: `["kaappi-test", "kaappi-stress"]`
- **Monitoring**: `true`

Record the **droplet ID** immediately — it is needed for cleanup.

## Wait for SSH access

1. Poll with `mcp__digitalocean-droplets__droplet-get` every 10 seconds until
   `status` is `active` and a public IPv4 is assigned (max 2 minutes).

2. Wait for sshd:
   ```bash
   IP=<droplet-ip>
   for i in $(seq 1 24); do
     ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -o UserKnownHostsFile=/dev/null root@$IP echo ready 2>/dev/null && break
     sleep 5
   done
   ```

## Arm the 3-hour self-destruct timer

Immediately after SSH is up. This guarantees destruction even if the Claude
session dies mid-run. **3 hours 5 minutes** (11100 s) gives the run its full
3-hour budget with a small margin:

```bash
DO_TOKEN=$(source ~/.zshrc 2>/dev/null && echo "$DIGITALOCEAN_API_TOKEN")
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP "nohup bash -c 'sleep 11100 && curl -sf -X DELETE \
    -H \"Authorization: Bearer $DO_TOKEN\" \
    https://api.digitalocean.com/v2/droplets/<DROPLET_ID>' \
    > /dev/null 2>&1 &"
```

The token lives only in the process's memory on a throwaway droplet.

## Provision

One SSH command (well under the Bash tool timeout):

```bash
ssh -i ~/.ssh/id_rsa \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'bash -s' << 'REMOTE'
set -euo pipefail

echo "==== Swap (OOM insurance for testing-allocator churn) ===="
fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile

echo "==== Installing Zig 0.16 ===="
cd /tmp
curl -sL https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | tar xJ -C /opt
ln -sf /opt/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig
zig version

echo "==== Waiting for apt lock ===="
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
      fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  sleep 5
done

echo "==== Installing dependencies ===="
apt-get update -qq
apt-get install -y -qq git make gcc libc6-dev > /dev/null 2>&1

echo "==== Cloning repo (branch: <BRANCH>) ===="
git clone --depth 1 --branch <BRANCH> https://github.com/kaappi/kaappi.git /workspace
echo "PROVISION: OK"
REMOTE
```

## Sanity check: plain build and test first

Catch a broken commit in minutes before burning hours on the stress run:

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'cd /workspace && zig build 2>&1 | tail -5 && zig build test 2>&1 | tail -5; echo "PLAIN: $?"'
```

If the plain suite fails, report and go straight to Cleanup — a stress run on
a broken commit is wasted money.

## Launch the stress suite (detached)

**Never run the stress suite as a foreground SSH command** — it takes
1.5–3 hours. Launch it detached, writing to a results file:

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'cd /workspace && nohup bash -c \
    "zig build test -Dgc-stress=true > /tmp/stress-results.txt 2>&1; \
     echo EXIT:\$? >> /tmp/stress-results.txt; touch /tmp/stress-done" \
    > /dev/null 2>&1 & echo LAUNCHED'
```

Record the local start time.

## Poll for completion

Poll every few minutes with short SSH commands. Each poll checks for the done
marker and shows the process is still alive:

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  -o UserKnownHostsFile=/dev/null root@$IP \
  'test -f /tmp/stress-done && echo DONE || \
   { pgrep -f "gc-stress|unit-tests" > /dev/null && echo RUNNING || echo DEAD; }'
```

- Locally, prefer a background Bash poll loop (e.g. `until ssh ... test -f
  /tmp/stress-done; do sleep 120; done` with `run_in_background`) so the
  session is notified on completion instead of burning foreground calls.
- **RUNNING**: keep waiting. Report progress to the user roughly every
  30 minutes.
- **DEAD** without the done marker: the process was killed (OOM is the usual
  suspect — check `dmesg | grep -i oom` and `free -h`). Fetch partial results
  and report.
- If ~2 h 45 min elapse without completion, fetch whatever
  `/tmp/stress-results.txt` holds — the self-destruct fires at 3 h 05 min.

## Fetch results

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'grep -E "error: |pass|skip|fail|crash|EXIT" /tmp/stress-results.txt | tail -40'
```

If the connection was interrupted at any point, the results file is still on
the droplet — reconnect and fetch.

## Report results

- **Plain build/test**: OK / FAIL
- **Stress suite**: the `N pass, N skip, N fail, N crash (N total)` line and
  `EXIT:` code. Expect a handful of **skips** — throughput- or memory-bound
  tests deliberately skip on stress builds (see `docs/dev/testing.md`).
- Every `error: '<test name>' ...` line, verbatim — under gc-stress a crash
  signature (poison reads, "@memcpy arguments alias", "incorrect alignment")
  usually means an unrooted value; see `.claude/rules/gc-safety.md`.
- Wall time of the stress run.

## Cleanup

**CRITICAL: This step MUST run regardless of outcome — success, failure,
timeout, or error.** Never skip it, and never rely solely on the
self-destruct timer.

Use `mcp__digitalocean-droplets__droplet-delete` with the recorded droplet ID.

If deletion fails, **warn the user immediately** with the droplet ID and IP so
they can destroy it manually via the DigitalOcean console.

## Notes

- **Cost**: `s-4vcpu-8gb-amd` is ~$0.084/hr → a full 3-hour window costs
  ~$0.25.
- **Why hours**: with a collection attempted on every allocation, each test's
  VM bootstrap alone performs tens of thousands of full collections. ~40 min
  on an M-series Mac; budget 1.5–3 h on droplet vCPUs.
- **Memory**: `std.testing.allocator` (DebugAllocator) metadata churn under
  stress inflates process RSS far beyond real heap use (#1401 postmortem:
  multi-GB peaks). Hence 8 GB RAM + 8 GB swap; if the run still dies to the
  OOM killer, check whether a new test needs the stress-build scaling pattern
  from `docs/dev/testing.md`.
- **SSH key**: uses `~/.ssh/id_rsa`; the public key must be on the DO account.
- **Stale droplets**: if a session dies, list droplets via
  `mcp__digitalocean-droplets__droplet-list` and destroy anything named
  `kaappi-stress-*` (they also carry the `kaappi-test` tag).
- **macOS has no `timeout`**: never `timeout N ssh ...`; use the detached
  launch + poll pattern above.
- **CI equivalent**: the `gc-stress` variant of `.github/workflows/fuzz.yml`
  runs this same suite (300-minute job timeout) on schedule/dispatch — this
  skill is for on-demand runs against a branch before merging.
