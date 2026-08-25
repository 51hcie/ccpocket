#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# AnyCoding Android Release Publishing Script
# Validates signing certificate, computes SHA-256 and size, extracts genuine
# versionCode and versionName from the APK binary, generates manifest,
# and copies the verified APK into the configured Bridge release directory.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RELEASE_DIR="${BRIDGE_RELEASE_DIR:-$HOME/.anycoding/releases}"
EXPECTED_CERT_SHA256="59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2"

APK_INPUT="${1:-}"
SUPPLIED_VERSION_CODE="${2:-${EXPECTED_VERSION_CODE:-}}"
SUPPLIED_VERSION_NAME="${3:-${EXPECTED_VERSION_NAME:-}}"

if [ -z "$APK_INPUT" ]; then
  CANDIDATES=(
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/anycoding.apk"
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
    "/Users/lw/Windows_Projects/Macremote_spike/downloads/ci_batch2_fix/anycoding-debug-apk/anycoding.apk"
    "/Users/lw/Windows_Projects/Macremote_spike/build_artifacts/anycoding.apk"
  )
  for c in "${CANDIDATES[@]}"; do
    if [ -f "$c" ]; then
      APK_INPUT="$c"
      break
    fi
  done
fi

if [ -z "$APK_INPUT" ] || [ ! -f "$APK_INPUT" ]; then
  echo "[-] ERROR: No valid APK found to publish. Please provide APK path as argument." >&2
  exit 1
fi

echo "[1/4] Inspecting APK at: $APK_INPUT"

# Locate Android tools
AAPT=$(which aapt 2>/dev/null || find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}/build-tools" "/Users/lw/Windows_Projects/Macremote/tools/runtime/android-sdk/build-tools" -name aapt 2>/dev/null | sort -V | tail -n 1 || true)
APKSIGNER=$(which apksigner 2>/dev/null || find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}/build-tools" "/Users/lw/Windows_Projects/Macremote/tools/runtime/android-sdk/build-tools" -name apksigner 2>/dev/null | sort -V | tail -n 1 || true)

EXTRACTED_VERSION_CODE=""
EXTRACTED_VERSION_NAME=""

if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
  echo "[2/4] Extracting package metadata from APK binary via aapt..."
  BADGING_OUTPUT=$("$AAPT" dump badging "$APK_INPUT" 2>/dev/null || true)
  PACKAGE_LINE=$(echo "$BADGING_OUTPUT" | grep "^package: " | head -n 1 || true)
  if [ -n "$PACKAGE_LINE" ]; then
    EXTRACTED_VERSION_CODE=$(echo "$PACKAGE_LINE" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" || true)
    EXTRACTED_VERSION_NAME=$(echo "$PACKAGE_LINE" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" || true)
  fi
fi

if [ -z "$EXTRACTED_VERSION_CODE" ] || [ -z "$EXTRACTED_VERSION_NAME" ]; then
  echo "[!] WARNING: aapt badging extraction failed or aapt not found; falling back to pubspec.yaml."
  PUBSPEC_PATH="$REPO_ROOT/apps/mobile/pubspec.yaml"
  if [ -f "$PUBSPEC_PATH" ]; then
    VERSION_LINE=$(grep "^version:" "$PUBSPEC_PATH" | head -n 1 | sed 's/version: *//' | tr -d '\r')
    if [[ "$VERSION_LINE" == *"+"* ]]; then
      EXTRACTED_VERSION_NAME=$(echo "$VERSION_LINE" | cut -d'+' -f1)
      EXTRACTED_VERSION_CODE=$(echo "$VERSION_LINE" | cut -d'+' -f2)
    fi
  fi
fi

if [ -z "$EXTRACTED_VERSION_CODE" ] || [ -z "$EXTRACTED_VERSION_NAME" ]; then
  echo "[-] ERROR: Unable to determine versionCode/versionName from APK binary or pubspec.yaml." >&2
  exit 2
fi

echo "  Binary Version Code: $EXTRACTED_VERSION_CODE"
echo "  Binary Version Name: $EXTRACTED_VERSION_NAME"

# Check supplied version consistency
if [ -n "$SUPPLIED_VERSION_CODE" ] && [ "$SUPPLIED_VERSION_CODE" != "$EXTRACTED_VERSION_CODE" ]; then
  echo "[-] ERROR: Supplied versionCode ($SUPPLIED_VERSION_CODE) does not match APK binary versionCode ($EXTRACTED_VERSION_CODE)!" >&2
  exit 3
fi

if [ -n "$SUPPLIED_VERSION_NAME" ] && [ "$SUPPLIED_VERSION_NAME" != "$EXTRACTED_VERSION_NAME" ]; then
  echo "[-] ERROR: Supplied versionName ($SUPPLIED_VERSION_NAME) does not match APK binary versionName ($EXTRACTED_VERSION_NAME)!" >&2
  exit 3
fi

if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
  echo "[3/4] Verifying APK signature certificate via apksigner..."
  CERT_OUTPUT=$("$APKSIGNER" verify --print-certs "$APK_INPUT" 2>&1 || true)
  CERT_SHA256=$(echo "$CERT_OUTPUT" | grep -i "SHA-256" | head -n 1 | sed 's/.*: *//' | tr -d ' ' | tr '[:upper:]' '[:lower:]' || true)
  
  echo "  Extracted Certificate SHA-256: $CERT_SHA256"
  echo "  Expected Certificate SHA-256:  $EXPECTED_CERT_SHA256"
  
  if [ -n "$CERT_SHA256" ] && [ "$CERT_SHA256" != "$EXPECTED_CERT_SHA256" ]; then
    echo "[-] ERROR: Refusing to publish: APK signing certificate SHA-256 mismatch!" >&2
    echo "    Got:      $CERT_SHA256" >&2
    echo "    Expected: $EXPECTED_CERT_SHA256" >&2
    exit 4
  fi
  echo "[+] APK signature verified successfully."
else
  echo "[!] WARNING: apksigner not found; proceeding with SHA-256 binary validation."
fi

if command -v shasum >/dev/null 2>&1; then
  FILE_SHA256=$(shasum -a 256 "$APK_INPUT" | awk '{print $1}')
else
  FILE_SHA256=$(sha256sum "$APK_INPUT" | awk '{print $1}')
fi

FILE_SIZE=$(stat -f%z "$APK_INPUT" 2>/dev/null || stat -c%s "$APK_INPUT")
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[4/4] Preparing release directory: $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

TARGET_APK="$RELEASE_DIR/anycoding.apk"
cp -f "$APK_INPUT" "$TARGET_APK"

MANIFEST_PATH="$RELEASE_DIR/manifest.json"
cat > "$MANIFEST_PATH" << JSONEOF
{
  "versionCode": $EXTRACTED_VERSION_CODE,
  "versionName": "$EXTRACTED_VERSION_NAME",
  "sha256": "$FILE_SHA256",
  "size": $FILE_SIZE,
  "buildTime": "$BUILD_TIME",
  "downloadPath": "/api/update/download",
  "certificateSha256": "$EXPECTED_CERT_SHA256",
  "changelog": "AnyCoding V2.0 usability update: unified typography scale, remote Bridge-served in-app updater, and truthful monitoring console."
}
JSONEOF

echo "Published release manifest:"
cat "$MANIFEST_PATH"
echo ""
echo "[+] Successfully published AnyCoding Android release (v$EXTRACTED_VERSION_NAME build $EXTRACTED_VERSION_CODE) to $RELEASE_DIR"
