(async () => {
    const renderer = globalThis.mermaid;
    if (!renderer) return;

    const dark = matchMedia("(prefers-color-scheme: dark)").matches;
    renderer.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        suppressErrorRendering: true,
        htmlLabels: false,
        theme: dark ? "dark" : "neutral",
        fontFamily: "system-ui, sans-serif",
        maxTextSize: 40000,
        maxEdges: 250,
        secure: [
            "secure", "securityLevel", "startOnLoad", "suppressErrorRendering",
            "maxTextSize", "maxEdges", "dompurifyConfig", "htmlLabels"
        ]
    });

    const blocks = Array.from(document.querySelectorAll("main pre[data-mermaid]")).slice(0, 30);
    for (const [index, block] of blocks.entries()) {
        const code = block.querySelector("code");
        if (!code) continue;

        // Skip diagram-supplied configuration. The source remains visible as a code block.
        const source = code.textContent.trim();
        if (source.startsWith("---") || /%%\s*\{/.test(source)) continue;

        const diagram = document.createElement("div");
        diagram.className = "diagram";
        try {
            const { svg } = await renderer.render(`markdown-diagram-${index}`, source);
            diagram.innerHTML = svg;
            block.replaceWith(diagram);
        } catch {
            // Keep the original source if Mermaid cannot render it.
        }
    }
})();
