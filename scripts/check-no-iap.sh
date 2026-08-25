#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Running AnyCoding No-IAP Static Verification ==="

FAILED=0

# 1. Verify pubspec.yaml has no purchases_flutter
if grep -q "purchases_flutter" "$REPO_ROOT/apps/mobile/pubspec.yaml"; then
  echo "[-] ERROR: purchases_flutter found in apps/mobile/pubspec.yaml" >&2
  FAILED=1
else
  echo "[+] apps/mobile/pubspec.yaml: no purchases_flutter dependency"
fi

# 2. Verify AndroidManifest.xml has no BILLING permission
if grep -qi "com.android.vending.BILLING" "$REPO_ROOT/apps/mobile/android/app/src/main/AndroidManifest.xml"; then
  echo "[-] ERROR: com.android.vending.BILLING permission found in AndroidManifest.xml" >&2
  FAILED=1
else
  echo "[+] AndroidManifest.xml: no BILLING permission"
fi

# 3. Verify deleted IAP / supporter files do not exist
DELETED_FILES=(
  "apps/mobile/lib/services/revenuecat_service.dart"
  "apps/mobile/lib/services/support_banner_service.dart"
  "apps/mobile/lib/features/session_list/widgets/support_banner.dart"
  "apps/mobile/lib/features/settings/supporter_screen.dart"
  "apps/mobile/lib/features/settings/widgets/support_section.dart"
  "apps/mobile/lib/widgets/supporter_badge.dart"
  "apps/mobile/test/services/revenuecat_service_test.dart"
  "apps/mobile/test/services/support_banner_service_test.dart"
  "apps/mobile/test/supporter_screen_test.dart"
  "apps/mobile/test/supporter_badge_test.dart"
  "apps/mobile/test/support_section_test.dart"
  "apps/mobile/test/home_content_support_banner_test.dart"
)

for file in "${DELETED_FILES[@]}"; do
  if [ -f "$REPO_ROOT/$file" ]; then
    echo "[-] ERROR: Deleted file still exists: $file" >&2
    FAILED=1
  fi
done
echo "[+] All dead IAP/supporter files verified removed"

# 4. Verify no purchases_flutter, RevenueCat, or PurchasesHybridCommon in lockfiles
for lockfile in "apps/mobile/ios/Podfile.lock" "apps/mobile/macos/Podfile.lock"; do
  if [ -f "$REPO_ROOT/$lockfile" ]; then
    if grep -E -i "purchases_flutter|revenuecat|purchaseshybridcommon" "$REPO_ROOT/$lockfile"; then
      echo "[-] ERROR: Residual IAP entries found in $lockfile" >&2
      FAILED=1
    else
      echo "[+] $lockfile: no residual IAP entries"
    fi
  fi
done

# 5. Verify no purchases_flutter or revenuecat/support_banner_service imports or references in apps/mobile/lib
if grep -rn "purchases_flutter" "$REPO_ROOT/apps/mobile/lib"; then
  echo "[-] ERROR: purchases_flutter import or reference in apps/mobile/lib" >&2
  FAILED=1
else
  echo "[+] apps/mobile/lib: no purchases_flutter references"
fi

if grep -rn -i "revenuecat" "$REPO_ROOT/apps/mobile/lib"; then
  echo "[-] ERROR: revenuecat reference in apps/mobile/lib" >&2
  FAILED=1
else
  echo "[+] apps/mobile/lib: no revenuecat references"
fi

if grep -rn -E "support_banner_service|SupportBannerService" "$REPO_ROOT/apps/mobile/lib"; then
  echo "[-] ERROR: support_banner_service reference in apps/mobile/lib" >&2
  FAILED=1
else
  echo "[+] apps/mobile/lib: no support_banner_service references"
fi

# 6. Verify no purchases_flutter, RevenueCatService, or SupportBannerService residues in apps/mobile/test
if grep -rn "purchases_flutter" "$REPO_ROOT/apps/mobile/test"; then
  echo "[-] ERROR: purchases_flutter found in apps/mobile/test" >&2
  FAILED=1
else
  echo "[+] apps/mobile/test: no purchases_flutter references"
fi

if grep -rn -E "RevenueCatService|revenuecat_service|_FakeRevenueCatService" "$REPO_ROOT/apps/mobile/test"; then
  echo "[-] ERROR: RevenueCatService residue found in apps/mobile/test" >&2
  FAILED=1
else
  echo "[+] apps/mobile/test: no RevenueCatService residues"
fi

if grep -rn -E "SupportBannerService|support_banner_service" "$REPO_ROOT/apps/mobile/test"; then
  echo "[-] ERROR: SupportBannerService residue found in apps/mobile/test" >&2
  FAILED=1
else
  echo "[+] apps/mobile/test: no SupportBannerService residues"
fi

# 7. Verify no REVENUECAT in .github/workflows
if grep -rn "REVENUECAT" "$REPO_ROOT/.github/workflows"; then
  echo "[-] ERROR: REVENUECAT references in .github/workflows" >&2
  FAILED=1
else
  echo "[+] .github/workflows: no REVENUECAT references"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "[-] No-IAP validation FAILED!" >&2
  exit 1
fi

echo "[+] ALL NO-IAP STATIC CHECKS PASSED!"
