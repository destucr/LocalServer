#!/bin/zsh
# Quality gate. Run before every release, and before you push a change you care about.
# Fails on any compiler warning or failing self-test.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building…"
touch Sources/Switchboard/*.swift   # force a full compile so warnings are not hidden by the cache
OUT="$(swift build 2>&1)"
if echo "$OUT" | grep -q "error:"; then echo "$OUT" | grep "error:"; echo "FAILED: build errors"; exit 1; fi
if echo "$OUT" | grep -q "warning:"; then echo "$OUT" | grep "warning:" | sed 's/\x1b\[[0-9;]*m//g' | sort -u; echo "FAILED: compiler warnings"; exit 1; fi

echo "Self-test…"
"$(swift build --show-bin-path)/Switchboard" --selftest
echo "check.sh passed"
