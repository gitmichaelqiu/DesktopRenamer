#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="com.michaelqiu.DesktopRenamer"
LEGACY_WIDGET_BUNDLE_IDENTIFIER="com.michaelqiu.DesktopRenamer.DesktopRenamerWidget"
DEFAULT_STAGING_PATH="/Applications/DesktopRenamer-Migration.app"
DEFAULT_OUTPUT_DIRECTORY="tmp/DesktopRenamer-bridge-release"

usage() {
    cat <<'EOF'
Usage: build-bridge-release.sh --version VERSION --build-number BUILD \
    --release-tag TAG --feed-url URL --migration-package-url URL \
    --migration-package-sha256 SHA256 [options]

Builds the legacy-bundle-ID bridge release as a DMG. The bridge and current
application use the same Sparkle appcast; after installation the bridge
downloads the migration package and hands off to the current bundle ID.

Required:
  --version VERSION             Marketing version for the bridge app
  --build-number BUILD          CFBundleVersion for the bridge app
  --release-tag TAG             Release tag used in metadata and artifact name
  --feed-url URL                 Shared Sparkle appcast URL
  --migration-package-url URL    HTTPS URL for the migration package
  --migration-package-sha256 SHA256
                                 SHA256 pinned by the bridge

Signing and notarization:
  --signing-identity NAME        Developer ID Application certificate name
  --team-id ID                   Apple Developer Team ID (optional)
  --notary-profile NAME          notarytool keychain profile
  --skip-notarization             Build and sign without submitting/stapling
  --manual-approval               Build with automatic development signing and skip notarization

Other options:
  --migration-package-version BUILD
                                 Staged app/package CFBundleVersion (required)
  --staging-path PATH             Installer staging app path
  --output-dir PATH               Release output directory
  -h, --help                      Show this help

All release values are supplied at build time. Credentials are read from the
local keychain/profile only and are never written to the repository.
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

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_PATH="$SCRIPT_DIRECTORY/../DesktopRenamer.xcodeproj"
MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
MIGRATION_PACKAGE_URL=""
MIGRATION_PACKAGE_SHA256=""
MIGRATION_PACKAGE_VERSION=""
STAGING_PATH="$DEFAULT_STAGING_PATH"
OUTPUT_DIRECTORY="$DEFAULT_OUTPUT_DIRECTORY"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
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
        --output-dir)
            (($# >= 2)) || die "--output-dir requires a path"
            OUTPUT_DIRECTORY="$2"
            shift 2
            ;;
        --signing-identity)
            (($# >= 2)) || die "--signing-identity requires a certificate name"
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --team-id)
            (($# >= 2)) || die "--team-id requires an identifier"
            TEAM_ID="$2"
            shift 2
            ;;
        --notary-profile)
            (($# >= 2)) || die "--notary-profile requires a keychain profile"
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=1
            shift
            ;;
        --manual-approval)
            MANUAL_APPROVAL=1
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
if ((MANUAL_APPROVAL == 1)); then
    SKIP_NOTARIZATION=1
elif [[ -z "$SIGNING_IDENTITY" ]]; then
    die "a Developer ID Application identity is required, or use --manual-approval"
fi
if ((SKIP_NOTARIZATION == 0)); then
    [[ -n "$NOTARY_PROFILE" ]] || die "--notary-profile or NOTARY_PROFILE is required"
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
OUTPUT_DIRECTORY="$(to_absolute_path "$OUTPUT_DIRECTORY")"
[[ -d "$PROJECT_PATH" ]] || die "Xcode project not found: $PROJECT_PATH"

for command_name in codesign ditto hdiutil mkdir shasum xcodebuild; do
    require_command "$command_name"
done
if ((SKIP_NOTARIZATION == 0)); then
    require_command spctl
    require_command xcrun
fi

mkdir -p "$OUTPUT_DIRECTORY"
BRIDGE_APP_PATH="$OUTPUT_DIRECTORY/DesktopRenamer.app"
DMG_PATH="$OUTPUT_DIRECTORY/DesktopRenamer-$MARKETING_VERSION-$RELEASE_TAG.dmg"
[[ ! -e "$BRIDGE_APP_PATH" ]] || die "output app already exists: $BRIDGE_APP_PATH"
[[ ! -e "$DMG_PATH" ]] || die "output disk image already exists: $DMG_PATH"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/DesktopRenamerBridgeRelease.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARCHIVE_PATH="$WORK_DIR/DesktopRenamerBridge.xcarchive"
DERIVED_DATA_PATH="$WORK_DIR/DerivedData"
BUILD_SETTINGS=(
    "MARKETING_VERSION=$MARKETING_VERSION"
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
    "DESKTOP_RENAMER_UPDATE_FEED_URL=$FEED_URL"
    "DESKTOP_RENAMER_MIGRATION_PACKAGE_URL=$MIGRATION_PACKAGE_URL"
    "DESKTOP_RENAMER_MIGRATION_PACKAGE_SHA256=$MIGRATION_PACKAGE_SHA256"
    "DESKTOP_RENAMER_MIGRATION_PACKAGE_VERSION=$MIGRATION_PACKAGE_VERSION"
    "DESKTOP_RENAMER_MIGRATION_ALLOW_MANUAL_APPROVAL=$MANUAL_APPROVAL"
    "DESKTOP_RENAMER_MIGRATION_STAGING_PATH=$STAGING_PATH"
    "DESKTOP_RENAMER_RELEASE_TAG=$RELEASE_TAG"
)
if ((MANUAL_APPROVAL == 0)); then
    BUILD_SETTINGS+=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY"
    )
else
    BUILD_SETTINGS+=("CODE_SIGN_STYLE=Automatic")
fi
if [[ -n "$TEAM_ID" ]]; then
    BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$TEAM_ID")
fi

xcodebuild -quiet \
    -project "$PROJECT_PATH" \
    -scheme DesktopRenamerBridge \
    -configuration Bridge \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    "${BUILD_SETTINGS[@]}"

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/DesktopRenamer.app"
[[ -d "$ARCHIVED_APP_PATH/Contents" ]] \
    || die "Xcode archive did not contain DesktopRenamer.app"
ditto "$ARCHIVED_APP_PATH" "$BRIDGE_APP_PATH"

APP_INFO_PLIST="$BRIDGE_APP_PATH/Contents/Info.plist"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$LEGACY_BUNDLE_IDENTIFIER" ]] \
    || die "bridge app has the wrong bundle identifier"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleShortVersionString)" == "$MARKETING_VERSION" ]] \
    || die "bridge app marketing version does not match --version"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$BUILD_NUMBER" ]] \
    || die "bridge app build number does not match --build-number"
[[ "$(read_plist_value "$APP_INFO_PLIST" SUFeedURL)" == "$FEED_URL" ]] \
    || die "bridge app feed URL does not match --feed-url"
[[ "$(read_plist_value "$APP_INFO_PLIST" DesktopRenamerMigrationPackageURL)" == "$MIGRATION_PACKAGE_URL" ]] \
    || die "bridge app migration package URL does not match the build input"
[[ "$(read_plist_value "$APP_INFO_PLIST" DesktopRenamerMigrationPackageSHA256)" == "$MIGRATION_PACKAGE_SHA256" ]] \
    || die "bridge app migration package checksum does not match the build input"
[[ "$(read_plist_value "$APP_INFO_PLIST" DesktopRenamerMigrationPackageVersion)" == "$MIGRATION_PACKAGE_VERSION" ]] \
    || die "bridge app migration package version does not match the build input"
[[ "$(read_plist_value "$APP_INFO_PLIST" DesktopRenamerMigrationStagingPath)" == "$STAGING_PATH" ]] \
    || die "bridge app staging path does not match the build input"
[[ "$(read_plist_value "$APP_INFO_PLIST" DesktopRenamerReleaseTag)" == "$RELEASE_TAG" ]] \
    || die "bridge app release tag does not match the build input"

WIDGET_INFO_PLIST="$BRIDGE_APP_PATH/Contents/PlugIns/DesktopRenamerWidgetExtension.appex/Contents/Info.plist"
[[ -f "$WIDGET_INFO_PLIST" ]] || die "bridge archive did not contain its widget extension"
[[ "$(read_plist_value "$WIDGET_INFO_PLIST" CFBundleIdentifier)" == "$LEGACY_WIDGET_BUNDLE_IDENTIFIER" ]] \
    || die "bridge widget has the wrong bundle identifier"

if ! codesign --verify --deep --strict "$BRIDGE_APP_PATH" >/dev/null 2>&1; then
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: bridge app signature is not trusted; manual approval is required" >&2
    else
        die "bridge app failed strict code-signature verification"
    fi
fi

hdiutil create \
    -volname DesktopRenamer \
    -srcfolder "$BRIDGE_APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if ((SKIP_NOTARIZATION == 0)); then
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate -q "$DMG_PATH"
    spctl --assess --type open --verbose=2 "$DMG_PATH"
else
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: bridge is intended for manual Gatekeeper approval; notarization was skipped" >&2
    else
        echo "warning: notarization and Gatekeeper assessment were skipped" >&2
    fi
fi

echo "Bridge app: $BRIDGE_APP_PATH"
echo "Bridge DMG: $DMG_PATH"
echo "Bridge DMG SHA256: $(shasum -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
