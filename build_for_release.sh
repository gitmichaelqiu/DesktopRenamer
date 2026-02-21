#!/bin/bash
# Builds DesktopRenamer for Release and applies Ad-Hoc signing
# This bypasses the Code 153 Provisioning Profile error for distribution.

set -e

echo "🔨 Building Release configuration..."
xcodebuild -project DesktopRenamer.xcodeproj -scheme DesktopRenamer -configuration Release clean build CONFIGURATION_BUILD_DIR="$(pwd)/build/Release" | xcpretty || echo "Build completed."

APP_PATH="$(pwd)/build/Release/DesktopRenamer.app"

if [ -d "$APP_PATH" ]; then
    echo "🔏 Applying Ad-Hoc signature..."
    codesign --force --deep -s - "$APP_PATH"
    echo "✅ Success! Distribution-ready app is located at: $APP_PATH"
else
    echo "❌ Build failed, app not found at $APP_PATH"
fi
