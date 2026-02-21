#!/bin/bash
# Applies Ad-Hoc signing
# This bypasses the Code 153 Provisioning Profile error for distribution.

set -e

echo "Drag and drop the built DesktopRenamer.app here and press Enter:"
read -r RAW_PATH

# Clean up the path (remove quotes that terminal drag-and-drop might add, and trim whitespace)
APP_PATH=$(eval echo "$RAW_PATH")

if [ -d "$APP_PATH" ]; then
    echo "🔏 Applying Ad-Hoc signature..."
    codesign --force --deep -s - "$APP_PATH"
    echo "✅ Success! Distribution-ready app is located at: $APP_PATH"
else
    echo "❌ App not found at: $APP_PATH"
fi
