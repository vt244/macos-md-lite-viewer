#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build="$PWD/.build"
app="$build/Markdown Viewer.app"
mkdir -p "$app/Contents/MacOS" "$build/module-cache" "$build/tmp"
export TMPDIR="$build/tmp"

swift_flags=(-O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$build/module-cache")
shared_sources=(Sources/MarkdownDocument.swift Sources/MarkdownRenderer.swift Sources/PreviewPage.swift)

swiftc "${swift_flags[@]}" "${shared_sources[@]}" Sources/ViewerWindow.swift Sources/main.swift \
    -o "$app/Contents/MacOS/MarkdownViewer"
install_resources() {
    local bundle="$1" info="$2" resources="$1/Contents/Resources"
    mkdir -p "$resources"
    cp "$info" "$bundle/Contents/Info.plist"
    cp Resources/Preview.css "$resources/"
    cp LICENSE "$resources/LICENSE.txt"
}

install_resources "$app" Resources/Info.plist
codesign --force --sign - "$app"
printf '%s\n' "$app"
