#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/dist/Still.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/zh-Hans.lproj" .build/Still.iconset
cp "$binary_dir/Still" "$app/Contents/MacOS/Still"
swift Scripts/make-icon.swift Design
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Design/Still-1024.png --out ".build/Still.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Design/Still-1024.png --out ".build/Still.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/Still.iconset -o "$app/Contents/Resources/Still.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleName</key><string>Still</string>
<key>CFBundleDisplayName</key><string>Still · 留选</string>
<key>CFBundleIdentifier</key><string>app.still.culling</string>
<key>CFBundleExecutable</key><string>Still</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.5</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleIconFile</key><string>Still</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cat > "$app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleDisplayName" = "Still · 留选";
"CFBundleName" = "Still";
STRINGS
codesign --force --sign - "$app"
print "Built: $app"
