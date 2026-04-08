#!/bin/bash
set -euo pipefail

# compare-builds.sh — Compare two normalized .app bundles for functional equivalence.
# Both bundles should have been processed by normalize-app.sh first.
#
# Usage: ./scripts/compare-builds.sh <path/to/build1.app> <path/to/build2.app>
#
# Exit codes:
#   0 — Functionally equivalent (no code differences)
#   1 — Code differences found

APP1="${1:?Usage: compare-builds.sh <build1.app> <build2.app>}"
APP2="${2:?Usage: compare-builds.sh <build1.app> <build2.app>}"

if [ ! -d "$APP1" ]; then
  echo "Error: $APP1 is not a directory" >&2
  exit 1
fi
if [ ! -d "$APP2" ]; then
  echo "Error: $APP2 is not a directory" >&2
  exit 1
fi

echo "==> Comparing builds:"
echo "    Build 1: $APP1"
echo "    Build 2: $APP2"
echo ""

IDENTICAL=0
DIFFERENT=0
ONLY_IN_1=0
ONLY_IN_2=0
DIFF_FILES=()

# Get sorted file lists relative to the .app root
FILES1=$(cd "$APP1" && find . -type f | sort)
FILES2=$(cd "$APP2" && find . -type f | sort)

# Check for files only in one build
ONLY1=$(comm -23 <(echo "$FILES1") <(echo "$FILES2"))
ONLY2=$(comm -13 <(echo "$FILES1") <(echo "$FILES2"))

if [ -n "$ONLY1" ]; then
  ONLY_IN_1=$(echo "$ONLY1" | wc -l | tr -d ' ')
  echo "--- Files only in Build 1 ($ONLY_IN_1):"
  echo "$ONLY1" | sed 's/^/    /'
  echo ""
fi

if [ -n "$ONLY2" ]; then
  ONLY_IN_2=$(echo "$ONLY2" | wc -l | tr -d ' ')
  echo "--- Files only in Build 2 ($ONLY_IN_2):"
  echo "$ONLY2" | sed 's/^/    /'
  echo ""
fi

# Compare common files
COMMON=$(comm -12 <(echo "$FILES1") <(echo "$FILES2"))

while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  if cmp -s "$APP1/$relpath" "$APP2/$relpath"; then
    IDENTICAL=$((IDENTICAL + 1))
  else
    DIFFERENT=$((DIFFERENT + 1))
    DIFF_FILES+=("$relpath")
  fi
done <<< "$COMMON"

# Report
echo "==> Results:"
echo "    Identical files:    $IDENTICAL"
echo "    Different files:    $DIFFERENT"
echo "    Only in Build 1:    $ONLY_IN_1"
echo "    Only in Build 2:    $ONLY_IN_2"

if [ "$DIFFERENT" -gt 0 ]; then
  echo ""
  echo "--- Files with differences ($DIFFERENT):"
  for f in "${DIFF_FILES[@]}"; do
    SIZE1=$(stat -f%z "$APP1/$f" 2>/dev/null || echo "?")
    SIZE2=$(stat -f%z "$APP2/$f" 2>/dev/null || echo "?")
    echo "    $f  (${SIZE1}B vs ${SIZE2}B)"
  done
fi

TOTAL_DIFF=$((DIFFERENT + ONLY_IN_1 + ONLY_IN_2))
if [ "$TOTAL_DIFF" -eq 0 ]; then
  echo ""
  echo "==> PASS: Builds are functionally equivalent."
  exit 0
else
  echo ""
  echo "==> FAIL: Builds differ in $TOTAL_DIFF file(s)."
  exit 1
fi
