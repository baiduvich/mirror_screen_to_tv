#!/usr/bin/env bash
# run_tests.sh — runs the test suite 3 times with kTestMode=true and produces
# structured JSON output. Used by Phase 4 of the skill.
#
# Output: .test_results.json with the shape:
# {
#   "ran_at": "...",
#   "tests": [
#     {
#       "name": "convert_happy_path",
#       "layer": "integration",
#       "runs": [{"pass": true, "log": "..."}, ...],
#       "status": "pass" | "flake_tolerant_pass" | "real_failure",
#       "fail_log": "..." (only if real_failure)
#     }
#   ]
# }
#
# Run from project root.

set -uo pipefail  # no -e: we want to capture failures, not abort on them

if [[ ! -f "pubspec.yaml" ]]; then
  echo "ERROR: run_tests.sh must be run from a Flutter project root." >&2
  exit 1
fi

OUT=".test_results.json"
RUNS=3
DART_DEFINE="--dart-define=TEST_MODE=true"

echo "Running test suite 3x with kTestMode=true..."
echo "(per-test results will be aggregated into $OUT)"
echo ""

# We rely on `flutter test --machine` for unit + widget tests (it emits NDJSON
# per-test events) and `flutter test integration_test --machine` for integration.
# Each run writes to a separate temp file; we aggregate after.

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

for run in $(seq 1 $RUNS); do
  echo "=== Run $run/$RUNS ==="

  if [[ -d "test" ]]; then
    flutter test --machine $DART_DEFINE > "$TMPDIR/unit_widget_$run.json" 2>&1 || true
  fi

  if [[ -d "integration_test" ]]; then
    flutter test integration_test --machine $DART_DEFINE > "$TMPDIR/integration_$run.json" 2>&1 || true
  fi
done

# Aggregate using a small Python helper (Python 3 is available on any Mac with
# Flutter installed; if not, the user can install it).
python3 <<PYEOF
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone

tmp = Path(os.environ.get("TMPDIR", "$TMPDIR"))
runs = $RUNS
out_path = "$OUT"

# Collect per-test pass/fail across runs
# flutter test --machine emits one JSON object per line; testStart/testDone events
# carry the test name and result.
tests = {}  # name -> list of {pass, log}

def parse_machine_log(path):
    if not path.exists():
        return
    with path.open() as f:
        lines = f.readlines()
    test_id_to_name = {}
    test_id_to_log = {}
    for line in lines:
        line = line.strip()
        if not line or not line.startswith("["):
            # The first line of flutter --machine is sometimes a wrapping array; skip.
            try:
                events = json.loads(line)
                if isinstance(events, list):
                    process_events(events, test_id_to_name, test_id_to_log)
                    continue
            except Exception:
                pass
            continue
        try:
            events = json.loads(line)
            if not isinstance(events, list):
                events = [events]
            process_events(events, test_id_to_name, test_id_to_log)
        except json.JSONDecodeError:
            continue
    return test_id_to_name, test_id_to_log

def process_events(events, names, logs):
    for e in events:
        if not isinstance(e, dict):
            continue
        et = e.get("type")
        if et == "testStart":
            t = e.get("test", {})
            tid = t.get("id")
            if tid is not None:
                names[tid] = t.get("name", "<unnamed>")
                logs[tid] = []
        elif et == "print":
            tid = e.get("testID")
            if tid in logs:
                logs[tid].append(e.get("message", ""))
        elif et == "error":
            tid = e.get("testID")
            if tid in logs:
                logs[tid].append("ERROR: " + e.get("error", ""))
                logs[tid].append(e.get("stackTrace", ""))
        elif et == "testDone":
            tid = e.get("testID")
            result = e.get("result", "unknown")
            hidden = e.get("hidden", False)
            if hidden or tid not in names:
                continue
            name = names[tid]
            log = "\n".join(logs.get(tid, []))
            tests.setdefault(name, []).append({
                "pass": result == "success",
                "log": log,
            })

for run in range(1, runs + 1):
    for fname in (f"unit_widget_{run}.json", f"integration_{run}.json"):
        parse_machine_log(tmp / fname)

# Classify each test
result_list = []
for name, run_results in sorted(tests.items()):
    passes = sum(1 for r in run_results if r["pass"])
    total = len(run_results)
    if passes == total:
        status = "pass"
    elif passes >= 2:
        status = "flake_tolerant_pass"
    else:
        status = "real_failure"
    entry = {
        "name": name,
        "runs": run_results,
        "passes": passes,
        "total_runs": total,
        "status": status,
    }
    if status == "real_failure":
        # Pick the most informative failure log (first failed run)
        for r in run_results:
            if not r["pass"]:
                entry["fail_log"] = r["log"]
                break
    result_list.append(entry)

output = {
    "ran_at": datetime.now(timezone.utc).isoformat(),
    "total_tests": len(result_list),
    "passed": sum(1 for t in result_list if t["status"] == "pass"),
    "flake_tolerant": sum(1 for t in result_list if t["status"] == "flake_tolerant_pass"),
    "real_failures": sum(1 for t in result_list if t["status"] == "real_failure"),
    "tests": result_list,
}

with open(out_path, "w") as f:
    json.dump(output, f, indent=2)

print(f"")
print(f"Results: {output['passed']} pass, {output['flake_tolerant']} flake-tolerant, {output['real_failures']} real failures")
print(f"Detailed JSON -> {out_path}")
PYEOF
