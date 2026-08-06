#!/bin/bash
# `kaappi-lsp` — end-to-end language-server protocol driver (audit Phase 6D).
#
# The server is a JSON-RPC 2.0 peer speaking LSP over stdio with `Content-Length`
# framing, so it needs no editor to test: this script writes a framed request
# stream to the real binary's stdin and asserts on the framed responses. Each
# case is a fresh process, which is also what makes the state-leak cases below
# meaningful — anything that persists does so inside one session by design.
#
# What is covered:
#   * the advertised `initialize` capability set (the server's own inventory)
#   * framing: exact `Content-Length`, `jsonrpc`/`id` correlation
#   * a full session: initialize -> initialized -> didOpen -> feature requests
#     -> shutdown -> exit
#   * diagnostics cross-checked against `kaappi check --diagnostics=json`, which
#     shares the serializer in src/lsp_diagnostic.zig (docs/dev/diagnostics-json.md)
#   * protocol edges: pre-initialize requests, unknown methods, malformed
#     framing, malformed bodies, unopened documents, non-Scheme content
#
# Assertions disabled with `# FAIL: #1980` are reproduced defects; each keeps an
# enabled control beside it so the surrounding mechanism stays covered.

set -uo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"

# The language server is its own binary installed beside kaappi.
BINDIR="$(dirname "$KAAPPI")"
case "$KAAPPI" in
    *.exe) LSP="$BINDIR/kaappi-lsp.exe" ;;
    *) LSP="$BINDIR/kaappi-lsp" ;;
esac
if [[ ! -x "$LSP" ]]; then
    echo "SKIP: kaappi-lsp not built at $LSP"
    exit 77
fi

# macOS has no timeout(1); a wedged server must not wedge the suite.
if command -v timeout > /dev/null 2>&1; then
    run_timeout() { timeout "$@"; }
elif command -v gtimeout > /dev/null 2>&1; then
    run_timeout() { gtimeout "$@"; }
else
    run_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
fi

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}
fail() {
    echo "FAIL: $1 — $2"
    FAIL=$((FAIL + 1))
}

# --- request-stream construction ----------------------------------------

# stream_reset: start a new request stream.
stream_reset() { : > "$TMP/in"; }

# msg <json>: append one correctly framed JSON-RPC message.
msg() {
    local j="$1" n
    n=$(printf '%s' "$j" | wc -c | tr -d ' ')
    printf 'Content-Length: %s\r\n\r\n%s' "$n" "$j" >> "$TMP/in"
}

# raw <bytes>: append literal bytes (printf escapes honoured) — for the
# deliberately malformed framing cases.
raw() { printf '%b' "$1" >> "$TMP/in"; }

# Canonical messages. `initialize` uses id 1 throughout, so every other
# assertion can filter it out by id.
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
INITED='{"jsonrpc":"2.0","method":"initialized","params":{}}'
EXITN='{"jsonrpc":"2.0","method":"exit"}'

# did_open <uri> <text-json-string-body>: a didOpen whose text is already
# JSON-escaped (use \n for newlines).
did_open() {
    msg '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$1"'","languageId":"scheme","version":1,"text":"'"$2"'"}}}'
}
did_change() {
    msg '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"'"$1"'","version":2},"contentChanges":[{"text":"'"$2"'"}]}}'
}
# pos_req <id> <method> <uri> <line> <char>
pos_req() {
    msg '{"jsonrpc":"2.0","id":'"$1"',"method":"'"$2"'","params":{"textDocument":{"uri":"'"$3"'"},"position":{"line":'"$4"',"character":'"$5"'}}}'
}

OUT=""
RC=0
# lsp_run: feed the built stream to the server, capture stdout and exit status.
lsp_run() {
    OUT="$(run_timeout 30 "$LSP" < "$TMP/in" 2> "$TMP/err")"
    RC=$?
    if [[ $RC -eq 124 || $RC -eq 142 ]]; then
        echo "HANG: server did not exit within 30s"
    fi
}

# --- assertion helpers ---------------------------------------------------
#
# Every match uses a here-string, never a pipe into `grep -q`: under pipefail a
# `grep -q` that matches an early line kills the writer with SIGPIPE and the
# pipeline reports failure on text that is present (kaappi#1967). Patterns are
# plain ERE via `grep -E` — GNU's `\?`/`\|`/`\+` match nothing on OpenBSD.

has() { grep -qE -- "$2" <<< "$1"; }

assert_has() {
    if has "$2" "$3"; then pass "$1"; else fail "$1" "output lacks /$3/"; fi
}
assert_lacks() {
    if has "$2" "$3"; then fail "$1" "output unexpectedly has /$3/"; else pass "$1"; fi
}
assert_eq() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$3', got '$2'"; fi
}

# count <text> <fixed-substring>: occurrences, not matching lines (the wire
# format is one long CRLF-delimited blob, so `grep -c` would always say 1).
count() { grep -oF -- "$2" <<< "$1" | wc -l | tr -d ' '; }

# first_code / first_diag_line: pull fields out of a diagnostics frame.
first_code() { grep -oE '"code":"KP[0-9]+"' <<< "$1" | head -1 | sed 's/.*\(KP[0-9]*\).*/\1/'; }
first_diag_line() { grep -oE '"start":\{"line":[0-9]+' <<< "$1" | head -1 | sed 's/.*://'; }

echo "=== kaappi-lsp: $LSP ==="

# ========================================================================
# 1. initialize — the advertised capability inventory
# ========================================================================
stream_reset
msg "$INIT"
msg "$EXITN"
lsp_run

assert_has "initialize: response is JSON-RPC 2.0" "$OUT" '"jsonrpc":"2.0"'
assert_has "initialize: response id matches request id 1" "$OUT" '"id":1,"result":'
assert_has "initialize: serverInfo names kaappi-lsp" "$OUT" '"serverInfo":\{"name":"kaappi-lsp"'
assert_has "initialize: serverInfo carries a version" "$OUT" '"version":"[0-9]+\.[0-9]+\.[0-9]+"'
# textDocumentSync 1 = Full. The server only ever reads contentChanges[0].text,
# so advertising Full (not Incremental) is what makes didChange correct.
assert_has "capability: textDocumentSync = 1 (Full)" "$OUT" '"textDocumentSync":1'
assert_has "capability: hoverProvider" "$OUT" '"hoverProvider":true'
assert_has "capability: documentSymbolProvider" "$OUT" '"documentSymbolProvider":true'
assert_has "capability: definitionProvider" "$OUT" '"definitionProvider":true'
assert_has "capability: referencesProvider" "$OUT" '"referencesProvider":true'
assert_has "capability: completionProvider, no resolve" "$OUT" '"completionProvider":\{"resolveProvider":false'
# Capabilities the server does NOT implement must not be advertised, or an
# editor will send requests that get -32601 back.
assert_lacks "capability: no formattingProvider advertised" "$OUT" 'formattingProvider'
assert_lacks "capability: no renameProvider advertised" "$OUT" 'renameProvider'
assert_lacks "capability: no codeActionProvider advertised" "$OUT" 'codeActionProvider'

# ========================================================================
# 2. framing — exact Content-Length, and one frame per request
# ========================================================================
# A lone `shutdown` produces exactly one 38-byte body; the header is 22 bytes,
# so a correctly framed reply is exactly 60 bytes on the wire.
stream_reset
msg '{"jsonrpc":"2.0","id":7,"method":"shutdown"}'
lsp_run
run_timeout 30 "$LSP" < "$TMP/in" 2> /dev/null > "$TMP/raw"
assert_eq "framing: declared Content-Length is exact" \
    "$(grep -oE 'Content-Length: [0-9]+' < "$TMP/raw" | head -1)" "Content-Length: 38"
assert_eq "framing: header + body is the whole stdout" \
    "$(wc -c < "$TMP/raw" | tr -d ' ')" "60"
assert_has "framing: header terminated by CRLFCRLF" "$(cat "$TMP/raw")" 'Content-Length: 38'

stream_reset
msg "$INIT"
msg '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_eq "framing: two requests produce exactly two frames" "$(count "$OUT" 'Content-Length:')" "2"
assert_has "framing: second reply correlates to id 2" "$OUT" '"id":2,"result":null'
assert_eq "framing: notifications (initialized/exit) produce no reply" \
    "$(count "$OUT" '"id":3')" "0"

# ========================================================================
# 3. a full end-to-end session
# ========================================================================
DOC="file:///lsp-audit/session.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$DOC" '(define (twice x) (+ x x))\n(display (twice 21))\n'
msg '{"jsonrpc":"2.0","id":10,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'"$DOC"'"}}}'
pos_req 11 "textDocument/hover" "$DOC" 1 3
pos_req 12 "textDocument/definition" "$DOC" 1 12
pos_req 13 "textDocument/references" "$DOC" 1 12
pos_req 14 "textDocument/completion" "$DOC" 0 0
msg '{"jsonrpc":"2.0","id":15,"method":"shutdown"}'
msg "$EXITN"
lsp_run

assert_eq "session: server exits cleanly after exit" "$RC" "0"
assert_has "session: didOpen publishes diagnostics for the document" "$OUT" \
    '"method":"textDocument/publishDiagnostics"'
assert_has "session: a valid document reports no diagnostics" "$OUT" '"diagnostics":\[\]'
assert_has "session: documentSymbol finds the defined procedure" "$OUT" \
    '"id":10,"result":\[\{"name":"twice","kind":12'
assert_has "session: documentSymbol locates it on line 0" "$OUT" \
    '"name":"twice".*"start":\{"line":0'
assert_has "session: hover reports the builtin's type" "$OUT" \
    '"id":11,"result":\{"contents":\{"kind":"markdown"'
assert_has "session: hover names the symbol under the cursor" "$OUT" '\*\*procedure\*\* `display`'
assert_has "session: hover reports arity" "$OUT" 'Arity: '
assert_has "session: definition resolves to the defining line" "$OUT" \
    '"id":12,"result":\{"uri":"[^"]*","range":\{"start":\{"line":0'
assert_has "session: references finds both occurrences" "$OUT" \
    '"id":13,"result":\[\{.*\},\{.*\}\]'
assert_has "session: completion returns labelled items" "$OUT" '"id":14,"result":\[\{"label":'
assert_has "session: completion items carry a kind" "$OUT" '"label":"[^"]*","kind":[0-9]+'
assert_has "session: shutdown is answered with a null result" "$OUT" '"id":15,"result":null'
# Every request id issued must come back exactly once, in order.
assert_eq "session: all 6 request ids answered" \
    "$(count "$OUT" '"id":10')$(count "$OUT" '"id":11')$(count "$OUT" '"id":12')$(count "$OUT" '"id":13')$(count "$OUT" '"id":14')$(count "$OUT" '"id":15')" \
    "111111"

# references must ignore occurrences inside strings and comments.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$DOC" '(define foo 1)\n(display \"foo in a string\")\n;; foo in a comment\n(display foo)\n'
pos_req 20 "textDocument/references" "$DOC" 0 8
msg "$EXITN"
lsp_run
assert_eq "references: string and comment occurrences are skipped" \
    "$(count "$OUT" '"start":{"line":')" "2"
assert_has "references: the definition occurrence is reported" "$OUT" \
    '"start":\{"line":0,"character":8\},"end":\{"line":0,"character":11\}'
assert_has "references: the use occurrence is reported" "$OUT" \
    '"start":\{"line":3,"character":9\},"end":\{"line":3,"character":12\}'

# documentSymbol kinds across the four recognised defining forms.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$DOC" '(define a 1)\n\n;; c\n(define (b) 2)\n\n\n(define-syntax m (syntax-rules () ((_) 1)))\n(define-record-type <p> (mk f) p? (f g))\n'
msg '{"jsonrpc":"2.0","id":21,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'"$DOC"'"}}}'
msg "$EXITN"
lsp_run
assert_has "documentSymbol: plain define is a Variable (13)" "$OUT" '"name":"a","kind":13'
assert_has "documentSymbol: procedure define is a Function (12)" "$OUT" '"name":"b","kind":12'
assert_has "documentSymbol: define-syntax is kind 14" "$OUT" '"name":"m","kind":14'
assert_has "documentSymbol: define-record-type is a Struct (23)" "$OUT" '"name":"<p>","kind":23'
assert_has "documentSymbol: line numbers survive blank lines/comments" "$OUT" \
    '"name":"b".*"start":\{"line":3'

# ========================================================================
# 4. diagnostics cross-check against `kaappi check --diagnostics=json`
# ========================================================================
# Both surfaces serialize through src/lsp_diagnostic.zig, so `code`, `severity`
# and the start line must agree on the same source (docs/dev/diagnostics-json.md).
# `check` prints its JSON Lines on stdout (docs/dev/check.md).

crosscheck() { # crosscheck <label> <json-escaped-text> <literal-text>
    local label="$1" esc="$2" lit="$3" f="$TMP/x.scm"
    printf '%b' "$lit" > "$f"
    stream_reset
    msg "$INIT"
    msg "$INITED"
    did_open "file://$f" "$esc"
    msg "$EXITN"
    lsp_run
    local lcode lline ccode cline cout
    cout="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$f" 2> /dev/null)"
    lcode="$(first_code "$OUT")"
    lline="$(first_diag_line "$OUT")"
    ccode="$(first_code "$cout")"
    cline="$(first_diag_line "$cout")"
    assert_eq "crosscheck/$label: code agrees (lsp=$lcode check=$ccode)" "$lcode" "$ccode"
    assert_eq "crosscheck/$label: start line agrees" "$lline" "$cline"
    assert_eq "crosscheck/$label: severity agrees" \
        "$(grep -oE '"severity":[0-9]+' <<< "$OUT" | head -1)" \
        "$(grep -oE '"severity":[0-9]+' <<< "$cout" | head -1)"
    assert_has "crosscheck/$label: lsp source is kaappi" "$OUT" '"source":"kaappi"'
    assert_has "crosscheck/$label: check source is kaappi" "$cout" '"source":"kaappi"'
}

crosscheck "unterminated-string" '(display \"abc\n' '(display "abc\n'
crosscheck "reader-eof" '(display 1\n' '(display 1\n'
crosscheck "compile-if" '(define x 1)\n(if)\n' '(define x 1)\n(if)\n'
crosscheck "compile-line-3" ';; c\n;; c\n\n(if)\n' ';; c\n;; c\n\n(if)\n'

# A clean file must produce an empty diagnostics array on both surfaces.
printf '(define (f x) x)\n' > "$TMP/clean.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "file://$TMP/clean.scm" '(define (f x) x)\n'
msg "$EXITN"
lsp_run
assert_has "crosscheck/clean: lsp publishes an empty array" "$OUT" '"diagnostics":\[\]'
assert_eq "crosscheck/clean: check exits 0" \
    "$(run_timeout 30 "$KAAPPI" check "$TMP/clean.scm" > /dev/null 2>&1 && echo 0 || echo 1)" "0"

# -- multi-error divergence ------------------------------------------------
# `runDiagnostics` breaks out of its loop on the first failing form, so a file
# with two independent errors publishes one diagnostic where `check` reports two.
printf '(if)\n(let)\n' > "$TMP/two.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "file://$TMP/two.scm" '(if)\n(let)\n'
msg "$EXITN"
lsp_run
TWO_CHK="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$TMP/two.scm" 2> /dev/null)"
# Control: `check` really does see both errors, so the LSP's count is the outlier.
assert_eq "multi-error control: check reports 2 diagnostics" "$(count "$TWO_CHK" '"severity":')" "2"
assert_eq "multi-error control: lsp reports the first error's code" "$(first_code "$OUT")" "KP2001"
# FAIL: #1980 (LSP stops at the first bad form; check reports every one)
# assert_eq "multi-error: lsp reports both diagnostics" "$(count "$OUT" '"severity":')" "2"

# -- lint (KP4xxx) coverage divergence ------------------------------------
# `check` adds a lint pass on top of read+compile; the LSP runs neither, so an
# editor shows a clean file where `check` reports an error and exits 1.
printf '(car 1 2 3)\n' > "$TMP/arity.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "file://$TMP/arity.scm" '(car 1 2 3)\n'
msg "$EXITN"
lsp_run
ARITY_CHK="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$TMP/arity.scm" 2> /dev/null)"
# Control: check flags it as a hard error, and the LSP's own diagnostics path is
# demonstrably working (the crosscheck cases above), so the gap is the lint pass.
assert_eq "lint control: check reports KP4002 for (car 1 2 3)" "$(first_code "$ARITY_CHK")" "KP4002"
assert_has "lint control: lsp did publish a diagnostics frame" "$OUT" \
    '"method":"textDocument/publishDiagnostics"'
# FAIL: #1981 (LSP runs no KP4xxx lint pass; check's arity error is invisible in an editor)
# assert_eq "lint: lsp reports KP4002 too" "$(first_code "$OUT")" "KP4002"

printf '(display undefined-thing-xyz)\n' > "$TMP/warn.scm"
WARN_CHK="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$TMP/warn.scm" 2> /dev/null)"
assert_eq "lint control: check emits a severity-2 warning (KP4001)" "$(first_code "$WARN_CHK")" "KP4001"
assert_has "lint control: that warning really is severity 2" "$WARN_CHK" '"severity":2'
# FAIL: #1980 (LSP never emits severity 2 — only read/compile errors reach addDiagnostic)
# stream_reset; msg "$INIT"; msg "$INITED"
# did_open "file://$TMP/warn.scm" '(display undefined-thing-xyz)\n'; msg "$EXITN"; lsp_run
# assert_has "lint: lsp emits the same warning" "$OUT" '"severity":2'

# -- range fidelity --------------------------------------------------------
# The LSP hardcodes character 0..999; `check` carries the real span. Same code,
# same line, different columns — the shared serializer guarantees the shape, not
# the values.
printf '(define (f) (if))\n' > "$TMP/nest.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "file://$TMP/nest.scm" '(define (f) (if))\n'
msg "$EXITN"
lsp_run
NEST_CHK="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$TMP/nest.scm" 2> /dev/null)"
assert_eq "range control: code still agrees on a nested error" \
    "$(first_code "$OUT")" "$(first_code "$NEST_CHK")"
assert_has "range control: check pinpoints the inner (if)" "$NEST_CHK" \
    '"start":\{"line":0,"character":12\},"end":\{"line":0,"character":16\}'
assert_has "range: lsp uses a whole-line 0..999 sentinel" "$OUT" \
    '"start":\{"line":0,"character":0\},"end":\{"line":0,"character":999\}'

# ========================================================================
# 5. protocol edges
# ========================================================================

# -- requests before initialize -------------------------------------------
stream_reset
msg '{"jsonrpc":"2.0","id":30,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///x.scm"},"position":{"line":0,"character":0}}}'
msg "$INIT"
msg "$EXITN"
lsp_run
assert_has "pre-init: a feature request errors with -32002" "$OUT" \
    '"id":30,"error":\{"code":-32002,"message":"not initialized"\}'
assert_has "pre-init: initialize itself still succeeds afterwards" "$OUT" '"id":1,"result":'

# `shutdown` is dispatched above the !initialized guard, so it is answered
# successfully before any handshake. LSP 3.17 requires -32002 for every request
# received before `initialize`.
stream_reset
msg '{"jsonrpc":"2.0","id":31,"method":"shutdown"}'
lsp_run
# Control: the guard demonstrably works for other methods (asserted just above).
assert_has "pre-init control: shutdown is answered at all" "$OUT" '"id":31'
# FAIL: #1980 (shutdown before initialize returns success, not -32002)
# assert_has "pre-init: shutdown before initialize errors -32002" "$OUT" \
#     '"id":31,"error":\{"code":-32002'

# -- unknown methods -------------------------------------------------------
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":32,"method":"textDocument/formatting","params":{}}'
msg '{"jsonrpc":"2.0","id":33,"method":"nonsense/method","params":{}}'
msg "$EXITN"
lsp_run
assert_has "unknown method: request gets -32601" "$OUT" \
    '"id":32,"error":\{"code":-32601,"message":"MethodNotFound"\}'
assert_has "unknown method: a second one also gets -32601" "$OUT" '"id":33,"error":\{"code":-32601'

# An unknown *notification* has no id and must be dropped silently, not answered.
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":3}}'
msg '{"jsonrpc":"2.0","id":34,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_eq "unknown notification: silently ignored, no extra frame" \
    "$(count "$OUT" 'Content-Length:')" "2"
assert_has "unknown notification: the following request still works" "$OUT" '"id":34,"result":null'

# -- shutdown/exit lifecycle ----------------------------------------------
# There is no shutdown state: a request after `shutdown` is served normally.
# LSP 3.17 requires InvalidRequest (-32600) for requests received after shutdown.
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":35,"method":"shutdown"}'
pos_req 36 "textDocument/hover" "file:///x.scm" 0 0
msg "$EXITN"
lsp_run
# Control: the same request before shutdown behaves identically, which is the
# point — the two are indistinguishable because no state is recorded.
assert_has "post-shutdown control: the request is answered" "$OUT" '"id":36'
# FAIL: #1980 (no shutdown state; post-shutdown requests should be -32600)
# assert_has "post-shutdown: request errors -32600" "$OUT" '"id":36,"error":\{"code":-32600'

# LSP 3.17: exit after shutdown -> status 0, exit without shutdown -> status 1.
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":37,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_eq "exit: clean shutdown-then-exit is status 0" "$RC" "0"
stream_reset
msg "$INIT"
msg "$INITED"
msg "$EXITN"
lsp_run
# Control: with the handshake done the server is definitely alive and running.
assert_eq "exit control: the server did terminate on exit" "$(count "$OUT" 'Content-Length:')" "1"
# FAIL: #1980 (exit without a prior shutdown must be status 1; it is 0)
# assert_eq "exit: exit without shutdown is status 1" "$RC" "1"

# EOF on stdin with no `exit` at all must terminate, not spin.
stream_reset
msg "$INIT"
msg "$INITED"
lsp_run
assert_eq "eof: server terminates when stdin closes" "$RC" "0"

# -- malformed bodies (survivable) ----------------------------------------
stream_reset
raw 'Content-Length: 7\r\n\r\nNOTJSON'
msg "$INIT"
msg '{"jsonrpc":"2.0","id":40,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "bad body: unparseable JSON is skipped, session continues" "$OUT" '"id":1,"result":'
assert_has "bad body: later requests still answered" "$OUT" '"id":40,"result":null'

stream_reset
msg "$INIT"
raw 'Content-Length: 5\r\n\r\n[1,2]'
msg '{"jsonrpc":"2.0","id":41,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "bad body: valid JSON that is not an object is skipped" "$OUT" '"id":41,"result":null'

stream_reset
msg "$INIT"
msg '{"jsonrpc":"2.0","id":42}'
msg '{"jsonrpc":"2.0","id":43,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "bad body: a message with no method is skipped" "$OUT" '"id":43,"result":null'

# -- malformed framing (fatal) --------------------------------------------
# A bad *body* is skipped and the session continues (asserted above), but a bad
# *header* makes readMessage return null, which breaks the message loop: every
# well-formed message after it is silently dropped and the process exits.
stream_reset
raw 'Content-Length: abc\r\n\r\n{}'
msg "$INIT"
msg "$EXITN"
lsp_run
# Control: the identical INIT message on its own is answered, so the drop is
# caused by the preceding malformed header and nothing else.
stream_reset
msg "$INIT"
msg "$EXITN"
lsp_run
assert_has "bad header control: a lone initialize is answered" "$OUT" '"id":1,"result":'
stream_reset
raw 'Content-Length: abc\r\n\r\n{}'
msg "$INIT"
msg "$EXITN"
lsp_run
assert_eq "bad header: server produces no output at all" "$(count "$OUT" 'Content-Length:')" "0"
# FAIL: #1980 (a non-numeric Content-Length should be resynchronised or reported,
#            not silently end the session — every later message is lost)
# assert_has "bad header: session survives a malformed Content-Length" "$OUT" '"id":1,"result":'

stream_reset
raw 'Content-Type: application/json\r\n\r\n'
msg "$INIT"
msg "$EXITN"
lsp_run
assert_eq "missing Content-Length: no output" "$(count "$OUT" 'Content-Length:')" "0"
# FAIL: #1980 (a header block with no Content-Length ends the session silently)
# assert_has "missing Content-Length: session survives" "$OUT" '"id":1,"result":'

stream_reset
raw 'Content-Length: 0\r\n\r\n'
msg "$INIT"
msg "$EXITN"
lsp_run
assert_eq "zero Content-Length: no output" "$(count "$OUT" 'Content-Length:')" "0"
# FAIL: #1980 (Content-Length: 0 is treated as a fatal read failure)
# assert_has "zero Content-Length: session survives" "$OUT" '"id":1,"result":'

# A truncated body (declared length exceeds what arrives) must not hang or crash.
stream_reset
raw 'Content-Length: 500\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize"}'
lsp_run
assert_eq "truncated body: server exits rather than hanging" "$RC" "0"

# Extra headers before Content-Length are legal and must be tolerated.
stream_reset
raw 'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n'
msg "$INIT"
msg "$EXITN"
lsp_run
assert_has "extra headers: Content-Type before Content-Length is tolerated" "$OUT" '"id":1,"result":'

# -- request id handling ---------------------------------------------------
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":"abc-1","method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "id: a string id round-trips verbatim" "$OUT" '"id":"abc-1","result":null'
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":-9,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "id: a negative integer id round-trips" "$OUT" '"id":-9,"result":null'

stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":null,"method":"shutdown"}'
msg "$EXITN"
lsp_run
# Control: integer and string ids do round-trip (asserted just above), so a
# fabricated id is specific to the unrepresentable ones.
assert_has "null id control: a reply is still produced" "$OUT" '"result":null'
# FAIL: #1980 (an id the formatter cannot render becomes 0, matching no request)
# assert_lacks "null id: server must not invent id 0" "$OUT" '"id":0'

# -- requests with missing or malformed params ----------------------------
# Every position-taking handler bails with a bare `return` when a field is
# absent, so the request is never answered and a client blocks on that id.
stream_reset
msg "$INIT"
msg "$INITED"
pos_req 50 "textDocument/hover" "file:///x.scm" 0 0
msg '{"jsonrpc":"2.0","id":51,"method":"textDocument/hover","params":{}}'
msg '{"jsonrpc":"2.0","id":52,"method":"textDocument/hover"}'
msg '{"jsonrpc":"2.0","id":53,"method":"shutdown"}'
msg "$EXITN"
lsp_run
# Control: the well-formed hover at id 50 IS answered, so the handler works and
# only the malformed variants vanish.
assert_has "missing params control: a well-formed hover is answered" "$OUT" '"id":50'
assert_has "missing params control: a later request still works" "$OUT" '"id":53,"result":null'
assert_eq "missing params: params={} produces no reply" "$(count "$OUT" '"id":51')" "0"
assert_eq "missing params: absent params produces no reply" "$(count "$OUT" '"id":52')" "0"
# FAIL: #1980 (a request with unusable params must get a response — -32602
#            InvalidParams — not silence; the client waits on that id forever)
# assert_has "missing params: params={} errors -32602" "$OUT" '"id":51,"error":'
# assert_has "missing params: absent params errors -32602" "$OUT" '"id":52,"error":'

# The same silence affects every position-taking method, not just hover.
stream_reset
msg "$INIT"
msg "$INITED"
msg '{"jsonrpc":"2.0","id":54,"method":"textDocument/definition","params":{}}'
msg '{"jsonrpc":"2.0","id":55,"method":"textDocument/references","params":{}}'
msg '{"jsonrpc":"2.0","id":56,"method":"textDocument/completion","params":{}}'
msg '{"jsonrpc":"2.0","id":57,"method":"textDocument/documentSymbol","params":{}}'
msg '{"jsonrpc":"2.0","id":58,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "missing params control: session survives all four" "$OUT" '"id":58,"result":null'
assert_eq "missing params: definition/references/completion/documentSymbol all silent" \
    "$(count "$OUT" '"id":54')$(count "$OUT" '"id":55')$(count "$OUT" '"id":56')$(count "$OUT" '"id":57')" \
    "0000"

# ========================================================================
# 6. document-store edges
# ========================================================================
UNOPENED="file:///lsp-audit/never-opened.scm"
stream_reset
msg "$INIT"
msg "$INITED"
pos_req 60 "textDocument/hover" "$UNOPENED" 0 1
pos_req 61 "textDocument/definition" "$UNOPENED" 0 1
pos_req 62 "textDocument/references" "$UNOPENED" 0 1
msg '{"jsonrpc":"2.0","id":63,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'"$UNOPENED"'"}}}'
msg "$EXITN"
lsp_run
assert_has "unopened uri: hover returns null" "$OUT" '"id":60,"result":null'
assert_has "unopened uri: definition returns null" "$OUT" '"id":61,"result":null'
assert_has "unopened uri: references returns an empty array" "$OUT" '"id":62,"result":\[\]'
assert_has "unopened uri: documentSymbol returns an empty array" "$OUT" '"id":63,"result":\[\]'

# didChange on a document that was never opened must not crash; full-sync means
# the change text simply becomes the document.
stream_reset
msg "$INIT"
msg "$INITED"
did_change "$UNOPENED" '(if)\n'
msg '{"jsonrpc":"2.0","id":64,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "didChange on unopened doc: diagnostics are published anyway" "$OUT" \
    '"uri":"'"$UNOPENED"'","diagnostics":\[\{'
assert_has "didChange on unopened doc: session survives" "$OUT" '"id":64,"result":null'

# Full-sync round trip: clean -> broken -> clean republishes each time.
CDOC="file:///lsp-audit/cycle.scm"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$CDOC" '(define x 1)\n'
did_change "$CDOC" '(if)\n'
did_change "$CDOC" '(define x 1)\n'
msg "$EXITN"
lsp_run
assert_eq "didChange: one diagnostics notification per edit" \
    "$(count "$OUT" '"method":"textDocument/publishDiagnostics"')" "3"
assert_eq "didChange: exactly one edit is diagnosed as broken" "$(count "$OUT" '"code":"KP2001"')" "1"

# didClose clears diagnostics and forgets the document.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$CDOC" '(if)\n'
msg '{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"'"$CDOC"'"}}}'
pos_req 65 "textDocument/definition" "$CDOC" 0 2
msg "$EXITN"
lsp_run
assert_eq "didClose: publishes an empty diagnostics array" "$(count "$OUT" '"diagnostics":[]')" "1"
assert_has "didClose: the document is forgotten" "$OUT" '"id":65,"result":null'

# didChange with an empty contentChanges array leaves the document alone.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$CDOC" '(define x 1)\n'
msg '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"'"$CDOC"'"},"contentChanges":[]}}'
msg '{"jsonrpc":"2.0","id":66,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"'"$CDOC"'"}}}'
msg "$EXITN"
lsp_run
assert_has "didChange with no changes: document content is preserved" "$OUT" '"id":66,"result":\[\{"name":"x"'

# ========================================================================
# 7. hostile / non-Scheme document content
# ========================================================================
# None of these may crash, hang, or wedge the session.
HDOC="file:///lsp-audit/hostile.scm"
hostile() { # hostile <label> <escaped-text> <expected-ere-or-empty>
    stream_reset
    msg "$INIT"
    msg "$INITED"
    did_open "$HDOC" "$2"
    msg '{"jsonrpc":"2.0","id":70,"method":"shutdown"}'
    msg "$EXITN"
    lsp_run
    assert_has "hostile/$1: session survives" "$OUT" '"id":70,"result":null'
    assert_eq "hostile/$1: exits cleanly" "$RC" "0"
    if [[ -n "$3" ]]; then assert_has "hostile/$1: reports $3" "$OUT" '"code":"'"$3"'"'; fi
}
hostile "empty-document" '' ''
hostile "prose-not-scheme" 'This is plain English, not Scheme at all.' ''
hostile "only-close-parens" ')))))' 'KP1003'
hostile "unterminated-block-comment" '#| never closed\n' ''
hostile "recursive-macro" '(define-syntax loop (syntax-rules () ((_ x) (loop x))))\n(loop 1)\n' 'KP2003'
hostile "lone-hash" '#' 'KP1001'
hostile "control-characters" '' ''

# -- errors raised while skipping intertoken space are discarded ----------
# runDiagnostics, handleDocumentSymbol and handleDefinition all drive the reader
# with `while (r.hasMore() catch false)`. hasMore() skips intertoken space —
# which includes `#| ... |#` and `#;` — and can fail there; `catch false` turns
# that failure into "end of input", so the loop exits normally and the error
# never becomes a diagnostic. Errors from readDatum() itself are caught and
# reported, which is why most malformed input is fine.

skipspace() { # skipspace <label> <escaped-text> <literal-text>
    printf '%b' "$3" > "$TMP/s.scm"
    stream_reset
    msg "$INIT"
    msg "$INITED"
    did_open "file://$TMP/s.scm" "$2"
    msg '{"jsonrpc":"2.0","id":72,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://'"$TMP"'/s.scm"}}}'
    msg "$EXITN"
    lsp_run
    SKIP_CHK="$(run_timeout 30 "$KAAPPI" check --diagnostics=json "$TMP/s.scm" 2> /dev/null)"
}

# Control: an unterminated *string* — a readDatum() error, not a skip error — is
# reported identically by both surfaces, so reader diagnostics do reach the LSP.
skipspace "string-control" '(display \"abc\n' '(display "abc\n'
assert_eq "skipspace control: an unterminated string agrees on both surfaces" \
    "$(first_code "$OUT")" "$(first_code "$SKIP_CHK")"
# Control: a well-formed trailing line comment is clean on both surfaces, so a
# trailing comment by itself is not the trigger.
skipspace "line-comment-control" '(define x 1)\n;; fine\n' '(define x 1)\n;; fine\n'
assert_has "skipspace control: a good trailing comment is clean in the lsp" "$OUT" '"diagnostics":\[\]'
assert_eq "skipspace control: and clean in check too" "$(count "$SKIP_CHK" '"severity":')" "0"

# An unterminated block comment at the START swallows the entire file: the LSP
# reports no diagnostic AND documentSymbol returns nothing, so a real error two
# lines down is invisible in an editor.
skipspace "leading-block-comment" '#| unterminated\n(if)\n' '#| unterminated\n(if)\n'
assert_eq "skipspace: check reports KP1001 for a leading unterminated block comment" \
    "$(first_code "$SKIP_CHK")" "KP1001"
assert_has "skipspace: the lsp reports nothing at all" "$OUT" '"diagnostics":\[\]'
assert_has "skipspace: and documentSymbol returns an empty list" "$OUT" '"id":72,"result":\[\]'
# FAIL: #1981 (`hasMore() catch false` discards every reader error raised while
#            skipping intertoken space, so an unterminated block comment hides
#            the whole file from diagnostics and documentSymbol)
# assert_eq "skipspace: leading block comment is reported by the lsp too" \
#     "$(first_code "$OUT")" "KP1001"

# The same at end-of-file, and for a dangling datum comment.
skipspace "trailing-block-comment" '(define x 1)\n#| unterminated\n' '(define x 1)\n#| unterminated\n'
assert_eq "skipspace: check reports KP1001 for a trailing unterminated block comment" \
    "$(first_code "$SKIP_CHK")" "KP1001"
assert_has "skipspace control: the good datum before it is still found" "$OUT" '"name":"x"'
# FAIL: #1980 (same mechanism at end of file)
# assert_eq "skipspace: trailing block comment is reported by the lsp too" \
#     "$(first_code "$OUT")" "KP1001"

skipspace "dangling-datum-comment" '(define x 1)\n#;\n' '(define x 1)\n#;\n'
assert_eq "skipspace: check reports KP1001 for a dangling #;" "$(first_code "$SKIP_CHK")" "KP1001"
# FAIL: #1981 (same mechanism for a datum comment with nothing to comment out)
# assert_eq "skipspace: dangling #; is reported by the lsp too" "$(first_code "$OUT")" "KP1001"

# Deeply nested input must be reported, not overflow the stack.
DEEP="$(printf '(%.0s' $(seq 1 5000))1$(printf ')%.0s' $(seq 1 5000))"
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$HDOC" "$DEEP"
msg '{"jsonrpc":"2.0","id":71,"method":"shutdown"}'
msg "$EXITN"
lsp_run
assert_has "hostile/deep-nesting: reported as KP1009, not a crash" "$OUT" '"code":"KP1009"'
assert_has "hostile/deep-nesting: session survives" "$OUT" '"id":71,"result":null'

# ========================================================================
# 8. position handling
# ========================================================================
PDOC="file:///lsp-audit/pos.scm"
posq() { # posq <line> <char> <escaped-text>
    stream_reset
    msg "$INIT"
    msg "$INITED"
    did_open "$PDOC" "$3"
    pos_req 80 "textDocument/hover" "$PDOC" "$1" "$2"
    msg "$EXITN"
    lsp_run
}
posq 0 2 '(car x)\n(display abc)\n'
assert_has "position: hover on 'car' resolves the builtin" "$OUT" '\*\*procedure\*\* `car`'
posq -5 -5 '(car x)\n(display abc)\n'
assert_has "position: negative line/character clamps to null, no crash" "$OUT" '"id":80,"result":null'
posq 99999 0 '(car x)\n(display abc)\n'
assert_has "position: line past end of document returns null" "$OUT" '"id":80,"result":null'

# A character past end-of-line is clamped to the end of the *document*, not the
# end of the line, so it can resolve a symbol on a later line entirely.
posq 0 200 '(car x)\ndisplay'
# Control: the byte-identical text with a trailing newline correctly returns
# null, which isolates the overrun to the document-end clamp.
CTRL_OUT=""
posq 0 200 '(car x)\ndisplay\n'
CTRL_OUT="$OUT"
assert_has "eol-overrun control: with a trailing newline the answer is null" "$CTRL_OUT" '"id":80,"result":null'
posq 0 200 '(car x)\ndisplay'
assert_has "eol-overrun: line 0 char 200 resolves a line-1 symbol" "$OUT" '\*\*procedure\*\* `display`'
# FAIL: #1980 (lineColToOffset clamps to text.len, so a column past end-of-line
#            walks into later lines instead of stopping at the line end)
# assert_has "eol-overrun: character past end of line returns null" "$OUT" '"id":80,"result":null'

# ========================================================================
# 9. cross-document state leakage
# ========================================================================
# runDiagnostics compiles every document into the server's single shared macro
# table (vm.macros), so a `define-syntax` in one open file permanently changes
# how every other file is diagnosed — including files that are correct alone.
ADOC="file:///lsp-audit/leak-a.scm"
BDOC="file:///lsp-audit/leak-b.scm"
MACRO='(define-syntax my-if (syntax-rules () ((_ a) (if a 1 2))))\n'
USE='(my-if)\n'

# Control 1: B alone is clean — `(my-if)` with no macro in scope is just a call.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$BDOC" "$USE"
msg "$EXITN"
lsp_run
assert_has "leak control 1: B alone is diagnosed clean" "$OUT" \
    '"uri":"'"$BDOC"'","diagnostics":\[\]'

# Control 2: macro and misuse in one document really is KP2001 — so KP2001 is
# exactly the verdict a leaked macro would produce.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" "$MACRO$USE"
msg "$EXITN"
lsp_run
assert_has "leak control 2: macro + misuse in one file is KP2001" "$OUT" '"code":"KP2001"'

# The leak: identical B text, diagnosed clean and then not, because A was opened.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$BDOC" "$USE"
did_open "$ADOC" "$MACRO"
did_change "$BDOC" "$USE"
msg "$EXITN"
lsp_run
assert_eq "leak: the same document text is diagnosed twice" \
    "$(count "$OUT" '"uri":"'"$BDOC"'"')" "2"
assert_eq "leak: both diagnoses of identical text agree" \
    "$(count "$OUT" '"code":"KP2001"')" "0"

# The leak outlives didClose of the defining document.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" "$MACRO"
msg '{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"'"$ADOC"'"}}}'
did_open "$BDOC" "$USE"
msg "$EXITN"
lsp_run
# Control: closing A does publish its clearing notification, so didClose ran.
# (With the leak fixed, B's own open is clean too, so all three frames are
# empty arrays; the count was 2 under the bug because B carried A's macro.)
assert_eq "leak control 3: didClose published its empty array" "$(count "$OUT" '"diagnostics":[]')" "3"
assert_eq "leak: closing A restores B's clean verdict" \
    "$(count "$OUT" '"code":"KP2001"')" "0"

# Control 4: a plain `define` of the same name does NOT leak, which isolates the
# mechanism to the macro table rather than the globals map.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" '(define (my-if a) a)\n'
did_open "$BDOC" "$USE"
msg "$EXITN"
lsp_run
assert_eq "leak control 4: a plain define of the same name does not leak" \
    "$(count "$OUT" '"code":"KP2001"')" "0"

# Regression guards for the fix itself, in both directions:
#  * isolation must not disable macro diagnostics within a document — a file
#    that defines AND misuses a macro is KP2001 even when another document is
#    open (the misuse is judged against the macros its own text defines);
#  * isolation must hold for a document that defines macros of its own: B
#    defining `other` must not start seeing A's `my-if` mid-file. Under the
#    leak, the second case is KP2001; with the fix it is a clean call to an
#    unbound global, exactly B's verdict alone.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" "$MACRO"
did_open "$BDOC" "$MACRO$USE"
msg "$EXITN"
lsp_run
assert_has "leak fix: own-document macro misuse stays KP2001" \
    "$OUT" '"code":"KP2001"'

stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" "$MACRO"
did_open "$BDOC" '(define-syntax other (syntax-rules () ((_) 1)))\n(my-if)\n'
msg "$EXITN"
lsp_run
assert_eq "leak fix: another doc's macro stays invisible after own define-syntax" \
    "$(count "$OUT" '"code":"KP2001"')" "0"

# Compiling a document must not publish its globals to the whole server either:
# diagnostics compile but never execute, so `define`d names stay unhoverable.
stream_reset
msg "$INIT"
msg "$INITED"
did_open "$ADOC" '(define my-special-fn 1)\n'
did_open "$BDOC" '(display my-special-fn)\n'
pos_req 90 "textDocument/hover" "$BDOC" 0 12
msg "$EXITN"
lsp_run
assert_has "no globals leak: a name defined in another document is not hoverable" \
    "$OUT" '"id":90,"result":null'

# ========================================================================
echo ""
echo "kaappi-lsp: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
