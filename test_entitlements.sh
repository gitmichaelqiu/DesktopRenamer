#!/bin/bash
# Test extracting and modifying entitlements
APP_PATH="$(pwd)/build/Release/DesktopRenamer.app"
codesign -d --entitlements :- "$APP_PATH" > temp.entitlements
plutil -remove com.apple.security.application-groups temp.entitlements
cat temp.entitlements
rm temp.entitlements
