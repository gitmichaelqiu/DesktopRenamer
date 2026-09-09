# Bundle-identity migration

This migration moves an existing installation from the legacy bundle
identifiers to the current identifiers without requiring the user to install
the application manually:

| Component | Legacy identifier | Current identifier |
| --- | --- | --- |
| Application | `com.michaelqiu.DesktopRenamer` | `dev.mqiu.DesktopRenamer` |
| Widget | `com.michaelqiu.DesktopRenamer.DesktopRenamerWidget` | `dev.mqiu.DesktopRenamer.DesktopRenamerWidget` |

The migration is implemented as a one-time legacy bridge. Normal builds using
`dev.mqiu.DesktopRenamer` do not enter the bridge flow.

## Runtime flow

1. Sparkle delivers a signed legacy bridge update through the shared appcast.
   The bridge item stays on Sparkle's default channel and is tagged for
   `com.michaelqiu.DesktopRenamer`; current-ID items use the `dev-mqiu`
   channel and are tagged for `dev.mqiu.DesktopRenamer`.
2. The bridge starts and shows a one-time migration prompt. Choosing **Later**
   continues to launch the legacy application normally.
3. Choosing **Migrate Now** records a manifest containing the original app
   path, process ID, launch-at-login state, target version, and staging path.
4. The bridge copies the legacy defaults domain into the current defaults
   domain, excluding Sparkle-owned keys. Sparkle state stays in the legacy
   domain until the bridge has completed.
5. The bridge downloads the migration package over HTTPS and verifies its
   SHA-256 checksum. Developer ID builds also require package signature and
   Gatekeeper verification; manual-approval builds leave that final approval
   to the user and Installer.
6. The package installer stages the current-ID app at
   `/Applications/DesktopRenamer-Migration.app`.
7. The staged app starts with the migration manifest arguments, waits for the
   legacy process to terminate, and replaces the old app at its original path.
   The old app is first moved to a temporary backup so the operation can be
   rolled back.
8. The current-ID app starts from the original path and acknowledges startup.
   Only after that acknowledgement does the finalizer remove the staged app,
   backup, migration package, legacy login item, legacy defaults domain, and
   migration manifest.

If any handoff step fails, the finalizer preserves or restores the legacy app,
relaunches it when possible, and exits after displaying an error. The old app
is never removed before the current app has started successfully.

## Producing a release

Do this only after the final current-ID source is ready. The release tooling
keeps package URL, checksum, versions, the appcast URL, staging path, and release
tag as build-time inputs; do not hardcode release values in source.

The complete command reference is also available in
[`Scripts/README.md`](../../../../Scripts/README.md).

### Prerequisites

- A final current-ID `DesktopRenamer.app` archive.
- A final HTTPS URL where the migration package will be hosted.
- The shared Sparkle appcast URL.

For the current DesktopRenamer distribution, use `--manual-approval` with the
release scripts. This keeps the existing development-signing/manual-Gatekeeper
workflow and does not require a paid Developer ID certificate. For a stronger
distribution, omit that flag and provide Developer ID Application and
Developer ID Installer certificates plus a configured `notarytool` keychain
profile.

Signing credentials and notarization profiles must remain in the local
keychain. Do not put them, generated archives, packages, DMGs, or checksums in
the repository.

### 1. Build the migration package

Set the paths and shared appcast URL for the final current-ID app:

```sh
CURRENT_APP="tmp/DesktopRenamer 2026-09-09 10-19-25/DesktopRenamer.app"
CURRENT_BUILD=38
MIGRATION_PACKAGE="tmp/DesktopRenamer-migration-${CURRENT_BUILD}.pkg"
APPCAST_URL="https://raw.githubusercontent.com/gitmichaelqiu/DesktopRenamer/main/appcast.xml"
```

Build a package containing the current-ID app:

```sh
Scripts/build-migration-package.sh \
  --app "$CURRENT_APP" \
  --version "$CURRENT_BUILD" \
  --update-feed-url "$APPCAST_URL" \
  --output "$MIGRATION_PACKAGE" \
  --manual-approval
```

`--version` is the app build number (`CFBundleVersion`), not the marketing
version. The script verifies the app and widget identifiers, verifies the
shared Sparkle feed, creates the `.pkg`, and prints the SHA-256 checksum.
With Developer ID mode, it also signs, notarizes, and staples the package.

Upload the resulting package to its final HTTPS URL before building the
bridge. The URL and checksum must remain stable after the bridge is released.

### 2. Build the legacy bridge

Build the legacy bridge DMG with the package metadata supplied explicitly:

```sh
MIGRATION_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print $1}')"

Scripts/build-bridge-release.sh \
  --version "$BRIDGE_VERSION" \
  --build-number "$BRIDGE_BUILD" \
  --release-tag "$RELEASE_TAG" \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version "$CURRENT_BUILD" \
  --output-dir "$BRIDGE_OUTPUT_DIRECTORY" \
  --manual-approval
```

This uses the `DesktopRenamerBridge` scheme and the `Bridge` configuration.
The resulting app retains the legacy application and widget identifiers so
Sparkle can update existing installations.

### 3. Verify before publishing

Verify the bridge DMG and migration package together:

```sh
Scripts/verify-bridge-release.sh \
  --bridge-dmg "$BRIDGE_OUTPUT_DIRECTORY/DesktopRenamer-$BRIDGE_VERSION-$RELEASE_TAG.dmg" \
  --migration-package "$MIGRATION_PACKAGE" \
  --version "$BRIDGE_VERSION" \
  --build-number "$BRIDGE_BUILD" \
  --release-tag "$RELEASE_TAG" \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version "$CURRENT_BUILD" \
  --manual-approval
```

The verifier checks bundle identifiers, embedded metadata, signatures,
notarization tickets when applicable, package contents, shared-feed metadata,
and the package checksum. Publish the bridge item in the shared appcast only
after this verification succeeds. Keep the bridge item on the default channel
and tag it for the legacy bundle identifier; keep future current-ID items on
`dev-mqiu` and tag them for the current bundle identifier.

`--manual-approval` is the intended mode for the current distribution.
`--skip-notarization` and `--skip-notarization-checks` are lower-level local
diagnostic options and should not replace the explicit mode choice.

## Diagnostics and recovery

The bridge stores temporary state in:

- Manifest: `~/Library/Application Support/DesktopRenamer/Migration/manifest.json`
- Download cache: `~/Library/Caches/DesktopRenamer/Migration/`
- Installer staging app: `/Applications/DesktopRenamer-Migration.app`

The migration finalizer is started internally with
`--desktoprenamer-migration` and an optional
`--desktoprenamer-migration-manifest` argument. These arguments are not a
general-purpose launch interface and should not be added to normal login-item
or user launch configurations.

SpaceAPI compatibility is intentionally unchanged by this migration.
