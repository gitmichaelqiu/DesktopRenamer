# Bundle-identity bridge release

The bridge is a one-time Sparkle update for installations that still use
`com.michaelqiu.DesktopRenamer`. It stages a separately signed current-ID app,
then lets that app replace the bridge at its original path. Normal
`dev.mqiu.DesktopRenamer` builds do not enter the bridge flow when migration
metadata is empty.

The bridge package is intentionally not produced or published as part of a
normal development build. Run this workflow only after the final current-ID
source is ready:

1. Build and sign the final current-ID app with its new Sparkle feed. The feed
   must not be the legacy appcast, or future updates to the new bundle ID will
   not be discovered.

   ```sh
   xcodebuild \
     -project DesktopRenamer.xcodeproj \
     -scheme DesktopRenamer \
     -configuration Release \
     -archivePath "$CURRENT_ARCHIVE" \
     archive \
     MARKETING_VERSION="$CURRENT_VERSION" \
     CURRENT_PROJECT_VERSION="$CURRENT_BUILD" \
     DESKTOP_RENAMER_UPDATE_FEED_URL="$CURRENT_FEED_URL" \
     DESKTOP_RENAMER_RELEASE_TAG="$RELEASE_TAG"
   ```

2. Build the migration package from the archived current-ID app. `--version`
   is the app build number (`CFBundleVersion`), which must match the package
   version and the bridge's `--migration-package-version`.

   ```sh
   Scripts/build-migration-package.sh \
     --app "$CURRENT_ARCHIVE/Products/Applications/DesktopRenamer.app" \
     --version "$CURRENT_BUILD" \
     --update-feed-url "$CURRENT_FEED_URL" \
     --output "$MIGRATION_PACKAGE" \
     --signing-identity "$DEVELOPER_ID_INSTALLER" \
     --notary-profile "$NOTARY_PROFILE"
   ```

   Upload the package to its final HTTPS URL and calculate its SHA256. The URL
   and checksum are pinned into the bridge at the next step; they are never
   hardcoded in source.

3. Build the legacy bridge DMG with the package URL, checksum, versions, feed,
   and release tag supplied as build-time values.

   ```sh
   MIGRATION_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print $1}')"

   Scripts/build-bridge-release.sh \
     --version "$BRIDGE_VERSION" \
     --build-number "$BRIDGE_BUILD" \
     --release-tag "$RELEASE_TAG" \
     --feed-url "$LEGACY_FEED_URL" \
     --staged-feed-url "$CURRENT_FEED_URL" \
     --migration-package-url "$MIGRATION_PACKAGE_URL" \
     --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
     --migration-package-version "$CURRENT_BUILD" \
     --output-dir "$BRIDGE_OUTPUT_DIRECTORY" \
     --signing-identity "$DEVELOPER_ID_APPLICATION" \
     --notary-profile "$NOTARY_PROFILE"
   ```

   The bridge build uses the `DesktopRenamerBridge` scheme and keeps the
   legacy app and widget bundle identifiers. Its Sparkle appcast item must be
   published to the legacy feed only after verification.

4. Verify both artifacts before publishing the bridge appcast.

   ```sh
   Scripts/verify-bridge-release.sh \
     --bridge-dmg "$BRIDGE_OUTPUT_DIRECTORY/DesktopRenamer-$BRIDGE_VERSION-$RELEASE_TAG.dmg" \
     --migration-package "$MIGRATION_PACKAGE" \
     --version "$BRIDGE_VERSION" \
     --build-number "$BRIDGE_BUILD" \
     --release-tag "$RELEASE_TAG" \
     --feed-url "$LEGACY_FEED_URL" \
     --migration-package-url "$MIGRATION_PACKAGE_URL" \
     --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
     --migration-package-version "$CURRENT_BUILD"
   ```

`build-migration-package.sh` signs with a Developer ID Installer identity and
`build-bridge-release.sh` signs the app with a Developer ID Application
identity. Both submit to `notarytool` through a named keychain profile and
staple the ticket. `--skip-notarization` and
`--skip-notarization-checks` are for local diagnostics only and must not be
used for a release.

The migration copies the legacy defaults domain while leaving Sparkle state in
the old domain, carries launch-at-login state to the current bundle ID, and
removes the old app only after the canonical app acknowledges startup. On a
failed handoff it restores and relaunches the old app. SpaceAPI names and
transport identifiers are deliberately unchanged.

All output paths in the examples are caller-provided. The repository ignores
the default `tmp/` output directory; generated apps, packages, archives,
checksums, credentials, and notarization profiles must not be committed.
