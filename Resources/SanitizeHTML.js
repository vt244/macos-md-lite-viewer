const safeHTMLTags = new Set(`
    a abbr address article aside b bdi bdo blockquote br caption cite code col colgroup dd del
    details dfn div dl dt em figcaption figure footer h1 h2 h3 h4 h5 h6 header hr i img ins kbd
    li mark nav ol p pre q rp rt ruby s samp section small span strong sub summary sup table
    tbody td tfoot th thead time tr u ul var wbr
`.trim().split(/\s+/));
const safeHTMLAttributes = new Set(`
    alt aria-label aria-hidden class colspan data-lang data-value datetime dir height id lang
    open reversed role rowspan scope start title type value width
`.trim().split(/\s+/));

function sanitizeHTML(html, image, link, markdown) {
    const fragment = AsciiDocEngine.parseFragment(html);
    function clean(parent) {
        parent.childNodes = parent.childNodes.flatMap(node => {
            if (node.nodeName === '#text') return [node];
            if (node.namespaceURI !== 'http://www.w3.org/1999/xhtml') return [];
            const tag = node.tagName;
            if (tag === 'input' && markdown &&
                node.attrs.some(attr => attr.name === 'class' && attr.value === 'task-checkbox') &&
                node.attrs.some(attr => attr.name === 'type' && attr.value === 'checkbox')) {
                const checked = node.attrs.some(attr => attr.name === 'checked');
                node.attrs = [
                    { name: 'class', value: 'task-checkbox' },
                    { name: 'type', value: 'checkbox' },
                    { name: 'disabled', value: '' }
                ];
                if (checked) node.attrs.push({ name: 'checked', value: '' });
                return [node];
            }
            if (!safeHTMLTags.has(tag)) return [];
            node.attrs = node.attrs.filter(attr => {
                if (attr.namespace) return false;
                if (tag === 'a' && attr.name === 'href') {
                    attr.value = link(attr.value) || '';
                    return attr.value !== '';
                }
                if (tag === 'a' && attr.name === 'name') return true;
                if (tag === 'img' && attr.name === 'src') {
                    attr.value = image(attr.value) || '';
                    return attr.value !== '';
                }
                if (attr.name === 'style') {
                    // Asciidoctor emits percentage widths for tables and columns.
                    return ['table', 'col', 'colgroup'].includes(tag) &&
                        /^width:\s*\d{1,3}(?:\.\d+)?%;?\s*$/i.test(attr.value);
                }
                if (attr.name === 'data-mermaid') {
                    return markdown && tag === 'pre' && attr.value === '';
                }
                return safeHTMLAttributes.has(attr.name);
            });
            if (tag === 'img' && !node.attrs.some(attr => attr.name === 'src')) {
                const alt = node.attrs.find(attr => attr.name === 'alt');
                return alt ? [{ nodeName: '#text', value: alt.value, parentNode: parent }] : [];
            }
            if (tag === 'a' && !node.attrs.some(attr => attr.name === 'id')) {
                const name = node.attrs.find(attr => attr.name === 'name');
                if (name) node.attrs.push({ name: 'id', value: name.value });
            }
            clean(node);
            if (tag !== 'table' || parent.attrs?.some(attr => attr.name === 'class' &&
                attr.value.split(/\s+/).some(name => name === 'table-wrap' || name === 'admonitionblock'))) {
                return [node];
            }
            const wrapper = {
                nodeName: 'div', tagName: 'div', namespaceURI: node.namespaceURI,
                attrs: [{ name: 'class', value: 'table-wrap' }], childNodes: [node], parentNode: parent
            };
            node.parentNode = wrapper;
            return [wrapper];
        });
    }
    clean(fragment);
    return AsciiDocEngine.serialize(fragment).trim();
}
