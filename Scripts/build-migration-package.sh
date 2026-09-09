#!/bin/bash
set -euo pipefail

CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.DesktopRenamer"
CURRENT_WIDGET_BUNDLE_IDENTIFIER="dev.mqiu.DesktopRenamer.DesktopRenamerWidget"
STAGED_APPLICATION_NAME="DesktopRenamer-Migration.app"
DEFAULT_PACKAGE_IDENTIFIER="dev.mqiu.DesktopRenamer.migration"

usage() {
    cat <<'EOF'
Usage: build-migration-package.sh --app PATH --version BUILD \
    --update-feed-url URL [options]

Builds the package that stages a current-ID DesktopRenamer app at
/Applications/DesktopRenamer-Migration.app for the legacy bridge handoff.

Required:
  --app PATH                    Final current-ID DesktopRenamer.app
  --version BUILD               CFBundleVersion of the staged app/package
  --update-feed-url URL         Current-ID Sparkle feed embedded in the app

Signing and notarization:
  --signing-identity NAME       Developer ID Installer certificate name
  --notary-profile NAME         notarytool keychain profile
  --skip-notarization           Build and sign without submitting/stapling
  --manual-approval              Build for development signing/manual Gatekeeper approval

Other options:
  --output PATH                 Destination .pkg (default: tmp/migration.pkg)
  --package-identifier ID       Installer package identifier
  -h, --help                    Show this help

The package version is the app build number (CFBundleVersion), not the
marketing version. Credentials are read from the local keychain/profile only.
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

APP_PATH=""
OUTPUT_PATH="tmp/DesktopRenamer-Migration.pkg"
PACKAGE_VERSION=""
UPDATE_FEED_URL=""
PACKAGE_IDENTIFIER="$DEFAULT_PACKAGE_IDENTIFIER"
SIGNING_IDENTITY="${DEVELOPER_ID_INSTALLER:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=0
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --app)
            (($# >= 2)) || die "--app requires a path"
            APP_PATH="$2"
            shift 2
            ;;
        --version)
            (($# >= 2)) || die "--version requires a build number"
            PACKAGE_VERSION="$2"
            shift 2
            ;;
        --update-feed-url)
            (($# >= 2)) || die "--update-feed-url requires a URL"
            UPDATE_FEED_URL="$2"
            shift 2
            ;;
        --output)
            (($# >= 2)) || die "--output requires a path"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --package-identifier)
            (($# >= 2)) || die "--package-identifier requires an identifier"
            PACKAGE_IDENTIFIER="$2"
            shift 2
            ;;
        --signing-identity)
            (($# >= 2)) || die "--signing-identity requires a certificate name"
            SIGNING_IDENTITY="$2"
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

[[ -n "$APP_PATH" ]] || die "--app is required"
[[ -n "$PACKAGE_VERSION" ]] || die "--version is required"
[[ "$PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] \
    || die "package version must contain only numeric dot-separated components"
[[ "$UPDATE_FEED_URL" =~ ^https://[^[:space:]]+$ ]] \
    || die "--update-feed-url must be an HTTPS URL"
[[ "$PACKAGE_IDENTIFIER" =~ ^[A-Za-z0-9.-]+$ ]] \
    || die "package identifier contains unsupported characters"
if ((MANUAL_APPROVAL == 1)); then
    SKIP_NOTARIZATION=1
elif [[ -z "$SIGNING_IDENTITY" ]]; then
    die "a Developer ID Installer identity is required, or use --manual-approval"
fi
if ((SKIP_NOTARIZATION == 0)); then
    [[ -n "$NOTARY_PROFILE" ]] || die "--notary-profile or NOTARY_PROFILE is required"
fi

APP_PATH="$(to_absolute_path "$APP_PATH")"
OUTPUT_PATH="$(to_absolute_path "$OUTPUT_PATH")"
[[ -d "$APP_PATH/Contents" ]] || die "app bundle not found: $APP_PATH"
[[ "${APP_PATH##*.}" == "app" ]] || die "--app must point to an .app bundle"
[[ "${OUTPUT_PATH##*.}" == "pkg" ]] || die "--output must point to a .pkg file"
[[ ! -e "$OUTPUT_PATH" ]] || die "output already exists: $OUTPUT_PATH"

for command_name in codesign ditto mkdir pkgbuild pkgutil shasum; do
    require_command "$command_name"
done
if ((SKIP_NOTARIZATION == 0)); then
    require_command spctl
    require_command xcrun
fi

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || die "app Info.plist not found: $APP_INFO_PLIST"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$CURRENT_BUNDLE_IDENTIFIER" ]] \
    || die "staged app must use bundle identifier $CURRENT_BUNDLE_IDENTIFIER"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$PACKAGE_VERSION" ]] \
    || die "staged app CFBundleVersion does not match --version"
[[ "$(read_plist_value "$APP_INFO_PLIST" SUFeedURL)" == "$UPDATE_FEED_URL" ]] \
    || die "staged app SUFeedURL does not match --update-feed-url"
WIDGET_INFO_PLIST="$APP_PATH/Contents/PlugIns/DesktopRenamerWidgetExtension.appex/Contents/Info.plist"
[[ -f "$WIDGET_INFO_PLIST" ]] || die "staged app widget extension is missing"
[[ "$(read_plist_value "$WIDGET_INFO_PLIST" CFBundleIdentifier)" == "$CURRENT_WIDGET_BUNDLE_IDENTIFIER" ]] \
    || die "staged app widget must use bundle identifier $CURRENT_WIDGET_BUNDLE_IDENTIFIER"

mkdir -p "$(dirname "$OUTPUT_PATH")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/DesktopRenamerMigrationPackage.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PACKAGE_ROOT="$WORK_DIR/root"
mkdir -p "$PACKAGE_ROOT/Applications"
ditto "$APP_PATH" "$PACKAGE_ROOT/Applications/$STAGED_APPLICATION_NAME"

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: staged app signature is not trusted; manual approval is required" >&2
    else
        die "staged app failed strict code-signature verification"
    fi
fi

PACKAGE_BUILD_ARGUMENTS=(
    --root "$PACKAGE_ROOT"
    --identifier "$PACKAGE_IDENTIFIER"
    --version "$PACKAGE_VERSION"
    --install-location /
)
if [[ -n "$SIGNING_IDENTITY" ]]; then
    PACKAGE_BUILD_ARGUMENTS+=(--sign "$SIGNING_IDENTITY")
fi

pkgbuild "${PACKAGE_BUILD_ARGUMENTS[@]}" "$OUTPUT_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    if ! pkgutil --check-signature "$OUTPUT_PATH" >/dev/null 2>&1; then
        if ((MANUAL_APPROVAL == 1)); then
            echo "warning: migration package signature is not trusted; manual approval is required" >&2
        else
            die "pkgbuild output did not pass package signature verification"
        fi
    fi
elif ((MANUAL_APPROVAL == 0)); then
    die "an unsigned package requires --manual-approval"
fi

if ((SKIP_NOTARIZATION == 0)); then
    xcrun notarytool submit "$OUTPUT_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$OUTPUT_PATH"
    xcrun stapler validate -q "$OUTPUT_PATH"
    spctl --assess --type install --verbose=2 "$OUTPUT_PATH"
else
    if ((MANUAL_APPROVAL == 1)); then
        echo "warning: package is intended for manual Gatekeeper approval; notarization was skipped" >&2
    else
        echo "warning: notarization and Gatekeeper assessment were skipped" >&2
    fi
fi

echo "Migration package: $OUTPUT_PATH"
echo "Migration package SHA256: $(shasum -a 256 "$OUTPUT_PATH" | awk '{print tolower($1)}')"
