#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SUPABASE_URL_VALUE="${SUPABASE_URL:-}"
SUPABASE_KEY_VALUE="${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-}}"

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_KEY_VALUE" ]]; then
  echo "Missing SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY/SUPABASE_ANON_KEY." >&2
  echo "Create .env before packaging so the app can use login and marketplace features." >&2
  exit 1
fi

xml_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

APP_NAME="Wazak"
BUNDLE_ID="${BUNDLE_ID:-com.goyoai.Wazak}"
VERSION="${VERSION:-0.1.0}"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"

swift build -c release

rm -rf "$APP_PATH" "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/Wazak" "$APP_PATH/Contents/MacOS/Wazak"
cp -R "$BUILD_DIR/Wazak_Wazak.bundle" "$APP_PATH/Contents/Resources/Wazak_Wazak.bundle"
cp "Sources/Wazak/Resources/Wazak.icns" "$APP_PATH/Contents/Resources/Wazak.icns"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>CFBundleExecutable</key>
  <string>Wazak</string>
  <key>CFBundleIdentifier</key>
  <string>$(xml_escape "$BUNDLE_ID")</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>Wazak</string>
  <key>CFBundleName</key>
  <string>Wazak</string>
  <key>CFBundleDisplayName</key>
  <string>Wazak</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(xml_escape "$VERSION")</string>
  <key>CFBundleVersion</key>
  <string>$(xml_escape "$VERSION")</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$(xml_escape "$BUNDLE_ID").auth</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>wazak</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SupabaseURL</key>
  <string>$(xml_escape "$SUPABASE_URL_VALUE")</string>
  <key>SupabasePublishableKey</key>
  <string>$(xml_escape "$SUPABASE_KEY_VALUE")</string>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"
else
  codesign --force --deep --sign - "$APP_PATH"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Built $APP_PATH"
echo "Built $ZIP_PATH"
