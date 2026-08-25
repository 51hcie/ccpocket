#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

TEST_APK="${1:-${TEST_APK:-}}"

if [ -z "$TEST_APK" ]; then
  CANDIDATES=(
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/anycoding.apk"
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    "$REPO_ROOT/build_artifacts/anycoding.apk"
  )
  for c in "${CANDIDATES[@]}"; do
    if [ -f "$c" ]; then
      TEST_APK="$c"
      break
    fi
  done
fi

if [ -z "$TEST_APK" ] || [ ! -f "$TEST_APK" ]; then
  echo "[-] ERROR: Test APK fixture not found. Pass APK as argument or set TEST_APK." >&2
  exit 1
fi

AAPT=$(which aapt 2>/dev/null || find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}/build-tools" -name aapt 2>/dev/null | sort -V | tail -n 1 || true)
if [ -z "$AAPT" ] || [ ! -x "$AAPT" ]; then
  echo "[-] ERROR: aapt tool not found for test execution." >&2
  exit 1
fi

BADGING_OUTPUT=$("$AAPT" dump badging "$TEST_APK" 2>/dev/null || true)
PACKAGE_LINE=$(echo "$BADGING_OUTPUT" | grep "^package: " | head -n 1 || true)
EXPECTED_CODE=$(echo "$PACKAGE_LINE" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
EXPECTED_NAME=$(echo "$PACKAGE_LINE" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")

if [ -z "$EXPECTED_CODE" ] || [ -z "$EXPECTED_NAME" ]; then
  echo "[-] ERROR: Failed to extract expected version from $TEST_APK" >&2
  exit 1
fi

echo "=== Test 1: Publish extracts genuine APK binary metadata ==="
export BRIDGE_RELEASE_DIR="$TEST_TEMP_DIR/release1"
bash "$SCRIPT_DIR/publish-android-release.sh" "$TEST_APK"

if [ ! -f "$BRIDGE_RELEASE_DIR/manifest.json" ]; then
  echo "[-] Failed: manifest.json was not created" >&2
  exit 1
fi

MANIFEST_CODE=$(grep '"versionCode":' "$BRIDGE_RELEASE_DIR/manifest.json" | sed 's/[^0-9]//g')
MANIFEST_NAME=$(grep '"versionName":' "$BRIDGE_RELEASE_DIR/manifest.json" | sed 's/.*: *"\([^"]*\)".*/\1/')

if [ "$MANIFEST_CODE" != "$EXPECTED_CODE" ]; then
  echo "[-] Failed: expected extracted versionCode $EXPECTED_CODE, got $MANIFEST_CODE" >&2
  exit 1
fi

if [ "$MANIFEST_NAME" != "$EXPECTED_NAME" ]; then
  echo "[-] Failed: expected extracted versionName $EXPECTED_NAME, got $MANIFEST_NAME" >&2
  exit 1
fi
echo "[+] Test 1 passed: extracted versionCode=$MANIFEST_CODE, versionName=$MANIFEST_NAME"

echo "=== Test 2: Reject mismatched supplied versionCode ==="
MISMATCH_CODE=$((EXPECTED_CODE + 1000))
export BRIDGE_RELEASE_DIR="$TEST_TEMP_DIR/release2"
set +e
bash "$SCRIPT_DIR/publish-android-release.sh" "$TEST_APK" "$MISMATCH_CODE" "$EXPECTED_NAME" > "$TEST_TEMP_DIR/test2.log" 2>&1
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "[-] Failed: publish-android-release.sh succeeded despite versionCode mismatch!" >&2
  exit 1
fi

if ! grep -q "Supplied versionCode ($MISMATCH_CODE) does not match APK binary versionCode ($EXPECTED_CODE)" "$TEST_TEMP_DIR/test2.log"; then
  echo "[-] Failed: expected mismatch error message not found in log" >&2
  cat "$TEST_TEMP_DIR/test2.log"
  exit 1
fi
echo "[+] Test 2 passed: mismatched versionCode ($MISMATCH_CODE) rejected with code $EXIT_CODE"

echo "=== Test 3: Reject mismatched supplied versionName ==="
MISMATCH_NAME="99.99.99"
export BRIDGE_RELEASE_DIR="$TEST_TEMP_DIR/release3"
set +e
bash "$SCRIPT_DIR/publish-android-release.sh" "$TEST_APK" "$EXPECTED_CODE" "$MISMATCH_NAME" > "$TEST_TEMP_DIR/test3.log" 2>&1
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "[-] Failed: publish-android-release.sh succeeded despite versionName mismatch!" >&2
  exit 1
fi

if ! grep -q "Supplied versionName ($MISMATCH_NAME) does not match APK binary versionName ($EXPECTED_NAME)" "$TEST_TEMP_DIR/test3.log"; then
  echo "[-] Failed: expected mismatch error message not found in log" >&2
  cat "$TEST_TEMP_DIR/test3.log"
  exit 1
fi
echo "[+] Test 3 passed: mismatched versionName ($MISMATCH_NAME) rejected with code $EXIT_CODE"

echo "=== Test 4: Verify generated SHA-256 and size match exact APK binary ==="
MANIFEST_SHA=$(grep '"sha256":' "$TEST_TEMP_DIR/release1/manifest.json" | sed 's/.*: *"\([^"]*\)".*/\1/')
if command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA=$(shasum -a 256 "$TEST_APK" | awk '{print $1}')
else
  ACTUAL_SHA=$(sha256sum "$TEST_APK" | awk '{print $1}')
fi

if [ "$MANIFEST_SHA" != "$ACTUAL_SHA" ]; then
  echo "[-] Failed: manifest SHA ($MANIFEST_SHA) does not match actual SHA ($ACTUAL_SHA)" >&2
  exit 1
fi
echo "[+] Test 4 passed: manifest SHA matches actual binary SHA ($ACTUAL_SHA)"

echo ""
echo "=========================================="
echo "ALL PUBLISH SCRIPT INTEGRITY TESTS PASSED!"
echo "=========================================="
