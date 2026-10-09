#!/usr/bin/env bash
# Builds LinkrunnerKit and runs its unit tests on the first available iPhone simulator.
# The package only targets iOS, so `swift test` on a Mac host does not work.
#
#   Scripts/test.sh          # build and run the tests
#   Scripts/test.sh build    # build the package and tests without running them
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION="${1:-test}"
case "$ACTION" in
    test) XCODE_ACTION=test ;;
    build) XCODE_ACTION=build-for-testing ;;
    *) echo "usage: $0 [test|build]" >&2; exit 2 ;;
esac

# Xcode generates "LinkrunnerKit-Package" (all targets and tests) when a package has more than
# one product; fall back to the product scheme otherwise.
if xcodebuild -list 2>/dev/null | grep -q "LinkrunnerKit-Package"; then
    SCHEME="LinkrunnerKit-Package"
else
    SCHEME="LinkrunnerKit"
fi

SIM_ID="$(xcrun simctl list devices available iPhone | grep -m1 -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"
if [ -z "$SIM_ID" ]; then
    echo "No available iPhone simulator found (xcrun simctl list devices available)" >&2
    exit 1
fi

echo "Running xcodebuild $XCODE_ACTION, scheme $SCHEME, simulator $SIM_ID"
xcodebuild "$XCODE_ACTION" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" \
    -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    | tail -n 80
