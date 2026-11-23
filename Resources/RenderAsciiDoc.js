const asciiDocTags = new Set(`
    a abbr article aside b blockquote br caption cite code col colgroup dd del details div dl dt em
    figcaption figure footer h1 h2 h3 h4 h5 h6 header hr i img kbd li mark nav ol p pre q s samp
    section small span strong sub summary sup table tbody td tfoot th thead tr u ul var wbr
`.trim().split(/\s+/));
const asciiDocAttributes = new Set(`
    alt aria-label aria-hidden class colspan data-lang data-value height id lang open reversed
    role rowspan scope start title type value width
`.trim().split(/\s+/));

function cleanAsciiDoc(parent, image, link) {
    parent.childNodes = parent.childNodes.filter(node => {
        if (node.nodeName === '#text') return true;
        if (node.namespaceURI !== 'http://www.w3.org/1999/xhtml' || !asciiDocTags.has(node.tagName)) {
            return false;
        }
        node.attrs = node.attrs.filter(attr => {
            if (attr.namespace) return false;
            if (attr.name === 'href' && node.tagName === 'a') {
                attr.value = link(attr.value) || '';
                return attr.value !== '';
            }
            if (attr.name === 'src' && node.tagName === 'img') {
                attr.value = image(attr.value) || '';
                return attr.value !== '';
            }
            if (attr.name === 'style') {
                // Asciidoctor uses inline widths for tables and their columns.
                return /^(?:width:\s*\d{1,3}(?:\.\d+)?%;?\s*)$/i.test(attr.value);
            }
            return asciiDocAttributes.has(attr.name);
        });
        if (node.tagName === 'img' && !node.attrs.some(attr => attr.name === 'src')) {
            const alt = node.attrs.find(attr => attr.name === 'alt');
            node.tagName = node.nodeName = 'span';
            node.childNodes = alt ? [{ nodeName: '#text', value: alt.value, parentNode: node }] : [];
        }
        cleanAsciiDoc(node, image, link);
        return true;
    });
    parent.childNodes = parent.childNodes.map(node => {
        if (node.tagName !== 'table' || node.parentNode?.attrs?.some(attr =>
            attr.name === 'class' && attr.value.split(/\s+/).includes('admonitionblock'))) {
            return node;
        }
        const wrapper = {
            nodeName: 'div', tagName: 'div', namespaceURI: node.namespaceURI,
            attrs: [{ name: 'class', value: 'table-wrap' }], childNodes: [node], parentNode: parent
        };
        node.parentNode = wrapper;
        return wrapper;
    });
}

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
        const fragment = AsciiDocEngine.parseFragment(html);
        cleanAsciiDoc(fragment, image, link);
        const body = AsciiDocEngine.serialize(fragment).trim();
        finish(body ? '<article class="asciidoc">' + body + '</article>' : '');
    }).catch(error => fail(String(error)));
}
