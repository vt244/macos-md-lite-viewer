#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

build="$PWD/.build"
app="$build/Markdown Viewer.app"
extension="$app/Contents/PlugIns/MarkdownQuickLook.appex"
mkdir -p "$app/Contents/MacOS" "$extension/Contents/MacOS" "$build/module-cache" "$build/tmp"
export TMPDIR="$build/tmp"

swift_flags=(-O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$build/module-cache")
shared_sources=(Sources/L10n.swift Sources/MarkdownDocument.swift Sources/MarkdownRenderer.swift Sources/PreviewPage.swift)

swiftc "${swift_flags[@]}" "${shared_sources[@]}" Sources/ViewerWindow.swift Sources/main.swift \
    -o "$app/Contents/MacOS/MarkdownViewer"
swiftc "${swift_flags[@]}" "${shared_sources[@]}" Extensions/QuickLook/PreviewProvider.swift \
    -application-extension -parse-as-library -module-name MarkdownQuickLook \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$extension/Contents/MacOS/MarkdownQuickLook"

install_resources() {
    local bundle="$1" info="$2" resources="$1/Contents/Resources"
    mkdir -p "$resources/en.lproj" "$resources/ru.lproj"
    cp "$info" "$bundle/Contents/Info.plist"
    cp Resources/Preview.css "$resources/"
    cp Resources/en.lproj/Localizable.strings "$resources/en.lproj/"
    cp Resources/ru.lproj/Localizable.strings "$resources/ru.lproj/"
    cp LICENSE "$resources/LICENSE.txt"
}

install_resources "$app" Resources/Info.plist
install_resources "$extension" Extensions/QuickLook/Info.plist
cp Resources/RenderMermaid.js Resources/ThirdParty/* "$app/Contents/Resources/"
for asset in RenderMermaid.js mermaid.min.js Mermaid-LICENSES.txt; do
    rm -f "$extension/Contents/Resources/$asset"
done
codesign --force --sign - --entitlements Extensions/QuickLook/Entitlements.plist "$extension"
codesign --force --sign - "$app"
printf '%s\n' "$app"
