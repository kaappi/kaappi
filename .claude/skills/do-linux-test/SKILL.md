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

2. Scan the host key and pin it (TOFU — trust on first contact, then verify
   all subsequent connections against this pinned key):
   ```bash
   IP=<droplet-ip>
   for i in $(seq 1 24); do
     ssh-keyscan -H $IP > /tmp/kaappi-test-hostkeys 2>/dev/null && \
       [ -s /tmp/kaappi-test-hostkeys ] && break
     sleep 5
   done
   ```

3. Verify SSH is ready using the pinned host key:
   ```bash
   ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
     -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
     -o ConnectTimeout=5 root@$IP echo ready
   ```

All subsequent SSH commands **must** use
`-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys`.
Never fall back to `StrictHostKeyChecking=no`.

## Arm self-destruct timer

Immediately after SSH is up, install a background process on the droplet
that deletes itself via the DO API after 55 minutes. This guarantees
destruction even if the Claude session dies mid-run.

Source the API token locally and write it to a root-only file on the droplet
(keeps the token out of `ps` output):

```bash
DO_TOKEN=$(source ~/.zshrc 2>/dev/null && echo "$DIGITALOCEAN_API_TOKEN")
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  root@$IP 'umask 077; cat > /root/.do-token; chmod 600 /root/.do-token' <<< "$DO_TOKEN"
```

Then start the timer, reading the token from the file:

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  root@$IP "nohup bash -c 'sleep 3300 && curl -sf -X DELETE \
    -H \"Authorization: Bearer \$(cat /root/.do-token)\" \
    https://api.digitalocean.com/v2/droplets/<DROPLET_ID>' \
    > /dev/null 2>&1 &"
```

The token file is owned by root (mode 0600) and inaccessible to the
unprivileged `tester` user that runs the build and tests.

## Provision and test

Run provisioning and tests as **separate SSH commands** so that a single
long-running step doesn't hit the Bash tool timeout (14 min). Replace
`<BRANCH>` with the actual branch name from pre-flight.

### 4a. Provision (as root)

Install system dependencies and create an unprivileged user for the build:

```bash
ssh -i ~/.ssh/id_rsa \
  -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
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

echo "==== Creating unprivileged tester user ===="
useradd -m -s /bin/bash tester
mkdir -p /workspace
chown tester:tester /workspace

echo "==== Cloning repo (branch: <BRANCH>) ===="
sudo -u tester git clone --depth 1 --branch <BRANCH> \
  https://github.com/kaappi/kaappi.git /workspace
echo "PROVISION: OK"
REMOTE
```

### 4b. Build

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  root@$IP 'cd /workspace && sudo -u tester zig build 2>&1 && echo "BUILD: OK" || echo "BUILD: FAIL"'
```

### 4c. Unit tests

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  root@$IP 'cd /workspace && sudo -u tester zig build test 2>&1'
```

### 4d. Scheme tests

Redirect output to a file on the remote so results survive even if the SSH
stream is interrupted. The Scheme suite includes compile tests
(`zig build -Dbundle`) that rebuild the full binary — expect ~5 minutes on
2 vCPUs. Use `ServerAliveInterval` to keep the connection open.

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=40 \
  root@$IP 'cd /workspace && sudo -u tester bash tests/scheme/run-all.sh > /tmp/scheme-results.txt 2>&1; echo "EXIT: $?"'
```

### 4e. Fetch results

```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/tmp/kaappi-test-hostkeys \
  root@$IP 'cat /tmp/scheme-results.txt'
```

If step 4d times out or disconnects, the results file still exists on the
droplet — reconnect and fetch it.

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

After deletion, remove the local host-key file:

```bash
rm -f /tmp/kaappi-test-hostkeys
```

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
- **Security model**: the droplet is throwaway (55 min lifetime), single-purpose.
  Host keys are pinned on first contact (TOFU). The DO API token is stored in a
  root-only file, never exposed on the command line. Repository code (which could
  be from an untrusted branch) runs as the unprivileged `tester` user with no
  access to the token or root privileges.
- **Stale droplets**: if a session dies mid-test, find and destroy orphans:
  list droplets via `mcp__digitalocean-droplets__droplet-list` and look for
  names starting with `kaappi-test-`.
- **Bash guard hook**: the local `bash-guard-pre.sh` hook pattern-matches
  command strings before they reach SSH. Avoid `rm -rf` inside SSH heredocs
  — the guard blocks it even though it would run on the remote. This is a
  throwaway droplet, so cleanup before clone is unnecessary anyway.
- **macOS has no `timeout`**: don't use `timeout N ssh ...`. Instead, split
  long-running work into separate SSH commands and use `ServerAliveInterval`.
