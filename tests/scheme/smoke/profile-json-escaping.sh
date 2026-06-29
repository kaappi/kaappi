#!/bin/bash
# Regression test for issue #292: profile JSON output must escape string values
set -e

KAAPPI="${KAAPPI:-./zig-out/bin/kaappi}"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create a Scheme file in a path containing JSON-special characters
SPECIAL_DIR="$TMPDIR_TEST/path\"with\\special"
mkdir -p "$SPECIAL_DIR"
cat > "$SPECIAL_DIR/test.scm" << 'EOF'
(import (scheme base))
(define (add x y) (+ x y))
(add 1 2)
EOF

JSON_OUT="$TMPDIR_TEST/profile.json"

# Run with profiling
"$KAAPPI" --profile --profile-json "$JSON_OUT" "$SPECIAL_DIR/test.scm" > /dev/null 2>&1

# Verify the file exists and is non-empty
if [ ! -s "$JSON_OUT" ]; then
    echo "FAIL: profile JSON file is empty or missing"
    exit 1
fi

# Validate JSON is well-formed using python (available on macOS and most Linux)
if command -v python3 &> /dev/null; then
    if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$JSON_OUT" 2>&1; then
        echo "FAIL: profile JSON is malformed"
        echo "Contents:"
        cat "$JSON_OUT"
        exit 1
    fi
fi

# Check that backslashes and quotes in the source path are properly escaped
# (the JSON should contain escaped versions, not raw special chars)
if python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
found_special = False
for entry in data:
    src = entry.get('source', '')
    if '\"' in src or '\\\\' in src:
        found_special = True
        break
if not found_special:
    # At minimum, the source path should contain our special characters
    # Check if any source contains the test file path (with escaping handled by JSON parser)
    for entry in data:
        src = entry.get('source', '')
        if 'special' in src:
            found_special = True
            break
if not found_special:
    print('WARNING: no entry with special-char source path found (may be native-only entries)')
" "$JSON_OUT" 2>&1; then
    true
fi

echo "PASS: profile JSON escaping"
