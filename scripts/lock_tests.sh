#!/usr/bin/env bash
# lock_tests.sh — SHA256-hashes every test file and writes to .test_locks.json.
# After this runs, the auto-fix loop is forbidden from modifying any of these
# files. The loop must call verify_locks (below) before every fix.
#
# Run from the project root (where pubspec.yaml lives).

set -euo pipefail

LOCK_FILE=".test_locks.json"
TEST_DIRS=("test" "integration_test")

if [[ ! -f "pubspec.yaml" ]]; then
  echo "ERROR: lock_tests.sh must be run from a Flutter project root (pubspec.yaml not found)." >&2
  exit 1
fi

# Pick a hash command that exists on the host
if command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
else
  echo "ERROR: neither shasum nor sha256sum found on PATH." >&2
  exit 1
fi

echo "{" > "$LOCK_FILE"
echo "  \"locked_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"," >> "$LOCK_FILE"
echo "  \"files\": {" >> "$LOCK_FILE"

first=true
for dir in "${TEST_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' file; do
      hash=$($HASH_CMD "$file" | awk '{print $1}')
      if [[ "$first" == "true" ]]; then
        first=false
      else
        echo "," >> "$LOCK_FILE"
      fi
      printf "    \"%s\": \"%s\"" "$file" "$hash" >> "$LOCK_FILE"
    done < <(find "$dir" -type f -name "*.dart" -print0)
  fi
done

echo "" >> "$LOCK_FILE"
echo "  }" >> "$LOCK_FILE"
echo "}" >> "$LOCK_FILE"

count=$(grep -c '"test/\|"integration_test/' "$LOCK_FILE" || true)
echo "🔒 Locked $count test file(s) -> $LOCK_FILE"
