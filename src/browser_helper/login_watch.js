// Installed before the official page's scripts in Browser login only.
// Records how Krunker's page logs in (method, address and the NAMES of the
// fields it sends), so SR Client can log in the same way natively. Values -
// usernames, passwords, codes, tokens - are never read into the record.
(() => {
    if (window !== window.top || location.origin !== 'https://krunker.io' || window.__srLoginWatch) return;
    const seen = window.__srLoginWatch = [];
    const name = key => String(key).replace(/[^A-Za-z0-9_]/g, '').slice(0, 40);
    const shape = (value, depth) => {
        if (depth > 3) return '...';
        if (Array.isArray(value)) return '[' + (value.length ? shape(value[0], depth + 1) : '') + ']';
        if (value && typeof value === 'object') {
            return '{' + Object.keys(value).slice(0, 24).map(key => {
                const child = value[key];
                return name(key) + (child && typeof child === 'object' ? ':' + shape(child, depth + 1) : ':' + typeof child);
            }).join(',') + '}';
        }
        return typeof value;
    };
    const interesting = url => /(^|\.)(krunker\.io|frvr\.com)$/.test(url.hostname) &&
        (url.hostname === 'gapi.svc.krunker.io' || /(login|auth|account|sign|token|session|user|legacy|migrat|register|seek-game)/i.test(url.pathname));
    // Strings seen in those responses and in socket addresses, kept only in the
    // page to NAME where a token came from (value -> "where"); never recorded.
    const origins = new Map();
    const remember = (where, value, depth) => {
        if (depth > 4 || origins.size > 4000) return;
        if (typeof value === 'string') { if (value.length >= 16 && !origins.has(value)) origins.set(value, where); return; }
        if (Array.isArray(value)) { value.slice(0, 8).forEach((child, k) => remember(`${where}[${k}]`, child, depth + 1)); return; }
        if (value && typeof value === 'object') for (const key of Object.keys(value).slice(0, 40)) remember(`${where}.${name(key)}`, value[key], depth + 1);
    };
    const recordResponse = (url, status, text) => {
        try {
            const value = JSON.parse(text);
            record(`RESP ${status} ${url.origin}${url.pathname} json${shape(value, 0)}`);
            if (/(login|auth|account|sign|token|session|user|refresh|seek-game)/i.test(url.pathname)) remember(`RESP ${url.hostname}${url.pathname}`, value, 0);
        } catch { record(`RESP ${status} ${url.origin}${url.pathname} text`); }
    };
    const record = line => { if (seen.length < 120 && !seen.includes(line)) seen.push(line); };
    const dump = window.__srLoginDump = [];
    const dumpAdd = entry => { if (dump.length < 400) dump.push(`${new Date().toISOString()} ${entry}`.slice(0, 20000)); };
    const noPassword = text => typeof text === 'string' ? text.replace(/("password"\s*:\s*")((?:[^"\\]|\\.)*)"/g, '$1<omitted>"') : text;
    const bulky = url => /\/(maps|titles|data)(\/|$)/.test(url.pathname);
    const bodyShape = body => {
        try {
            if (body == null) return 'none';
            if (typeof body === 'string') {
                try { return 'json' + shape(JSON.parse(body), 0); } catch {}
                try { return 'form{' + [...new URLSearchParams(body).keys()].map(name).join(',') + '}'; } catch {}
                return 'text';
            }
            if (body instanceof URLSearchParams) return 'form{' + [...body.keys()].map(name).join(',') + '}';
            if (body instanceof FormData) return 'formdata{' + [...body.keys()].map(name).join(',') + '}';
            return typeof body;
        } catch { return 'unreadable'; }
    };
    const recordRequest = (method, input, body, headers) => {
        let headerNames = '';
        try {
            if (headers) headerNames = (headers instanceof Headers ? [...headers.keys()] : Array.isArray(headers) ? headers.map(h => h[0]) : Object.keys(headers)).map(name).join(',');
            else if (input && input.headers && typeof input.headers.keys === 'function') headerNames = [...input.headers.keys()].map(name).join(',');
        } catch {}
        try {
            const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
            if (!interesting(url)) return;
            const query = [...url.searchParams.keys()].map(name).join(',');
            record(`${String(method || 'GET').toUpperCase().slice(0, 8)} ${url.origin}${url.pathname}${query ? ' query{' + query + '}' : ''} body=${bodyShape(body)}${headerNames ? ' headers{' + headerNames + '}' : ''}`);
        } catch {}
    };
    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
        recordRequest((init && init.method) || (input && input.method), input, init && init.body, init && init.headers);
        const result = originalFetch.apply(this, arguments);
        try {
            const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
            if (interesting(url) && !bulky(url)) {
                let headers = '';
                try { const h = init && init.headers; headers = JSON.stringify(h instanceof Headers ? Object.fromEntries(h.entries()) : h || {}); } catch {}
                dumpAdd(`REQUEST ${(init && init.method) || 'GET'} ${url.href} headers=${headers} body=${noPassword(init && typeof init.body === 'string' ? init.body : '')}`);
                Promise.resolve(result).then(response => response.clone().text().then(text => dumpAdd(`RESPONSE ${response.status} ${url.href} body=${text}`))).catch(() => {});
            }
            if (interesting(url)) {
                Promise.resolve(result).then(response => response.clone().text().then(text => recordResponse(url, response.status, text))).catch(() => {});
            }
        } catch {}
        return result;
    };
    const methods = new WeakMap();
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
        methods.set(this, [method, url]);
        return originalOpen.apply(this, arguments);
    };
    const xhrHeaders = new WeakMap();
    const originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    if (originalSetHeader) XMLHttpRequest.prototype.setRequestHeader = function(key) {
        const list = xhrHeaders.get(this) || []; list.push([key]); xhrHeaders.set(this, list);
        return originalSetHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
        const request = methods.get(this);
        if (request) {
            recordRequest(request[0], request[1], body, xhrHeaders.get(this));
            try {
                const url = new URL(request[1], location.href);
                if (interesting(url) && !bulky(url)) {
                    dumpAdd(`REQUEST(xhr) ${request[0]} ${url.href} body=${noPassword(typeof body === 'string' ? body : '')}`);
                    this.addEventListener('load', () => { try { dumpAdd(`RESPONSE(xhr) ${this.status} ${url.href} body=${typeof this.response === 'string' ? this.response : JSON.stringify(this.response)}`); } catch {} });
                }
                if (interesting(url)) this.addEventListener('load', () => { try { recordResponse(url, this.status, typeof this.response === 'string' ? this.response : JSON.stringify(this.response)); } catch {} });
            } catch {}
        }
        return originalSend.apply(this, arguments);
    };
    // Krunker's sockets: the address, and the opcode and argument KINDS of each
    // message type sent and received (msgpack ["opcode", ...] plus a 2-byte
    // trailer). Strings show only their length class, never their text.
    // For the request/reply opcode _0 only, values that are protocol
    // constants are shown: numbers, booleans, identifier-like short text
    // (never the username), and which stored token a long text IS (by
    // comparison; the token itself is never recorded).
    const REVEAL = new Set(['_0']);
    const stored = () => {
        const get = key => { try { return localStorage.getItem(key) || ''; } catch { return ''; } };
        const known = {accessToken: get('__FRVR_auth_access_token'), refreshToken: get('__FRVR_auth_refresh_token'), krunkerToken: get('krunker_token'), username: get('krunker_username'), krunkerId: get('krunker_id')};
        // Every other stored value, by where it is stored.
        for (const [area, storage] of [['localStorage', () => localStorage], ['sessionStorage', () => sessionStorage]]) {
            try { const st = storage(); for (let k = 0; k < st.length && k < 200; k++) { const key = st.key(k); const v = st.getItem(key) || ''; if (!Object.values(known).includes(v)) known[`${area}[${name(key)}]`] = v; } } catch {}
        }
        try { for (const part of document.cookie.split(';')) { const at = part.indexOf('='); if (at > 0) known[`cookie[${name(part.slice(0, at).trim())}]`] = decodeURIComponent(part.slice(at + 1).trim()); } } catch {}
        return known;
    };
    const label = (text, known) => {
        for (const [key, value] of Object.entries(known)) if (value && text === value) return key;
        if (origins.has(text)) return origins.get(text);
        // A JWT: which kind (its claims' key names and platform), never its content.
        if (/^eyJ[\w-]+\.eyJ[\w-]+\.[\w-]+$/.test(text)) {
            try {
                const claims = JSON.parse(atob(text.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
                const platform = claims && claims.extra && typeof claims.extra.platform === 'string' ? claims.extra.platform.replace(/[^a-z-]/g, '') : '';
                const iss = typeof claims.iss === 'string' ? claims.iss.replace(/[^A-Za-z0-9._:-]/g, '').slice(0, 40) : '';
                const extra = claims.extra && typeof claims.extra === 'object' ? Object.keys(claims.extra).map(name).join('/') : '';
                let same = '';
                try {
                    const stored = (known && known.accessToken) || '';
                    if (stored) {
                        const other = JSON.parse(atob(stored.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
                        same = `;sameSubAsStored=${other.sub === claims.sub};storedIss=${typeof other.iss === 'string' ? other.iss.replace(/[^A-Za-z0-9._:-]/g, '').slice(0, 40) : ''};newerThanStored=${(claims.iat || 0) > (other.iat || 0)}`;
                    }
                } catch {}
                return `unknownJWT{${Object.keys(claims).map(name).join(',')};extra=${extra}${platform ? ';platform=' + platform : ''};iss=${iss}${same}}`;
            } catch { return 'unknownJWT'; }
        }
        if (/^[A-Za-z0-9_.:-]{1,24}$/.test(text)) return JSON.stringify(text);
        return null;
    };
    const kinds = (bytes, max) => {
        let i = 0;
        const out = [];
        const u8 = () => bytes[i++];
        const be = n => { let v = 0; for (let k = 0; k < n; k++) v = v * 256 + u8(); return v; };
        let reveal = false, known = null;
        const text = n => { const t = new TextDecoder().decode(bytes.slice(i, i + n)); i += n; return t; };
        const strKind = (n, kind) => {
            if (!reveal || depth0 !== 0) { i += n; return kind; }
            const t = text(n);
            return label(t, known || (known = stored())) || kind;
        };
        let depth0 = 0;
        const skip = depth => {
            if (i >= bytes.length || depth > 6) throw 0;
            depth0 = depth;
            const b = u8();
            if (b <= 0x7f) return reveal && depth === 0 ? String(b) : 'int';
            if (b >= 0xe0) return reveal && depth === 0 ? String(b - 256) : 'int';
            if ((b & 0xe0) === 0xa0) { const n = b & 0x1f; return strKind(n, n > 16 ? 'str' + (n > 100 ? 'L' : 'M') : 'strS'); }
            if ((b & 0xf0) === 0x90) { for (let n = b & 0x0f; n > 0; n--) skip(depth + 1); return 'arr'; }
            if ((b & 0xf0) === 0x80) { for (let n = (b & 0x0f) * 2; n > 0; n--) skip(depth + 1); return 'map'; }
            switch (b) {
                case 0xc0: return 'nil';
                case 0xc2: case 0xc3: return reveal && depth === 0 ? String(b === 0xc3) : 'bool';
                case 0xc4: i += be(1); return 'bin';
                case 0xc5: i += be(2); return 'bin';
                case 0xca: i += 4; return 'float';
                case 0xcb: i += 8; return 'float';
                case 0xcc: case 0xd0: i += 1; return 'int';
                case 0xcd: case 0xd1: i += 2; return 'int';
                case 0xce: case 0xd2: i += 4; return 'int';
                case 0xcf: case 0xd3: i += 8; return 'int';
                case 0xd9: { const n = be(1); return strKind(n, n > 100 ? 'strL' : 'strM'); }
                case 0xda: { const n = be(2); return strKind(n, 'strL'); }
                case 0xdc: { for (let n = be(2); n > 0; n--) skip(depth + 1); return 'arr'; }
                case 0xde: { for (let n = be(2) * 2; n > 0; n--) skip(depth + 1); return 'map'; }
            }
            throw 0;
        };
        try {
            const head = u8();
            const count = (head & 0xf0) === 0x90 ? head & 0x0f : head === 0xdc ? be(2) : -1;
            if (count < 1) return null;
            // The opcode itself: a short string (or a number).
            let opcode;
            const b = bytes[i];
            if ((b & 0xe0) === 0xa0 && (b & 0x1f) <= 24) {
                const n = b & 0x1f; i++;
                opcode = String.fromCharCode(...bytes.slice(i, i + n)).replace(/[^A-Za-z0-9_-]/g, '?'); i += n;
            } else if (b <= 0x7f) { opcode = '#' + b; i++; }
            else return null;
            reveal = REVEAL.has(opcode);
            for (let k = 1; k < count && k <= max; k++) out.push(skip(0));
            return `${opcode} [${out.join(',')}${count - 1 > max ? ',...' : ''}]`;
        } catch { return null; }
    };
    const toBase64 = bytes => { let text = ''; for (const b of bytes) text += String.fromCharCode(b); try { return btoa(text); } catch { return ''; } };
    const socketDump = (direction, host, bytes) => {
        try {
            const shape = kinds(bytes, 2) || '';
            if (/^(_0|a|sb|load|io-init|uid|ready|cust|custom) /.test(shape) && bytes.length < 16384) dumpAdd(`WS ${direction} ${host} ${shape.split(' ')[0]} base64=${toBase64(bytes)}`);
        } catch {}
    };
    const socketRecord = (direction, host, data) => {
        const describe = bytes => {
            socketDump(direction, host, bytes);
            const shape = kinds(bytes, direction === 'SEND' ? 12 : 4);
            if (!shape) return;
            record(`WS ${direction} ${host} ${shape}`);
            // The page may write the new token to storage just after sending
            // it: label _0 again once storage has settled.
            if (/^_0 /.test(shape) && /str[SML]/.test(shape)) {
                const copy = bytes.slice();
                setTimeout(() => { const later = kinds(copy, 12); if (later && later !== shape) record(`WS ${direction} ${host} ${later} (2 s later)`); }, 2000);
            }
        };
        try {
            if (data instanceof ArrayBuffer) describe(new Uint8Array(data));
            else if (ArrayBuffer.isView(data)) describe(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
            else if (typeof Blob !== 'undefined' && data instanceof Blob) data.arrayBuffer().then(b => describe(new Uint8Array(b))).catch(() => {});
        } catch {}
    };
    const socketHosts = new WeakMap();
    const originalSocketSend = window.WebSocket.prototype.send;
    window.WebSocket.prototype.send = function(data) {
        const host = socketHosts.get(this);
        if (host) socketRecord('SEND', host, data);
        return originalSocketSend.apply(this, arguments);
    };
    window.WebSocket = new Proxy(window.WebSocket, {
        construct(target, args) {
            const socket = Reflect.construct(target, args);
            try {
                const url = new URL(args[0], location.href);
                if (/(^|\.)(krunker\.io|frvr\.com)$/.test(url.hostname)) {
                    // Lobby hosts differ per game: keep only their kind.
                    const host = /^lobby-/.test(url.hostname) ? 'lobby' : url.hostname;
                    dumpAdd(`SOCKET ${url.href}`);
                    const known = stored();
                    const labels = [...url.searchParams].map(([key, value]) => `${name(key)}=${label(value, known) || (value.length > 100 ? 'strL' : value.length > 16 ? 'strM' : 'strS')}`);
                    record(`SOCKET ${url.protocol}//${url.hostname}${url.pathname} query{${labels.join(',')}}`);
                    for (const [key, value] of url.searchParams) if (value.length >= 16 && !origins.has(value)) origins.set(value, `SOCKET ${host} ?${name(key)}`);
                    socketHosts.set(socket, host);
                    socket.addEventListener('message', event => socketRecord('RECV', host, event.data));
                }
            } catch {}
            return socket;
        }
    });
})();
