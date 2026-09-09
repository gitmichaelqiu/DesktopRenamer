# Bundle-identity bridge release tooling

The bridge is a one-time Sparkle update for installations that still use
`com.michaelqiu.DesktopRenamer`. It stages a current-ID app, then lets that
app replace the bridge at its original path. Normal
`dev.mqiu.DesktopRenamer` builds do not enter the bridge flow when migration
metadata is empty.

The legacy bridge and the current app intentionally use the same appcast URL:

```text
https://raw.githubusercontent.com/gitmichaelqiu/DesktopRenamer/main/appcast.xml
```

The appcast separates them with Sparkle channels and a custom target element:

```xml
<rss xmlns:desktoprenamer="https://mqiu.dev/desktoprenamer/appcast">
  <item>
    <desktoprenamer:targetBundleIdentifier>com.michaelqiu.DesktopRenamer</desktoprenamer:targetBundleIdentifier>
    <!-- No sparkle:channel: visible to the legacy default channel. -->
  </item>
  <item>
    <sparkle:channel>dev-mqiu</sparkle:channel>
    <desktoprenamer:targetBundleIdentifier>dev.mqiu.DesktopRenamer</desktoprenamer:targetBundleIdentifier>
  </item>
</rss>
```

The legacy bridge remains on the default channel so older installations can
find it. Current-ID builds opt into `dev-mqiu` and select only items tagged
for their bundle identifier. Every future current-ID item must include both
the channel and target element.

## Signing modes

The scripts support two distribution modes:

- `--manual-approval`: uses the existing development-signing workflow, skips
  notarization, keeps the package checksum requirement, and permits users to
  approve the package manually in Installer/Gatekeeper. This is the mode used
  for the current DesktopRenamer release.
- Developer ID mode: pass the required signing identities and notary profile
  and omit `--manual-approval`.

Sparkle’s Ed25519 signature and the package SHA-256 remain required for the
bridge release. The scripts never read or write private keys in the
repository.

## 1. Build the migration package

Use the current-ID app built from the final source. The package version is the
app build number (`CFBundleVersion`), not the marketing version.

```sh
CURRENT_APP="tmp/DesktopRenamer 2026-09-09 10-19-25/DesktopRenamer.app"
MIGRATION_PACKAGE="tmp/DesktopRenamer-migration-38.pkg"
APPCAST_URL="https://raw.githubusercontent.com/gitmichaelqiu/DesktopRenamer/main/appcast.xml"

Scripts/build-migration-package.sh \
  --app "$CURRENT_APP" \
  --version 38 \
  --update-feed-url "$APPCAST_URL" \
  --output "$MIGRATION_PACKAGE" \
  --manual-approval
```

Record the printed SHA-256 checksum. Upload the package to its final HTTPS
URL before building the bridge. The URL and checksum are pinned into the
bridge at the next step.

## 2. Build the legacy bridge

The bridge build uses the `DesktopRenamerBridge` scheme and the `Bridge`
configuration. It retains the legacy application and widget bundle
identifiers.

```sh
MIGRATION_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print $1}')"
MIGRATION_PACKAGE_URL="https://github.com/gitmichaelqiu/DesktopRenamer/releases/download/v1.14.0-bridge/DesktopRenamer-migration-38.pkg"
BRIDGE_OUTPUT_DIRECTORY="tmp/DesktopRenamer-bridge-release"

Scripts/build-bridge-release.sh \
  --version 1.14.0 \
  --build-number 39 \
  --release-tag bridge \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version 38 \
  --output-dir "$BRIDGE_OUTPUT_DIRECTORY" \
  --manual-approval
```

Choose the final GitHub Release asset URL before publishing. If the package
URL or checksum changes, rebuild the bridge so its embedded metadata remains
consistent.

## 3. Verify both artifacts

```sh
Scripts/verify-bridge-release.sh \
  --bridge-dmg "$BRIDGE_OUTPUT_DIRECTORY/DesktopRenamer-1.14.0-bridge.dmg" \
  --migration-package "$MIGRATION_PACKAGE" \
  --version 1.14.0 \
  --build-number 39 \
  --release-tag bridge \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version 38 \
  --manual-approval
```

The verifier checks both bundle identities, widget identifiers, shared feed
URL, migration metadata, package contents, and checksum. It allows the
development/unsigned signatures expected by manual approval but still fails
on metadata or payload mismatches.

Do not commit generated apps, packages, DMGs, archives, checksums, signing
credentials, or notarization profiles.
