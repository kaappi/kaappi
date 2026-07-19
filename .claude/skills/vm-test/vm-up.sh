#!/usr/bin/env bash
# Power on a local UTM virtual machine by its ssh-config alias and wait for SSH.
#
# Usage:   vm-up.sh <alias>
#   alias ∈ freebsd | openbsd | netbsd | alpine | alpine-ppc64le | win11
#
# Env overrides:
#   UTMCTL      path to utmctl        (default: UTM.app bundle, then PATH)
#   WAIT_ITERS  ssh poll attempts     (default: 60; ~5 s each ≈ 5 min)
#
# Exit: 0 = VM up and SSH reachable, non-zero otherwise.
set -euo pipefail

UTMCTL="${UTMCTL:-/Applications/UTM.app/Contents/MacOS/utmctl}"
[ -x "$UTMCTL" ] || UTMCTL="$(command -v utmctl 2>/dev/null || true)"
if [ -z "$UTMCTL" ] || [ ! -x "$UTMCTL" ]; then
  echo "error: utmctl not found. Install UTM, or set UTMCTL=/path/to/utmctl." >&2
  exit 1
fi

alias="${1:-}"
case "$alias" in
  freebsd)         vm="FreeBSD 15.1" ;;
  openbsd)         vm="OpenBSD 7.9" ;;
  netbsd)          vm="NetBSD 10.1" ;;
  alpine)          vm="Alpine-s390x" ;;
  alpine-ppc64le)  vm="Alpine-ppc64le" ;;
  win11)           vm="Windows 11" ;;
  *)
    echo "error: unknown VM alias '${alias}'." >&2
    echo "known aliases: freebsd openbsd netbsd alpine alpine-ppc64le win11" >&2
    exit 2 ;;
esac

# Make sure the UTM app itself is running (utmctl talks to it; it can't
# control anything if the app is closed). -g = don't steal focus.
open -ga UTM 2>/dev/null || true

status="$("$UTMCTL" status "$vm" 2>/dev/null || true)"
echo "VM '$vm' (ssh: $alias) status: ${status:-unknown}"

if [ "$status" != "started" ]; then
  echo "Starting '$vm' ..."
  "$UTMCTL" start "$vm"
fi

# Wait for SSH. BatchMode=yes never prompts (key auth only); accept-new
# trusts a first-seen host key but still refuses a *changed* one.
iters="${WAIT_ITERS:-60}"
printf 'Waiting for ssh %s ' "$alias"
for _ in $(seq 1 "$iters"); do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes \
         -o StrictHostKeyChecking=accept-new \
         "$alias" "exit 0" 2>/dev/null; then
    printf '\nSSH ready: %s\n' "$alias"
    exit 0
  fi
  printf '.'
  sleep 5
done

printf '\nerror: ssh %s not reachable after %s attempts.\n' "$alias" "$iters" >&2
echo "The VM may still be booting (emulated s390x/ppc64le are slow) — retry, or" >&2
echo "raise the budget with WAIT_ITERS=120 bash .../vm-up.sh $alias" >&2
exit 1
