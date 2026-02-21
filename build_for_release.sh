#!/bin/bash
# Applies Ad-Hoc signing
# This bypasses the Code 153 Provisioning Profile error for distribution.

set -e

echo "Drag and drop the built DesktopRenamer.app here and press Enter:"
read -r RAW_PATH

# Clean up the path (remove quotes that terminal drag-and-drop might add, and trim whitespace)
APP_PATH=$(eval echo "$RAW_PATH")

if [ -d "$APP_PATH" ]; then
    # 1. Sign the Widget Extension first
    WIDGET_PATH="$APP_PATH/Contents/PlugIns/DesktopNameWidgetExtension.appex"
    if [ -d "$WIDGET_PATH" ]; then
        echo "🔏 Extracting Widget entitlements..."
        WIDGET_ENT="/tmp/widget_temp.entitlements"
        codesign -d --entitlements :- --xml "$WIDGET_PATH" > "$WIDGET_ENT" 2>/dev/null
        
        echo "🗑️ Removing strict Provisioning Profile..."
        rm -f "$WIDGET_PATH/Contents/embedded.provisionprofile"
        
        echo "🗑️ Removing App Group and Restricted Identifiers for Ad-Hoc distribution..."
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$WIDGET_ENT" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$WIDGET_ENT" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$WIDGET_ENT" 2>/dev/null || true
        
        echo "🔏 Ad-Hoc signing Widget..."
        codesign --force --entitlements "$WIDGET_ENT" -s - "$WIDGET_PATH"
        rm "$WIDGET_ENT"
    fi

    # 2. Sign the Main App
    echo "🔏 Extracting Main App entitlements..."
    APP_ENT="/tmp/app_temp.entitlements"
    codesign -d --entitlements :- --xml "$APP_PATH" > "$APP_ENT" 2>/dev/null
    
    echo "🗑️ Removing strict Provisioning Profile..."
    rm -f "$APP_PATH/Contents/embedded.provisionprofile"
    
    echo "🗑️ Removing App Group and Restricted Identifiers for Ad-Hoc distribution..."
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$APP_ENT" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$APP_ENT" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$APP_ENT" 2>/dev/null || true
    
    echo "🔏 Ad-Hoc signing Main App..."
    codesign --force --entitlements "$APP_ENT" -s - "$APP_PATH"
    
    rm "$APP_ENT"
    echo "✅ Success! Distribution-ready app is located at: $APP_PATH"
else
    echo "❌ App not found at: $APP_PATH"
fi
