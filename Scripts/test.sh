#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Some standalone Command Line Tools releases omit TestingMacros auto-discovery.
swiftc_path=$(xcrun --find swiftc)
plugin="${swiftc_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$plugin"
else
  swift test
fi
