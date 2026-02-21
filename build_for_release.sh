#!/bin/bash
# Applies Ad-Hoc signing
# This bypasses the Code 153 Provisioning Profile error for distribution.

set -e

echo "Drag and drop the built DesktopRenamer.app here and press Enter:"
read -r RAW_PATH

# Clean up the path (remove quotes that terminal drag-and-drop might add, and trim whitespace)
APP_PATH=$(eval echo "$RAW_PATH")

if [ -d "$APP_PATH" ]; then
    echo "🔏 Extracting entitlements..."
    ENTITLEMENTS_FILE="/tmp/DesktopRenamer_temp.entitlements"
    codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_FILE"
    
    echo "🗑️ Removing App Group restrictions for Ad-Hoc distribution..."
    # The app group entitlement forces a Provisioning Profile requirement which fails Ad-Hoc Code 153.
    # We remove this so the app launches, but this sacrifices Widget functionality for downloaded copies.
    plutil -remove com.apple.security.application-groups "$ENTITLEMENTS_FILE" || true
    
    echo "🔏 Applying Ad-Hoc signature with modified entitlements..."
    codesign --force --deep --entitlements "$ENTITLEMENTS_FILE" -s - "$APP_PATH"
    
    rm "$ENTITLEMENTS_FILE"
    echo "✅ Success! Distribution-ready app is located at: $APP_PATH"
else
    echo "❌ App not found at: $APP_PATH"
fi
