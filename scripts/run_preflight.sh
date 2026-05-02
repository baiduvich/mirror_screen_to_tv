#!/usr/bin/env bash
# run_preflight.sh — runs the Apple pre-flight checklist from references/apple_preflight.md.
# Outputs structured results to .preflight_results.json.
#
# Run from project root.

set -uo pipefail  # no -e: capture failures

if [[ ! -f "pubspec.yaml" ]]; then
  echo "ERROR: run_preflight.sh must be run from a Flutter project root." >&2
  exit 1
fi

OUT=".preflight_results.json"
PLIST="ios/Runner/Info.plist"

# Helper to append a check result. Use python at the end to write valid JSON.
declare -a CHECK_NAMES
declare -a CHECK_STATUSES
declare -a CHECK_DETAILS

record() {
  CHECK_NAMES+=("$1")
  CHECK_STATUSES+=("$2")
  CHECK_DETAILS+=("$3")
}

# 1. Release build
echo "[1/12] Release-mode build..."
if flutter build ios --release --no-codesign --quiet 2>build_err.log; then
  record "release_build" "pass" ""
else
  err=$(tail -20 build_err.log | tr '\n' ' ' | sed 's/"/\\"/g')
  record "release_build" "fail" "$err"
fi
rm -f build_err.log

# 2. Test-mode leakage (FATAL if fails)
echo "[2/12] Test-mode leakage..."
leak_issues=""
if grep -rn "TEST_MODE=true" ios/ lib/ 2>/dev/null | grep -v "test/\|integration_test/" >/dev/null; then
  leak_issues+="hardcoded TEST_MODE=true found; "
fi
# [TEST_EVENT] should only appear inside lib/test_support.dart
stray=$(grep -rn "\[TEST_EVENT\]" lib/ --include="*.dart" 2>/dev/null | grep -v "lib/test_support.dart" || true)
if [[ -n "$stray" ]]; then
  leak_issues+="[TEST_EVENT] string found outside test_support.dart; "
fi
if [[ -z "$leak_issues" ]]; then
  record "test_mode_leakage" "pass" ""
else
  record "test_mode_leakage" "fail" "$leak_issues"
fi

# 3. Privacy strings
echo "[3/12] Privacy strings in Info.plist..."
missing_keys=""
needs_key() {
  local pattern="$1"
  local key="$2"
  if grep -rq "$pattern" lib/ --include="*.dart" 2>/dev/null; then
    if ! grep -q "$key" "$PLIST" 2>/dev/null; then
      missing_keys+="$key "
    fi
  fi
}
needs_key "image_picker\|camera:" "NSCameraUsageDescription"
needs_key "image_picker\|photo_manager" "NSPhotoLibraryUsageDescription"
needs_key "record\|mic_stream\|speech_to_text" "NSMicrophoneUsageDescription"
needs_key "geolocator\|location:" "NSLocationWhenInUseUsageDescription"
needs_key "flutter_blue_plus\|flutter_blue\|flutter_reactive_ble" "NSBluetoothAlwaysUsageDescription"
needs_key "local_auth" "NSFaceIDUsageDescription"
needs_key "contacts_service\|flutter_contacts" "NSContactsUsageDescription"
needs_key "device_calendar" "NSCalendarsUsageDescription"
if [[ -z "$missing_keys" ]]; then
  record "privacy_strings" "pass" ""
else
  record "privacy_strings" "fail" "missing: $missing_keys"
fi

# 4. ATS
echo "[4/12] App Transport Security..."
ats_issue=""
if grep -A1 "NSAllowsArbitraryLoads" "$PLIST" 2>/dev/null | grep -q "<true/>"; then
  ats_issue="NSAllowsArbitraryLoads=true; "
fi
http_urls=$(grep -rn "http://" lib/ --include="*.dart" 2>/dev/null | grep -v "//.*localhost\|//.*127\.0\.0\.1" || true)
if [[ -n "$http_urls" ]]; then
  ats_issue+="unguarded http:// in code; "
fi
if [[ -z "$ats_issue" ]]; then
  if grep -q "NSExceptionDomains" "$PLIST" 2>/dev/null; then
    record "ats" "warn" "NSExceptionDomains present; verify domains are real"
  else
    record "ats" "pass" ""
  fi
else
  record "ats" "fail" "$ats_issue"
fi

# 5. Background modes
echo "[5/12] UIBackgroundModes..."
bg_issue=""
if grep -q "UIBackgroundModes" "$PLIST" 2>/dev/null; then
  declared=$(grep -A20 "UIBackgroundModes" "$PLIST" | grep -E "<string>" | sed -E 's/.*<string>(.*)<\/string>.*/\1/' | tr '\n' ' ')
  for mode in $declared; do
    case "$mode" in
      audio)
        grep -rq "audioplayers\|just_audio\|audio_service" lib/ --include="*.dart" 2>/dev/null || bg_issue+="audio mode declared but no audio package found; "
        ;;
      location)
        grep -rq "geolocator\|location:" lib/ --include="*.dart" 2>/dev/null || bg_issue+="location mode declared but no location package found; "
        ;;
      remote-notification)
        grep -rq "firebase_messaging\|flutter_local_notifications" lib/ --include="*.dart" 2>/dev/null || bg_issue+="remote-notification declared but no notification package found; "
        ;;
      fetch)
        grep -rq "BGAppRefreshTask\|workmanager" lib/ ios/ 2>/dev/null || bg_issue+="fetch declared but no background task code; "
        ;;
    esac
  done
fi
if [[ -z "$bg_issue" ]]; then
  record "background_modes" "pass" ""
else
  record "background_modes" "fail" "$bg_issue"
fi

# 6. No print/debugPrint in production
echo "[6/12] No print/debugPrint in production..."
prints=$(grep -rn -E "(^|[^a-zA-Z_])print\(" lib/ --include="*.dart" 2>/dev/null | grep -v "lib/test_support.dart" | head -10 || true)
debugprints=$(grep -rn "debugPrint" lib/ --include="*.dart" 2>/dev/null | grep -v "lib/test_support.dart" | head -10 || true)
if [[ -z "$prints" && -z "$debugprints" ]]; then
  record "no_print" "pass" ""
else
  preview=$(echo -e "$prints\n$debugprints" | head -5 | tr '\n' '|' | sed 's/"/\\"/g')
  record "no_print" "warn" "$preview"
fi

# 7. No TODO/FIXME in critical files
echo "[7/12] No TODO/FIXME in critical files..."
critical_pattern="lib/main.dart"
for f in lib/**/onboarding*.dart lib/**/paywall*.dart lib/**/purchase*.dart lib/**/subscription*.dart lib/onboarding*.dart lib/paywall*.dart lib/purchase*.dart lib/subscription*.dart; do
  [[ -f "$f" ]] && critical_pattern="$critical_pattern $f"
done
todos=$(grep -rn -E "(TODO|FIXME|XXX|HACK)" $critical_pattern 2>/dev/null | head -5 | tr '\n' '|' | sed 's/"/\\"/g' || true)
if [[ -z "$todos" ]]; then
  record "no_todos_critical" "pass" ""
else
  record "no_todos_critical" "warn" "$todos"
fi

# 8. Version bump
echo "[8/12] Version + build..."
current_version=$(grep -E "^version:" pubspec.yaml | sed -E 's/version:[[:space:]]*//' | tr -d '\r')
if [[ -d ".git" ]]; then
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [[ -z "$last_tag" ]]; then
    record "version_bump" "warn" "no git tags; current=$current_version"
  elif [[ "$current_version" == "$last_tag"* ]] || [[ "v$current_version" == "$last_tag" ]]; then
    record "version_bump" "warn" "version unchanged from tag $last_tag"
  else
    record "version_bump" "pass" "current=$current_version last_tag=$last_tag"
  fi
else
  record "version_bump" "warn" "no .git; current=$current_version"
fi

# 9. App icon
echo "[9/12] App icon..."
icon_dir="ios/Runner/Assets.xcassets/AppIcon.appiconset"
icon_issue=""
if [[ ! -d "$icon_dir" ]]; then
  icon_issue="AppIcon.appiconset directory missing"
else
  icon_count=$(find "$icon_dir" -name "*.png" -size +0 | wc -l | tr -d ' ')
  if [[ "$icon_count" -lt 8 ]]; then
    icon_issue="only $icon_count non-empty PNGs in icon set (expected ≥8)"
  fi
fi
if [[ -z "$icon_issue" ]]; then
  record "app_icon" "pass" ""
else
  record "app_icon" "fail" "$icon_issue"
fi

# 10. Launch screen
echo "[10/12] Launch screen..."
if [[ -f "ios/Runner/Base.lproj/LaunchScreen.storyboard" ]]; then
  record "launch_screen" "pass" ""
elif grep -q "UILaunchStoryboardName" "$PLIST" 2>/dev/null; then
  record "launch_screen" "pass" "via UILaunchStoryboardName"
else
  record "launch_screen" "fail" "no launch storyboard found"
fi

# 11. Pubspec resolves
echo "[11/12] Pubspec dependencies resolve..."
if flutter pub get --offline 2>/dev/null || flutter pub get 2>pubget_err.log; then
  record "pubspec_resolves" "pass" ""
else
  err=$(tail -10 pubget_err.log 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')
  record "pubspec_resolves" "fail" "$err"
fi
rm -f pubget_err.log

# 12. No test scaffolding leaked into lib/
echo "[12/12] No test scaffolding in lib/..."
leaked=$(grep -rn -E "import.*['\"]package:.*test/|import.*['\"]\.\./test/|import.*['\"]\.\./integration_test/|import.*test_helpers|import.*['\"]mock_" lib/ --include="*.dart" 2>/dev/null || true)
if [[ -z "$leaked" ]]; then
  record "no_test_leak" "pass" ""
else
  preview=$(echo "$leaked" | head -3 | tr '\n' '|' | sed 's/"/\\"/g')
  record "no_test_leak" "fail" "$preview"
fi

# Write JSON output
python3 <<PYEOF
import json
from datetime import datetime, timezone

names = """${CHECK_NAMES[@]}""".split()
statuses = """${CHECK_STATUSES[@]}""".split()
# Details have shell-special chars, can't use the bash-array-as-string trick safely.
# We'll re-build details from a tmpfile written in bash. For simplicity, leave details empty in JSON.
PYEOF

# Simpler: write JSON from bash directly
{
  echo "{"
  echo "  \"ran_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"checks\": ["
  total=${#CHECK_NAMES[@]}
  for i in "${!CHECK_NAMES[@]}"; do
    detail_escaped=$(echo "${CHECK_DETAILS[$i]}" | sed 's/"/\\"/g' | tr '\n' ' ')
    sep=","
    [[ $i -eq $((total-1)) ]] && sep=""
    echo "    {\"name\": \"${CHECK_NAMES[$i]}\", \"status\": \"${CHECK_STATUSES[$i]}\", \"detail\": \"$detail_escaped\"}$sep"
  done
  echo "  ]"
  echo "}"
} > "$OUT"

# Summary
pass_count=0
fail_count=0
warn_count=0
for s in "${CHECK_STATUSES[@]}"; do
  case "$s" in
    pass) pass_count=$((pass_count+1)) ;;
    fail) fail_count=$((fail_count+1)) ;;
    warn) warn_count=$((warn_count+1)) ;;
  esac
done

echo ""
echo "Pre-flight: $pass_count pass, $warn_count warn, $fail_count fail"
echo "Detailed JSON -> $OUT"

if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
