function renderAsciiDoc(source, includeRoot, crossReferenceSuffix, include, image, link, finish, fail) {
    // Asciidoctor's browser adapter fetches includes. Only the native reader can supply them.
    globalThis.fetch = async target => {
        const text = include(target);
        return text == null ? { ok: false, status: 404, statusText: 'Not found' } :
            { ok: true, text: async () => text };
    };
    AsciiDocEngine.LoggerManager.setLogger(new AsciiDocEngine.NullLogger());
    AsciiDocEngine.convert(source, {
        safe: 'server',
        backend: 'html5',
        standalone: false,
        base_dir: includeRoot,
        attributes: {
            showtitle: '',
            'allow-uri-read': null,
            'cache-uri': null,
            'data-uri': null,
            'max-include-depth': 16,
            relfilesuffix: '.' + crossReferenceSuffix
        }
    }).then(html => {
        const body = sanitizeHTML(html, image, link, false);
        finish(body ? '<article class="asciidoc">' + body + '</article>' : '');
    }).catch(error => fail(String(error)));
}
