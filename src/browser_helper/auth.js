(() => {
    // ExecuteScript runs in the top-level document. No frame message bridge is exposed.
    if (window !== window.top || location.origin !== 'https://krunker.io') return {state: 'OTHER_ORIGIN'};
    if (window.__srProbeOnly) {
        return {state: typeof window.FRVR?.auth?.getFreshAccessToken === 'function' ? 'SDK_AVAILABLE' : 'WAIT_SDK'};
    }
    const unquote = value => {
        if (typeof value === 'string' && value.length >= 2 && value[0] === '"') {
            try { const parsed = JSON.parse(value); if (typeof parsed === 'string') return parsed; } catch {}
        }
        return value;
    };
    let token;
    let gate;
    try {
        // Anonymous sessions also have tokens. Never read one before the account flag exists.
        const username = localStorage.getItem('krunker_username');
        if (!username || !username.trim()) {
            delete window.__srStorageGate;
            delete window.__srAccess;
            return {state: 'WAIT_LOGIN'};
        }
        gate = window.__srStorageGate;
        if (!gate || gate.username !== username) {
            // The login handler can write the username before replacing anonymous access.
            gate = window.__srStorageGate = {username, readyAt: Date.now() + 1000};
            delete window.__srAccess;
        }
        if (Date.now() < gate.readyAt) return {state: 'WAIT_STORAGE'};
        // The SDK stores tokens JSON-encoded ("\"eyJ...\""): hand over the bare token.
        token = unquote(localStorage.getItem('__FRVR_auth_access_token'));
    } catch {
        return {state: 'STORAGE_UNAVAILABLE'};
    }
    // Read again on every poll: login may set the username and token in separate steps.
    if (typeof token === 'string' && token.length > 0 && token.length <= 32768) {
        try {
            const parts = token.split('.');
            if (parts.length === 3) {
                const payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
                const claims = JSON.parse(atob(payload));
                const pending = [claims];
                while (pending.length) {
                    const item = pending.pop();
                    if (!item || typeof item !== 'object') continue;
                    for (const [key, value] of Object.entries(item)) {
                        if (key.toLowerCase() === 'platform' && typeof value === 'string' &&
                            ['anonymous', 'anon'].includes(value.trim().toLowerCase())) {
                            // Even verified guest JWTs may remain after the username is written.
                            return {state: 'GUEST_TOKEN'};
                        }
                        if (value && typeof value === 'object') pending.push(value);
                    }
                }
                const {exp} = claims;
                if (Number.isSafeInteger(exp) && exp > Math.floor(Date.now() / 1000) + 60) {
                    // The refresh token too: SR Client renews the session through
                    // FRVR's API from now on, without this browser.
                    let refresh = '';
                    try { refresh = unquote(localStorage.getItem('__FRVR_auth_refresh_token')) || ''; } catch {}
                    return {state: 'READY', token, refresh};
                }
            }
        } catch { /* Wait for the site to finish login or refresh; never forward malformed tokens. */ }
    }
    if (typeof window.FRVR?.auth?.getFreshAccessToken !== 'function') return {state: 'WAIT_SDK'};
    let request = window.__srAccess;
    if (!request) {
        request = window.__srAccess = {state: 'PENDING', started: Date.now()};
        // Let the official SDK renew its storage. Its return value is never sent to native code.
        Promise.resolve().then(() => window.FRVR.auth.getFreshAccessToken()).then(() => {
            request.state = 'WAIT_TOKEN';
            // SDK completion can also precede the site's asynchronous storage write.
            if (window.__srStorageGate === gate) gate.readyAt = Date.now() + 1000;
        }).catch(() => { request.state = 'SESSION_REJECTED'; });
    }
    // Let normal site login change the session; only the SDK performs refresh.
    if ((request.state === 'SESSION_REJECTED' || request.state === 'WAIT_TOKEN') && Date.now() - request.started > 3000) {
        delete window.__srAccess;
    }
    return {state: request.state};
})()
