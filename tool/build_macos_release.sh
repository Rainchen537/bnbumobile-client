#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

codesign_identity="${MACOS_CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
  echo "MACOS_CODESIGN_IDENTITY is required for a signed macOS release." >&2
  exit 2
fi

python3 tool/check_apple_identity.py --platform macos --configuration Release

release_identity_config="$repository_root/macos/Flutter/Signing.release.local.xcconfig"
if [[ ! -f "$release_identity_config" ]]; then
  echo "Missing ignored macOS release identity configuration." >&2
  exit 2
fi
if ! git check-ignore -q "$release_identity_config"; then
  echo "The macOS release identity configuration must remain ignored by Git." >&2
  exit 2
fi

read_release_setting() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" \
    "$release_identity_config" | tail -n 1
}

identity_configured="$(read_release_setting BNBU_APPLE_IDENTITY_CONFIGURED)"
macos_bundle_identifier="$(
  read_release_setting BNBU_MACOS_APP_BUNDLE_IDENTIFIER
)"
macos_app_group_identifier="$(
  read_release_setting BNBU_MACOS_APP_GROUP_IDENTIFIER
)"
macos_team_identifier="$(
  read_release_setting BNBU_MACOS_TEAM_IDENTIFIER
)"
if [[ "$identity_configured" != "YES" || \
      -z "$macos_bundle_identifier" || \
      "$macos_bundle_identifier" == invalid.local.* || \
      ! "$macos_team_identifier" =~ ^[A-Z0-9]{10}$ || \
      -z "$macos_app_group_identifier" || \
      "$macos_app_group_identifier" != "$macos_team_identifier".* ]]; then
  echo "The macOS release identity configuration is incomplete." >&2
  exit 2
fi

secure_storage_service="${MACOS_RELEASE_SECURE_STORAGE_ACCOUNT:-$macos_bundle_identifier}"
flutter build macos --release \
  --dart-define="MACOS_RELEASE_SECURE_STORAGE_ACCOUNT=$secure_storage_service" \
  "$@"

application="$repository_root/build/macos/Build/Products/Release/BNBU.ME.app"
desktop_updater_helper_root="$repository_root/macos/Flutter/ephemeral/.symlinks/plugins/desktop_updater/macos/install_helper"
desktop_updater_helper_script="$desktop_updater_helper_root/embed_install_helper.sh"
desktop_updater_helper_policy="${MACOS_DESKTOP_UPDATER_POLICY:-$repository_root/macos/Runner/DesktopUpdaterHelperPolicy.local.json}"
if [[ "$desktop_updater_helper_policy" != /* ]]; then
  desktop_updater_helper_policy="$repository_root/$desktop_updater_helper_policy"
fi
desktop_updater_helper_policy_sha256="$(
  perl -0pe 's/\r?\n\z//' "$desktop_updater_helper_policy" | \
    shasum -a 256 | awk '{print $1}'
)"
desktop_updater_derived_root="$repository_root/build/macos/desktop_updater-helper"
entitlements="${MACOS_MAIN_ENTITLEMENTS:-macos/Runner/Release.entitlements}"
if [[ "$entitlements" != /* ]]; then
  entitlements="$repository_root/$entitlements"
fi
if [[ ! -f "$entitlements" ]]; then
  echo "Missing macOS main-app entitlements: $entitlements" >&2
  exit 2
fi
widget_entitlements_template="$repository_root/macos/Runner/Widget.entitlements"
if [[ ! -d "$application" ]]; then
  echo "Missing macOS release application: $application" >&2
  exit 2
fi
# Finder/resource-fork metadata can be copied into generated extension bundles
# and makes strict Developer ID signing fail. It is never part of the app.
/usr/bin/xattr -cr "$application"
if [[ ! -x "$desktop_updater_helper_script" ]]; then
  echo "Missing desktop updater helper packaging script." >&2
  exit 2
fi
if [[ ! -f "$desktop_updater_helper_policy" ]]; then
  echo "Missing ignored desktop updater helper policy." >&2
  exit 2
fi
if [[ "$desktop_updater_helper_policy" == "$repository_root"/* ]] && \
   ! git check-ignore -q "$desktop_updater_helper_policy"; then
  echo "The desktop updater helper policy must remain ignored by Git." >&2
  exit 2
fi
policy_application_id="$(
  plutil -extract applicationPackageId raw -o - \
    "$desktop_updater_helper_policy"
)"
if [[ "$policy_application_id" != "$macos_bundle_identifier" ]]; then
  echo "The desktop updater policy does not match the release app identity." >&2
  exit 2
fi

render_entitlements() {
  local source="$1"
  local destination="$2"
  cp "$source" "$destination"
  /usr/libexec/PlistBuddy \
    -c "Set :com.apple.security.application-groups:0 $macos_app_group_identifier" \
    "$destination" >/dev/null
}

resolved_entitlements_root="$repository_root/build/macos/resolved-entitlements"
mkdir -p "$resolved_entitlements_root"
resolved_main_entitlements="$resolved_entitlements_root/Main.entitlements"
resolved_widget_entitlements="$resolved_entitlements_root/Widget.entitlements"
render_entitlements "$entitlements" "$resolved_main_entitlements"
render_entitlements \
  "$widget_entitlements_template" \
  "$resolved_widget_entitlements"

mkdir -p "$desktop_updater_derived_root"
TARGET_BUILD_DIR="$(dirname "$application")" \
CONTENTS_FOLDER_PATH="$(basename "$application")/Contents" \
DERIVED_FILE_DIR="$desktop_updater_derived_root" \
ARCHS="arm64 x86_64" \
EXPANDED_CODE_SIGN_IDENTITY="$codesign_identity" \
CODE_SIGN_IDENTITY="$codesign_identity" \
DESKTOP_UPDATER_HELPER_INFO_TEMPLATE="$desktop_updater_helper_root/Configuration/Helper-Info.plist" \
DESKTOP_UPDATER_SEALED_POLICY_PATH="$desktop_updater_helper_policy" \
DESKTOP_UPDATER_SEALED_POLICY_SHA256="$desktop_updater_helper_policy_sha256" \
"$desktop_updater_helper_script"

codesign_with_retry() {
  local attempt
  local target
  target="${@: -1}"
  for attempt in 1 2 3; do
    /usr/bin/xattr -cr "$target"
    if codesign "$@"; then
      return 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
      /bin/sleep 2
    fi
  done
  return 1
}

sign_nested_code() {
  local item="$1"
  codesign_with_retry \
    --force \
    --sign "$codesign_identity" \
    --timestamp \
    --options runtime \
    "$item"
}

frameworks="$application/Contents/Frameworks"
if [[ -d "$frameworks" ]]; then
  while IFS= read -r -d '' item; do
    sign_nested_code "$item"
  done < <(find "$frameworks" -type d -name '*.framework' -print0)

  while IFS= read -r -d '' item; do
    sign_nested_code "$item"
  done < <(find "$frameworks" -type f -name '*.dylib' ! -path '*.framework/*' -print0)
fi

while IFS= read -r -d '' item; do
  if [[ "$item" == *.appex ]]; then
    codesign_with_retry \
      --force \
      --sign "$codesign_identity" \
      --timestamp \
      --options runtime \
      --entitlements "$resolved_widget_entitlements" \
      "$item"
  else
    sign_nested_code "$item"
  fi
done < <(
  find "$application/Contents" -depth -type d \
    \( -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) \
    -print0
)

codesign_with_retry \
  --force \
  --sign "$codesign_identity" \
  --timestamp \
  --options runtime \
  --entitlements "$resolved_main_entitlements" \
  "$application"

verify_signed_application() {
  local attempt
  for attempt in 1 2 3; do
    /usr/bin/xattr -cr "$application"
    if codesign --verify --deep --strict --verbose=2 "$application"; then
      return 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
      /bin/sleep 2
    fi
  done
  return 1
}

verify_signed_application
expected_application_requirement="$(
  plutil -extract allowedApplicationSigner.value raw -o - \
    "$desktop_updater_helper_policy"
)"
actual_application_requirement="$(
  codesign -d -r- "$application" 2>&1 | sed -n 's/^designated => //p'
)"
if [[ "$actual_application_requirement" != "$expected_application_requirement" ]]; then
  echo "macOS application designated requirement does not match updater policy." >&2
  exit 2
fi
helper="$application/Contents/Helpers/DesktopUpdaterInstallHelper"
widget="$application/Contents/PlugIns/BnbuWidgets.appex"
read_signed_team_identifier() {
  local item="$1"
  codesign -dv --verbose=4 "$item" 2>&1 | \
    sed -n 's/^TeamIdentifier=//p' | tail -n 1
}
actual_application_team="$(read_signed_team_identifier "$application")"
actual_widget_team="$(read_signed_team_identifier "$widget")"
actual_helper_team="$(read_signed_team_identifier "$helper")"
if [[ "$actual_application_team" != "$macos_team_identifier" || \
      "$actual_widget_team" != "$macos_team_identifier" || \
      "$actual_helper_team" != "$macos_team_identifier" ]]; then
  echo "Signed macOS code does not match the configured Team." >&2
  exit 2
fi
expected_helper_requirement="$(
  plutil -extract allowedHelperSigner.value raw -o - \
    "$desktop_updater_helper_policy"
)"
actual_helper_requirement="$(
  codesign -d -r- "$helper" 2>&1 | sed -n 's/^designated => //p'
)"
if [[ "$actual_helper_requirement" != "$expected_helper_requirement" ]]; then
  echo "macOS updater helper designated requirement does not match policy." >&2
  exit 2
fi
