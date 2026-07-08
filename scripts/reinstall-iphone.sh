#!/usr/bin/env bash
#
# Rebuild + reinstall Hire Haulage on the iPhone.
#
# Signed with the paid Apple Developer Program team, so each build lasts ~1 year.
# Re-run whenever you want to push a fresh build to the phone.
#
#   ./scripts/reinstall-iphone.sh
#
# The phone can be on the same WiFi network (paired) — no cable needed.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

BUNDLE_ID="com.spudbox.hirehaulage"
TEAM="N8W459SD9Z"                                    # Developer Program team (ade@coleplanet.com signed into Xcode)
HW_UDID="00008110-000808692EBA801E"                 # iPhone hardware id (xcodebuild destination)
DEVICECTL_ID="6ABE3F00-6FAC-5FA0-BA8A-B9EDF02783A8" # iPhone CoreDevice id (devicectl)
DERIVED="$REPO/build/device-dd"

echo "📱 Checking the iPhone is connected…"
if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICECTL_ID"; then
  echo "❌ iPhone not found. Plug it in with a cable, unlock it, tap 'Trust' if asked, then re-run."
  exit 1
fi

echo "🔧 Regenerating the Xcode project…"
xcodegen generate >/dev/null

echo "🔨 Building (Release, signed for your iPhone)…"
xcodebuild -project HHiOS.xcodeproj -scheme HHiOS \
  -configuration Release \
  -destination "platform=iOS,id=$HW_UDID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
  build >/dev/null

APP="$DERIVED/Build/Products/Release-iphoneos/HHiOS.app"

# A copy signed by a different team can't be overwritten (MismatchedApplicationIdentifierEntitlement),
# so clear any old install first. Harmless if it's not installed. Note: this wipes app data (you'll re-login).
echo "🧹 Removing any previous copy…"
xcrun devicectl device uninstall app --device "$DEVICECTL_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "📦 Installing onto the iPhone…"
xcrun devicectl device install app --device "$DEVICECTL_ID" "$APP" >/dev/null

# Best-effort launch (skips silently if the phone is locked — just open it yourself).
xcrun devicectl device process launch --device "$DEVICECTL_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "✅ Done — Hire Haulage refreshed (valid ~1 year on the paid team)."
