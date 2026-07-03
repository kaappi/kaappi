---
name: do-linux-test
description: Run Kaappi build and full test suite on a real x86-64 Linux machine using a DigitalOcean droplet. Use when the user asks to test on x86-64 Linux, run Linux tests on real hardware, verify x86-64 compatibility with full Scheme test suites, or test on DigitalOcean. Complements /linux-test (podman-based) by providing real x86-64 hardware instead of emulation.
---

# DigitalOcean x86-64 Linux Test

Build and run the full Kaappi test suite on a real x86-64 Linux machine via a
temporary DigitalOcean droplet. The droplet is **always** destroyed when done.

## Pre-flight

### 1. Record branch and check for unpushed work

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Branch: $BRANCH"
git status --porcelain
```

If there are uncommitted changes, warn the user that only pushed commits will
be tested. Check if the branch exists on the remote:

```bash
git ls-remote --heads origin "$BRANCH"
```

If the branch has no remote tracking, ask the user to push first.

### 2. Get SSH key fingerprint

```bash
ssh-keygen -l -E md5 -f ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://'
```

Save this fingerprint for the droplet creation step.

## Create the droplet

Use `mcp__digitalocean-droplets__droplet-create`:
- **Name**: `kaappi-test-<branch>` (replace `/` with `-` in branch name, truncate to 60 chars)
- **Size**: `s-2vcpu-4gb`
- **Region**: `nyc3`
- **ImageSlug**: `ubuntu-24-04-x64`
- **SSHKeys**: `["<fingerprint>"]`
- **Tags**: `["kaappi-test"]`
- **Monitoring**: `true`

Record the **droplet ID** immediately — it is needed for cleanup.

## Wait for SSH access

1. Poll with `mcp__digitalocean-droplets__droplet-get` every 10 seconds until
   `status` is `active` and a public IPv4 address is assigned (max 2 minutes).

2. Wait for sshd to accept connections:
   ```bash
   IP=<droplet-ip>
   for i in $(seq 1 24); do
     ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -o UserKnownHostsFile=/dev/null root@$IP echo ready 2>/dev/null && break
     sleep 5
   done
   ```

## Provision and test

Run provisioning and tests as **separate SSH commands** so that a single
long-running step doesn't hit the Bash tool timeout (14 min). Replace
`<BRANCH>` with the actual branch name from pre-flight.

### 4a. Provision

```bash
ssh -i ~/.ssh/id_rsa \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'bash -s' << 'REMOTE'
set -euo pipefail

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

### 4b. Build

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'cd /workspace && zig build 2>&1 && echo "BUILD: OK" || echo "BUILD: FAIL"'
```

### 4c. Unit tests

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@$IP 'cd /workspace && zig build test 2>&1'
```

### 4d. Scheme tests

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=40 \
  root@$IP 'cd /workspace && bash tests/scheme/run-all.sh 2>&1'
```

The Scheme suite includes compile tests (`zig build -Dbundle`) that rebuild
the full binary — expect ~5 minutes on 2 vCPUs. Use `ServerAliveInterval`
to keep the connection open during long compiles.

## Report results

Parse the test output and summarize:
- **Build**: OK / FAIL
- **Unit tests**: pass/fail counts
- **Scheme tests**: per-suite results from `run-all.sh` output (look for
  PASS/FAIL lines and the final summary)
- Any errors, failures, or timeouts

## Cleanup

**CRITICAL: This step MUST run regardless of test outcome — success, failure,
timeout, or error.** Never skip it.

Use `mcp__digitalocean-droplets__droplet-delete` with the recorded droplet ID.

If deletion fails, **warn the user immediately** with the droplet ID and IP
so they can destroy it manually via the DigitalOcean console.

## Notes

- **Cost**: `s-2vcpu-4gb` is ~$0.03/hr. A full test run takes 10–15 minutes
  (the compile tests rebuild the full binary, which is slow on 2 vCPUs).
- **SSH key**: uses `~/.ssh/id_rsa`. The matching public key must be on the
  DigitalOcean account (upload via web console → Settings → Security).
- **Complements /linux-test**: that skill uses podman for aarch64 native +
  x86-64/riscv64 cross-compile. This skill provides real x86-64 hardware
  for the full Scheme-level test suite.
- **Stale droplets**: if a session dies mid-test, find and destroy orphans:
  list droplets via `mcp__digitalocean-droplets__droplet-list` and look for
  names starting with `kaappi-test-`.
