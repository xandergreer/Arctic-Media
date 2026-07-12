// Arctic Media – Admin Integrations Tab (Radarr / Sonarr)

let _arrConfig = null;
let _arrSearchApp = 'radarr';

async function loadArr() {
    const el = document.getElementById('arr-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;
    try {
        const res = await fetch('/api/v1/arr/config', { credentials: 'include' });
        if (!res.ok) throw new Error(res.status);
        _arrConfig = await res.json();
        renderArr();
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load integration settings.</p>
        </div>`;
    }
}

function _arrAppCard(app, cfg) {
    const title = app === 'radarr' ? 'Radarr (Movies)' : 'Sonarr (TV Shows)';
    const icon = app === 'radarr' ? 'movie' : 'tv';
    const placeholder = app === 'radarr' ? 'http://localhost:7878' : 'http://localhost:8989';
    return `
    <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:1.25rem;flex:1;min-width:320px;">
        <div style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1rem;">
            <span class="material-icons" style="color:var(--primary);">${icon}</span>
            <h3 style="margin:0;font-size:1rem;">${title}</h3>
            <span id="arr-status-${app}" style="margin-left:auto;font-size:0.78rem;color:var(--text-muted);"></span>
        </div>
        <div class="form-group" style="margin-bottom:0.75rem;">
            <label style="font-size:0.8rem;">Server URL</label>
            <input id="arr-url-${app}" type="text" class="form-control" placeholder="${placeholder}" value="${cfg.url || ''}">
        </div>
        <div class="form-group" style="margin-bottom:0.75rem;">
            <label style="font-size:0.8rem;">API Key</label>
            <input id="arr-key-${app}" type="password" class="form-control" placeholder="Settings → General → API Key" value="${cfg.api_key || ''}">
        </div>
        <div style="display:flex;gap:0.75rem;margin-bottom:0.75rem;">
            <div class="form-group" style="flex:1;margin:0;">
                <label style="font-size:0.8rem;">Root Folder</label>
                <select id="arr-root-${app}" class="form-control">
                    ${cfg.root_folder ? `<option value="${cfg.root_folder}" selected>${cfg.root_folder}</option>` : '<option value="">— test connection to load —</option>'}
                </select>
            </div>
            <div class="form-group" style="flex:1;margin:0;">
                <label style="font-size:0.8rem;">Quality Profile</label>
                <select id="arr-profile-${app}" class="form-control">
                    ${cfg.quality_profile_id ? `<option value="${cfg.quality_profile_id}" selected>Profile #${cfg.quality_profile_id}</option>` : '<option value="">— test connection to load —</option>'}
                </select>
            </div>
        </div>
        <div style="display:flex;gap:0.5rem;">
            <button class="btn btn-ghost" onclick="testArr('${app}')">
                <span class="material-icons" style="font-size:1rem;">wifi_tethering</span> Test
            </button>
            <button class="btn btn-primary" onclick="saveArr('${app}')">
                <span class="material-icons" style="font-size:1rem;">save</span> Save
            </button>
        </div>
    </div>`;
}

function renderArr() {
    const el = document.getElementById('arr-content');
    el.innerHTML = `
        <p style="color:var(--text-muted);font-size:0.875rem;margin-bottom:1.25rem;">
            Connect Radarr and Sonarr to add media to your server directly from this page.
            Downloads land in your library folders and are picked up by the automatic scan.
        </p>
        <div style="display:flex;gap:1.25rem;flex-wrap:wrap;margin-bottom:2rem;">
            ${_arrAppCard('radarr', _arrConfig.radarr)}
            ${_arrAppCard('sonarr', _arrConfig.sonarr)}
        </div>

        <h3 style="margin:0 0 1rem 0;font-size:1rem;display:flex;align-items:center;gap:0.5rem;">
            <span class="material-icons" style="color:var(--primary);">add_circle</span> Add Media
        </h3>
        <div style="display:flex;gap:0.75rem;margin-bottom:1.25rem;flex-wrap:wrap;">
            <select id="arr-search-type" class="form-control" style="width:150px;" onchange="_arrSearchApp=this.value">
                <option value="radarr">Movie</option>
                <option value="sonarr">TV Show</option>
            </select>
            <input id="arr-search-input" type="text" class="form-control" style="flex:1;min-width:220px;"
                   placeholder="Search by title…" onkeydown="if(event.key==='Enter')searchArr()">
            <button class="btn btn-primary" onclick="searchArr()">
                <span class="material-icons" style="font-size:1rem;">search</span> Search
            </button>
        </div>
        <div id="arr-search-results"></div>`;
}

async function testArr(app) {
    const statusEl = document.getElementById(`arr-status-${app}`);
    statusEl.textContent = 'Testing…';
    statusEl.style.color = 'var(--text-muted)';
    // Save URL/key first so the test uses what's in the fields
    await _saveArrFields(app, false);
    try {
        const res = await fetch(`/api/v1/arr/${app}/test`, { method: 'POST', credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Connection failed');
        statusEl.textContent = `✓ ${data.app_name} ${data.version}`;
        statusEl.style.color = '#22c55e';
        await _loadArrOptions(app);
    } catch (e) {
        statusEl.textContent = '✗ ' + e.message;
        statusEl.style.color = '#f87171';
    }
}

async function _loadArrOptions(app) {
    try {
        const res = await fetch(`/api/v1/arr/${app}/options`, { credentials: 'include' });
        if (!res.ok) return;
        const opts = await res.json();
        const cfg = _arrConfig[app];

        const rootSel = document.getElementById(`arr-root-${app}`);
        rootSel.innerHTML = opts.root_folders.map(r =>
            `<option value="${r.path}" ${r.path === cfg.root_folder ? 'selected' : ''}>${r.path}</option>`).join('');

        const profSel = document.getElementById(`arr-profile-${app}`);
        profSel.innerHTML = opts.quality_profiles.map(p =>
            `<option value="${p.id}" ${p.id === cfg.quality_profile_id ? 'selected' : ''}>${p.name}</option>`).join('');
    } catch (_) { }
}

async function _saveArrFields(app, includeDefaults) {
    const body = {};
    body[`${app}_url`] = document.getElementById(`arr-url-${app}`).value.trim();
    body[`${app}_key`] = document.getElementById(`arr-key-${app}`).value.trim();
    if (includeDefaults) {
        body[`${app}_root`] = document.getElementById(`arr-root-${app}`).value;
        body[`${app}_profile`] = document.getElementById(`arr-profile-${app}`).value;
    }
    const res = await fetch('/api/v1/arr/config', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
    if (res.ok) {
        _arrConfig[app].url = body[`${app}_url`];
        _arrConfig[app].api_key = body[`${app}_key`];
        _arrConfig[app].configured = !!(body[`${app}_url`] && body[`${app}_key`]);
        if (includeDefaults) {
            _arrConfig[app].root_folder = body[`${app}_root`];
            _arrConfig[app].quality_profile_id = parseInt(body[`${app}_profile`]) || null;
        }
    }
    return res.ok;
}

async function saveArr(app) {
    const statusEl = document.getElementById(`arr-status-${app}`);
    const ok = await _saveArrFields(app, true);
    statusEl.textContent = ok ? '✓ Saved' : '✗ Save failed';
    statusEl.style.color = ok ? '#22c55e' : '#f87171';
}

async function searchArr() {
    const q = document.getElementById('arr-search-input').value.trim();
    const app = document.getElementById('arr-search-type').value;
    const resultsEl = document.getElementById('arr-search-results');
    if (!q) return;

    resultsEl.innerHTML = `<p style="color:var(--text-muted);">Searching ${app === 'radarr' ? 'movies' : 'shows'}…</p>`;
    try {
        const res = await fetch(`/api/v1/arr/${app}/search?q=${encodeURIComponent(q)}`, { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Search failed');
        if (!data.length) {
            resultsEl.innerHTML = `<p style="color:var(--text-muted);">No results.</p>`;
            return;
        }
        resultsEl.innerHTML = `<div style="display:flex;flex-direction:column;gap:0.75rem;">` + data.map((item, i) => {
            const id = app === 'radarr' ? item.tmdb_id : item.tvdb_id;
            const poster = item.poster
                ? `<img src="${item.poster}" style="width:60px;height:90px;object-fit:cover;border-radius:4px;flex-shrink:0;" loading="lazy">`
                : `<div style="width:60px;height:90px;background:var(--surface-2);border-radius:4px;flex-shrink:0;display:flex;align-items:center;justify-content:center;"><span class="material-icons" style="color:var(--text-muted);">image</span></div>`;
            const action = item.in_library
                ? `<span style="color:#22c55e;font-size:0.8rem;display:inline-flex;align-items:center;gap:0.25rem;"><span class="material-icons" style="font-size:1rem;">check_circle</span>In library</span>`
                : `<button id="arr-add-${i}" class="btn btn-primary" style="flex-shrink:0;" onclick="addArr('${app}', ${id}, ${i})">
                       <span class="material-icons" style="font-size:1rem;">add</span> Add
                   </button>`;
            return `<div style="display:flex;gap:1rem;align-items:center;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:0.75rem;">
                ${poster}
                <div style="flex:1;min-width:0;">
                    <div style="font-weight:600;">${item.title} ${item.year ? `<span style="color:var(--text-muted);font-weight:400;">(${item.year})</span>` : ''}</div>
                    <div style="font-size:0.8rem;color:var(--text-muted);overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;">${item.overview || ''}</div>
                </div>
                ${action}
            </div>`;
        }).join('') + `</div>`;
    } catch (e) {
        resultsEl.innerHTML = `<p style="color:#f87171;">Error: ${e.message}</p>`;
    }
}

/** Jump from a user request to the Integrations tab with the search pre-filled. */
async function sendRequestToArr(text) {
    switchTab('arr');
    // loadArr re-renders the tab async; wait for the search input to exist
    for (let i = 0; i < 30; i++) {
        const input = document.getElementById('arr-search-input');
        if (input) {
            input.value = text;
            searchArr();
            return;
        }
        await new Promise(r => setTimeout(r, 100));
    }
}

async function addArr(app, id, btnIdx) {
    const btn = document.getElementById(`arr-add-${btnIdx}`);
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="material-icons" style="font-size:1rem;">hourglass_top</span> Adding…'; }
    try {
        const body = app === 'radarr' ? { tmdb_id: id } : { tvdb_id: id };
        const res = await fetch(`/api/v1/arr/${app}/add`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || 'Add failed');
        if (btn) {
            btn.outerHTML = `<span style="color:#22c55e;font-size:0.8rem;display:inline-flex;align-items:center;gap:0.25rem;">
                <span class="material-icons" style="font-size:1rem;">check_circle</span>Added — downloading</span>`;
        }
    } catch (e) {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<span class="material-icons" style="font-size:1rem;">add</span> Add';
        }
        alert(`Failed to add: ${e.message}`);
    }
}
