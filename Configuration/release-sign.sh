#!/bin/bash
set -euo pipefail
release_app="${1:?Usage: release-sign.sh app_path}"
release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_entitlements="$(mktemp -t arswidget-entitlements)"
trap 'rm -f "$release_entitlements"' EXIT
python3 - "$release_root/ArsWidget/ArsWidget.entitlements" "$release_app/Contents/Info.plist" "$release_entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[2], 'rb') as f:
    bundle_id = plistlib.load(f)['CFBundleIdentifier']
with open(sys.argv[1]) as f:
    entitlements = f.read().replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle_id)
with open(sys.argv[3], 'w') as f:
    f.write(entitlements)
PY
# No hardened runtime for ad hoc signing: embedded frameworks have no Team ID.
xattr -cr "$release_app"
codesign --force --deep --sign - "$release_app"
codesign --force --sign - --entitlements "$release_root/ArsWidgetXPCHelper/ArsWidgetXPCHelper.entitlements" "$release_app/Contents/XPCServices/ArsWidgetXPCHelper.xpc"
codesign --force --sign - --entitlements "$release_root/tools/clipboard-reader/ClipboardReader.entitlements" "$release_app/Contents/MacOS/ArsWidgetClipboardReader"
codesign --force --sign - --entitlements "$release_entitlements" "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
