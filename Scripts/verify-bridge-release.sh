#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="com.michaelqiu.DesktopRenamer"
LEGACY_WIDGET_BUNDLE_IDENTIFIER="com.michaelqiu.DesktopRenamer.DesktopRenamerWidget"
CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.DesktopRenamer"
CURRENT_STAGED_APPLICATION_NAME="DesktopRenamer-Migration.app"
DEFAULT_STAGING_PATH="/Applications/$CURRENT_STAGED_APPLICATION_NAME"

usage() {
    cat <<'EOF'
Usage: verify-bridge-release.sh (--bridge-dmg PATH | --bridge-app PATH) \
    --migration-package PATH --version VERSION --build-number BUILD \
    --release-tag TAG --feed-url URL --migration-package-url URL \
    --migration-package-sha256 SHA256 --migration-package-version BUILD [options]

Verifies bundle identities, embedded build-time metadata, code signatures,
Gatekeeper assessment, notarization tickets, and the migration package payload.

Required:
  --bridge-dmg PATH               Bridge DMG
  --bridge-app PATH               Bridge app directory (alternative to DMG)
  --migration-package PATH        Migration .pkg
  --version VERSION               Expected bridge marketing version
  --build-number BUILD            Expected bridge CFBundleVersion
  --release-tag TAG               Expected bridge release tag
  --feed-url URL                  Expected shared Sparkle appcast URL
  --migration-package-url URL     Expected package URL in bridge metadata
  --migration-package-sha256 SHA256
                                  Expected package checksum in bridge metadata
  --migration-package-version BUILD
                                  Expected staged app/package build number

Other options:
  --staging-path PATH             Expected package staging path
  --manual-approval               Allow development/unsigned artifacts for manual Gatekeeper approval
  --skip-notarization-checks      Skip stapler ticket checks (local diagnostics)
  -h, --help                     Show this help

Production verification should omit --skip-notarization-checks and
--manual-approval.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

to_absolute_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

is_https_url() {
    [[ "$1" =~ ^https://[^[:space:]]+$ ]]
}

normalize_sha256() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

assert_equal() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    [[ "$actual" == "$expected" ]] \
        || die "$label mismatch (expected '$expected', got '$actual')"
}

BRIDGE_DMG=""
BRIDGE_APP_INPUT=""
MIGRATION_PACKAGE=""
MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
MIGRATION_PACKAGE_URL=""
MIGRATION_PACKAGE_SHA256=""
MIGRATION_PACKAGE_VERSION=""
STAGING_PATH="$DEFAULT_STAGING_PATH"
SKIP_NOTARIZATION_CHECKS=0
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --bridge-dmg)
            (($# >= 2)) || die "--bridge-dmg requires a path"
            BRIDGE_DMG="$2"
            shift 2
            ;;
        --bridge-app)
            (($# >= 2)) || die "--bridge-app requires a path"
            BRIDGE_APP_INPUT="$2"
            shift 2
            ;;
        --migration-package)
            (($# >= 2)) || die "--migration-package requires a path"
            MIGRATION_PACKAGE="$2"
            shift 2
            ;;
        --version)
            (($# >= 2)) || die "--version requires a value"
            MARKETING_VERSION="$2"
            shift 2
            ;;
        --build-number)
            (($# >= 2)) || die "--build-number requires a value"
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --release-tag)
            (($# >= 2)) || die "--release-tag requires a value"
            RELEASE_TAG="$2"
            shift 2
            ;;
        --feed-url)
            (($# >= 2)) || die "--feed-url requires a URL"
            FEED_URL="$2"
            shift 2
            ;;
        --migration-package-url)
            (($# >= 2)) || die "--migration-package-url requires a URL"
            MIGRATION_PACKAGE_URL="$2"
            shift 2
            ;;
        --migration-package-sha256)
            (($# >= 2)) || die "--migration-package-sha256 requires a checksum"
            MIGRATION_PACKAGE_SHA256="$2"
            shift 2
            ;;
        --migration-package-version)
            (($# >= 2)) || die "--migration-package-version requires a build number"
            MIGRATION_PACKAGE_VERSION="$2"
            shift 2
            ;;
        --staging-path)
            (($# >= 2)) || die "--staging-path requires a path"
            STAGING_PATH="$2"
            shift 2
            ;;
        --skip-notarization-checks)
            SKIP_NOTARIZATION_CHECKS=1
            shift
            ;;
        --manual-approval)
            MANUAL_APPROVAL=1
            SKIP_NOTARIZATION_CHECKS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$BRIDGE_DMG" || -n "$BRIDGE_APP_INPUT" ]] \
    || die "one of --bridge-dmg or --bridge-app is required"
[[ -z "$BRIDGE_DMG" || -z "$BRIDGE_APP_INPUT" ]] \
    || die "--bridge-dmg and --bridge-app are mutually exclusive"
[[ -n "$MIGRATION_PACKAGE" ]] || die "--migration-package is required"
[[ -n "$MARKETING_VERSION" ]] || die "--version is required"
[[ "$MARKETING_VERSION" =~ ^[0-9]+([.][0-9]+){1,3}$ ]] \
    || die "--version must contain numeric dot-separated components"
[[ -n "$BUILD_NUMBER" ]] || die "--build-number is required"
[[ "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] \
    || die "--build-number must contain numeric dot-separated components"
[[ -n "$MIGRATION_PACKAGE_VERSION" ]] || die "--migration-package-version is required"
[[ "$MIGRATION_PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] \
    || die "--migration-package-version must contain numeric dot-separated components"
[[ -n "$RELEASE_TAG" ]] || die "--release-tag is required"
[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "release tag contains unsupported characters"
is_https_url "$FEED_URL" || die "--feed-url must be an HTTPS URL"
is_https_url "$MIGRATION_PACKAGE_URL" \
    || die "--migration-package-url must be an HTTPS URL"
[[ "$MIGRATION_PACKAGE_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] \
    || die "--migration-package-sha256 must be a 64-character hexadecimal digest"
MIGRATION_PACKAGE_SHA256="$(normalize_sha256 "$MIGRATION_PACKAGE_SHA256")"
[[ "$STAGING_PATH" == /* && "$STAGING_PATH" == *.app ]] \
    || die "--staging-path must be an absolute .app path"

if [[ -n "$BRIDGE_DMG" ]]; then
    BRIDGE_DMG="$(to_absolute_path "$BRIDGE_DMG")"
    [[ -f "$BRIDGE_DMG" ]] || die "bridge DMG not found: $BRIDGE_DMG"
fi
if [[ -n "$BRIDGE_APP_INPUT" ]]; then
    BRIDGE_APP_INPUT="$(to_absolute_path "$BRIDGE_APP_INPUT")"
    [[ -d "$BRIDGE_APP_INPUT/Contents" ]] \
        || die "bridge app not found: $BRIDGE_APP_INPUT"
fi
MIGRATION_PACKAGE="$(to_absolute_path "$MIGRATION_PACKAGE")"
[[ -f "$MIGRATION_PACKAGE" ]] || die "migration package not found: $MIGRATION_PACKAGE"

for command_name in codesign ditto hdiutil mkdir pkgutil rm shasum; do
    require_command "$command_name"
done
if ((SKIP_NOTARIZATION_CHECKS == 0)); then
    require_command spctl
    require_command xcrun
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/DesktopRenamerBridgeVerification.XXXXXX")"
MOUNT_POINT="$WORK_DIR/mount"
mkdir -p "$MOUNT_POINT"
DMG_ATTACHED=0
cleanup() {
    if ((DMG_ATTACHED == 1)); then
        hdiutil detach -quiet "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ -n "$BRIDGE_DMG" ]]; then
    if ((SKIP_NOTARIZATION_CHECKS == 0)); then
        xcrun stapler validate -q "$BRIDGE_DMG"
    fi
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$BRIDGE_DMG" >/dev/null
    DMG_ATTACHED=1
    BRIDGE_APP="$MOUNT_POINT/DesktopRenamer.app"
else
    BRIDGE_APP="$BRIDGE_APP_INPUT"
fi

[[ -d "$BRIDGE_APP/Contents" ]] || die "DesktopRenamer.app not found in bridge artifact"
BRIDGE_INFO_PLIST="$BRIDGE_APP/Contents/Info.plist"
assert_equal "bridge bundle identifier" "$LEGACY_BUNDLE_IDENTIFIER" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" CFBundleIdentifier)"
assert_equal "bridge marketing version" "$MARKETING_VERSION" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" CFBundleShortVersionString)"
assert_equal "bridge build number" "$BUILD_NUMBER" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" CFBundleVersion)"
assert_equal "bridge feed URL" "$FEED_URL" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" SUFeedURL)"
assert_equal "bridge migration package URL" "$MIGRATION_PACKAGE_URL" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerMigrationPackageURL)"
assert_equal "bridge migration package checksum" "$MIGRATION_PACKAGE_SHA256" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerMigrationPackageSHA256)"
assert_equal "bridge migration package version" "$MIGRATION_PACKAGE_VERSION" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerMigrationPackageVersion)"
assert_equal "bridge manual approval mode" "$MANUAL_APPROVAL" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerMigrationAllowManualApproval)"
assert_equal "bridge staging path" "$STAGING_PATH" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerMigrationStagingPath)"
assert_equal "bridge release tag" "$RELEASE_TAG" \
    "$(read_plist_value "$BRIDGE_INFO_PLIST" DesktopRenamerReleaseTag)"

WIDGET_APP="$BRIDGE_APP/Contents/PlugIns/DesktopRenamerWidgetExtension.appex"
WIDGET_INFO_PLIST="$WIDGET_APP/Contents/Info.plist"
[[ -f "$WIDGET_INFO_PLIST" ]] || die "bridge widget extension is missing"
assert_equal "bridge widget bundle identifier" "$LEGACY_WIDGET_BUNDLE_IDENTIFIER" \
    "$(read_plist_value "$WIDGET_INFO_PLIST" CFBundleIdentifier)"

if ! codesign --verify --deep --strict "$BRIDGE_APP" >/dev/null 2>&1; then
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: bridge app signature is not trusted; manual approval is required" >&2
    else
        die "bridge app failed strict code-signature verification"
    fi
fi
if ((SKIP_NOTARIZATION_CHECKS == 0)); then
    spctl --assess --type execute --verbose=2 "$BRIDGE_APP"
fi

if ! pkgutil --check-signature "$MIGRATION_PACKAGE" >/dev/null 2>&1; then
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: migration package is not trusted; manual approval is required" >&2
    else
        die "migration package failed package signature verification"
    fi
fi
if ((SKIP_NOTARIZATION_CHECKS == 0)); then
    xcrun stapler validate -q "$MIGRATION_PACKAGE"
    spctl --assess --type install --verbose=2 "$MIGRATION_PACKAGE"
fi

ACTUAL_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print tolower($1)}')"
assert_equal "migration package SHA256" "$MIGRATION_PACKAGE_SHA256" "$ACTUAL_PACKAGE_SHA256"

EXPANDED_PACKAGE="$WORK_DIR/expanded-package"
pkgutil --expand-full "$MIGRATION_PACKAGE" "$EXPANDED_PACKAGE" >/dev/null
STAGED_APP="$EXPANDED_PACKAGE/Payload/Applications/$CURRENT_STAGED_APPLICATION_NAME"
STAGED_INFO_PLIST="$STAGED_APP/Contents/Info.plist"
[[ -f "$STAGED_INFO_PLIST" ]] || die "migration package does not stage the expected app"
assert_equal "staged app bundle identifier" "$CURRENT_BUNDLE_IDENTIFIER" \
    "$(read_plist_value "$STAGED_INFO_PLIST" CFBundleIdentifier)"
assert_equal "staged app build number" "$MIGRATION_PACKAGE_VERSION" \
    "$(read_plist_value "$STAGED_INFO_PLIST" CFBundleVersion)"
assert_equal "staged app feed URL" "$FEED_URL" \
    "$(read_plist_value "$STAGED_INFO_PLIST" SUFeedURL)"
STAGED_WIDGET_INFO_PLIST="$STAGED_APP/Contents/PlugIns/DesktopRenamerWidgetExtension.appex/Contents/Info.plist"
[[ -f "$STAGED_WIDGET_INFO_PLIST" ]] || die "migration package widget extension is missing"
assert_equal "staged widget bundle identifier" \
    "dev.mqiu.DesktopRenamer.DesktopRenamerWidget" \
    "$(read_plist_value "$STAGED_WIDGET_INFO_PLIST" CFBundleIdentifier)"
if ! codesign --verify --deep --strict "$STAGED_APP" >/dev/null 2>&1; then
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: staged app signature is not trusted; manual approval is required" >&2
    else
        die "staged app failed strict code-signature verification"
    fi
fi

echo "Bridge release verification passed"
echo "Bridge artifact: ${BRIDGE_DMG:-$BRIDGE_APP_INPUT}"
echo "Migration package: $MIGRATION_PACKAGE"
echo "Migration package SHA256: $ACTUAL_PACKAGE_SHA256"
