#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Still.app/Contents/Info.plist)
archive="Still-v${version}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Still.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256SUMS.txt)
print "Release package: $PWD/dist/$archive"
