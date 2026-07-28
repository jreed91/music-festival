#!/bin/sh
#
# Xcode Cloud runs this from the repository root right after cloning, before it looks
# for the Xcode project. Hinterland.xcodeproj is generated from project.yml rather than
# committed, so without this step the build fails with
#
#   Project Hinterland.xcodeproj does not exist at the root of the repository
#
# XcodeGen isn't on the Xcode Cloud image and there's no Homebrew either, so grab the
# prebuilt release binary. It's a Swift package bundle; the Swift runtime it needs is
# already there as part of Xcode.
set -eu

XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.43.0}"
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
TOOLS="$REPO/.ci-tools"

cd "$REPO"

if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN=xcodegen
else
    mkdir -p "$TOOLS"
    pinned="https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    latest="https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip"

    echo "Downloading XcodeGen $XCODEGEN_VERSION"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$TOOLS/xcodegen.zip" "$pinned"; then
        echo "XcodeGen $XCODEGEN_VERSION unavailable, falling back to the latest release"
        curl -fsSL --retry 3 --retry-delay 2 -o "$TOOLS/xcodegen.zip" "$latest"
    fi

    unzip -oq "$TOOLS/xcodegen.zip" -d "$TOOLS"
    XCODEGEN="$TOOLS/xcodegen/bin/xcodegen"
    chmod +x "$XCODEGEN"
fi

"$XCODEGEN" generate --spec project.yml --project .

# Fail loudly here rather than letting Xcode Cloud report the confusing missing-project
# error a step later.
if [ ! -d "$REPO/Hinterland.xcodeproj" ]; then
    echo "xcodegen finished but Hinterland.xcodeproj is missing" >&2
    exit 1
fi

echo "Generated Hinterland.xcodeproj"
