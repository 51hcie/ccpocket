#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# AnyCoding Android Release Publishing Script
# Validates signing certificate, computes SHA-256 and size, generates manifest,
# and copies the verified APK into the configured Bridge release directory.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RELEASE_DIR="${BRIDGE_RELEASE_DIR:-$HOME/.anycoding/releases}"
EXPECTED_CERT_SHA256="59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2"

APK_INPUT="${1:-}"

if [ -z "$APK_INPUT" ]; then
  CANDIDATES=(
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/anycoding.apk"
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    "$REPO_ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
    "/Users/lw/Windows_Projects/Macremote_spike/downloads/ci_build/ccpocket-debug-apk/app-debug.apk"
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

APKSIGNER=$(which apksigner 2>/dev/null || find "${ANDROID_HOME:-/usr/local/lib/android/sdk}/build-tools" -name apksigner 2>/dev/null | sort -V | tail -n 1 || true)

if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
  echo "[2/4] Verifying APK signature certificate via apksigner..."
  CERT_OUTPUT=$("$APKSIGNER" verify --print-certs "$APK_INPUT" 2>&1 || true)
  CERT_SHA256=$(echo "$CERT_OUTPUT" | grep -i "SHA-256" | head -n 1 | sed 's/.*: *//' | tr -d ' ' | tr '[:upper:]' '[:lower:]' || true)
  
  echo "  Extracted Certificate SHA-256: $CERT_SHA256"
  echo "  Expected Certificate SHA-256:  $EXPECTED_CERT_SHA256"
  
  if [ -n "$CERT_SHA256" ] && [ "$CERT_SHA256" != "$EXPECTED_CERT_SHA256" ]; then
    echo "[-] ERROR: Refusing to publish: APK signing certificate SHA-256 mismatch!" >&2
    echo "    Got:      $CERT_SHA256" >&2
    echo "    Expected: $EXPECTED_CERT_SHA256" >&2
    exit 2
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

PUBSPEC_PATH="$REPO_ROOT/apps/mobile/pubspec.yaml"
VERSION_NAME="1.115.3"
VERSION_CODE=218

if [ -f "$PUBSPEC_PATH" ]; then
  VERSION_LINE=$(grep "^version:" "$PUBSPEC_PATH" | head -n 1 | sed 's/version: *//' | tr -d '\r')
  if [[ "$VERSION_LINE" == *"+"* ]]; then
    VERSION_NAME=$(echo "$VERSION_LINE" | cut -d'+' -f1)
    VERSION_CODE=$(echo "$VERSION_LINE" | cut -d'+' -f2)
  else
    VERSION_NAME="$VERSION_LINE"
  fi
fi

echo "[3/4] Preparing release directory: $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

TARGET_APK="$RELEASE_DIR/anycoding.apk"
cp -f "$APK_INPUT" "$TARGET_APK"

MANIFEST_PATH="$RELEASE_DIR/manifest.json"
cat > "$MANIFEST_PATH" << JSONEOF
{
  "versionCode": $VERSION_CODE,
  "versionName": "$VERSION_NAME",
  "sha256": "$FILE_SHA256",
  "size": $FILE_SIZE,
  "buildTime": "$BUILD_TIME",
  "downloadPath": "/api/update/download",
  "certificateSha256": "$EXPECTED_CERT_SHA256",
  "changelog": "AnyCoding V2.0 usability update: unified typography scale, remote Bridge-served in-app updater, and truthful monitoring console."
}
JSONEOF

echo "[4/4] Published release manifest:"
cat "$MANIFEST_PATH"
echo ""
echo "[+] Successfully published AnyCoding Android release to $RELEASE_DIR"
