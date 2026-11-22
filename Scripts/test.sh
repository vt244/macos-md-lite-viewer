#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build="$PWD/.build"
mkdir -p "$build/module-cache" "$build/tmp"
export TMPDIR="$build/tmp"
fixtures="$(mktemp -d "$TMPDIR/markdown-tests.XXXXXX")"
trap 'rm -rf "$fixtures"' EXIT

swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$build/module-cache" \
    Sources/L10n.swift Sources/MarkdownRenderer.swift Sources/MarkdownDocument.swift \
    Extensions/QuickLook/QuickLookDiagram.swift Tests/MarkdownTests.swift \
    -o "$build/MarkdownTests"
"$build/MarkdownTests" "$fixtures"

plutil -lint Extensions/QuickLook/Info.plist Extensions/QuickLook/Entitlements.plist Resources/Info.plist Resources/en.lproj/Localizable.strings Resources/ru.lproj/Localizable.strings
