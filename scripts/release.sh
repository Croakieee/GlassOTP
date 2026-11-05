#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
profile="${NOTARY_PROFILE:-GlassOTP}"
team="B3V8PCM3YP"
out="$root/build/release"
archive="$out/GlassOTP.xcarchive"
exported="$out/export"
app="$exported/GlassOTP.app"
zip="$out/GlassOTP.zip"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "No notarytool profile \"$profile\". Create it once:"
  echo "  xcrun notarytool store-credentials $profile --apple-id <apple id> --team-id $team"
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

xcodebuild -project "$root/GlassOTP.xcodeproj" -scheme GlassOTP -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$archive" \
  -allowProvisioningUpdates archive

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$team</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$archive" -exportPath "$exported" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates

codesign --verify --strict --deep "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q "get-task-allow" && { echo "get-task-allow is set"; exit 1; }

ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait | tee "$out/notary.log"
grep -q "status: Accepted" "$out/notary.log" || { echo "Notarization failed"; exit 1; }

xcrun stapler staple "$app"
spctl -a -t exec -vv "$app"

mkdir -p "$out/stage/GlassOTP"
ditto "$app" "$out/stage/GlassOTP/GlassOTP.app"
ditto -c -k --keepParent "$out/stage/GlassOTP" "$zip"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
echo
echo "GlassOTP $version"
echo "$zip"
echo "sha256 $(shasum -a 256 "$zip" | awk '{print $1}')"
