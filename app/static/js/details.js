// Arctic Media 2.0 - Details Page Logic

let mediaId, isShow, els;

// ── Stream token management ───────────────────────────────────────────────────
// HLS tokens are short-lived (1 hour). For long movies or binge sessions we
// must refresh the token before it expires so HLS.js can keep fetching segments
// without hitting a 401 mid-stream.
//
// Strategy:
//   1. Cache the token + its expiry time.
//   2. Schedule a silent background refresh 5 minutes before expiry.
//   3. Use a custom HLS.js loader that reads _cachedToken on every request,
//      so the latest token is used automatically — no stream restart needed.

const _TOKEN_TTL_MS     = 60 * 60 * 1000;  // keep in sync with HLS_TOKEN_EXPIRE_HOURS
const _TOKEN_REFRESH_MS = 5  * 60 * 1000;  // refresh this many ms before expiry

let _cachedToken      = null;
let _tokenExpiresAt   = 0;
let _tokenRefreshTimer = null;

async function _fetchFreshToken() {
    const tok = await getStreamToken();   // defined in main.js
    if (tok) {
        _cachedToken    = tok;
        _tokenExpiresAt = Date.now() + _TOKEN_TTL_MS;
        _scheduleTokenRefresh();
    }
    return tok;
}

function _scheduleTokenRefresh() {
    if (_tokenRefreshTimer) clearTimeout(_tokenRefreshTimer);
    const delay = Math.max(0, (_tokenExpiresAt - Date.now()) - _TOKEN_REFRESH_MS);
    _tokenRefreshTimer = setTimeout(async () => {
        console.log('[Arctic] Refreshing stream token silently...');
        await _fetchFreshToken();
    }, delay);
}

/** Returns a cached token if still fresh, otherwise fetches a new one. */
async function getValidStreamToken() {
    if (_cachedToken && Date.now() < _tokenExpiresAt - _TOKEN_REFRESH_MS) {
        return _cachedToken;
    }
    return _fetchFreshToken();
}

/**
 * Build an HLS.js config that includes a custom loader which substitutes the
 * latest cached token into every playlist/segment URL just before the request
 * is sent. This means a mid-session token refresh is picked up automatically
 * by the very next segment fetch — no stream reload required.
 */
function _makeHlsConfig(startPosition) {
    const DefaultLoader = Hls.DefaultConfig.loader;

    class TokenAwareLoader extends DefaultLoader {
        load(context, config, callbacks) {
            // Swap in the freshest token we have for every outgoing request.
            if (_cachedToken && context.url && context.url.includes('token=')) {
                context.url = context.url.replace(/token=[^&]+/, `token=${_cachedToken}`);
            }
            super.load(context, config, callbacks);
        }
    }

    return {
        loader: TokenAwareLoader,
        startPosition: startPosition > 0 ? startPosition : -1,
        capLevelToPlayerSize: true,
        debug: false,
    };
}

function _renderExternalLinks(data) {
    const container = document.getElementById('external-links');
    if (!container) return;
    container.innerHTML = '';

    const tmdbId = data.tmdb_id || (data.extra_json && data.extra_json.tmdb_id);
    const imdbId = data.extra_json && data.extra_json.imdb_id;
    const tmdbType = isShow ? 'tv' : 'movie';

    if (tmdbId) {
        const a = document.createElement('a');
        a.href = `https://www.themoviedb.org/${tmdbType}/${tmdbId}/`;
        a.target = '_blank';
        a.rel = 'noreferrer nofollow';
        a.textContent = '🎬 TMDB';
        a.style.cssText = 'display:inline-flex;align-items:center;gap:5px;background:#032541;color:#01b4e4;padding:6px 14px;border-radius:5px;text-decoration:none;font-weight:700;font-size:13px;border:1px solid #01b4e4;transition:background 0.15s,color 0.15s;';
        a.onmouseover = () => { a.style.background = '#01b4e4'; a.style.color = '#fff'; };
        a.onmouseout  = () => { a.style.background = '#032541'; a.style.color = '#01b4e4'; };
        container.appendChild(a);
    }

    if (imdbId) {
        const a = document.createElement('a');
        a.href = `https://www.imdb.com/title/${imdbId}/`;
        a.target = '_blank';
        a.rel = 'noreferrer nofollow';
        a.textContent = 'IMDb';
        a.style.cssText = 'display:inline-flex;align-items:center;gap:5px;background:#f5c518;color:#000;padding:6px 14px;border-radius:5px;text-decoration:none;font-weight:700;font-size:13px;border:1px solid #d4aa00;transition:background 0.15s;';
        a.onmouseover = () => { a.style.background = '#d4aa00'; };
        a.onmouseout  = () => { a.style.background = '#f5c518'; };
        container.appendChild(a);
    }
}

function _renderGenresDisplay(data) {
    const section = document.getElementById('genres-section');
    const list = document.getElementById('genres-list');
    if (!section || !list) return;
    const genres = (data.extra_json && data.extra_json.genres) || [];
    if (!genres.length) return;
    list.innerHTML = genres.map(g => `<span class="genre-pill">${g}</span>`).join('');
    section.classList.remove('hidden');
    const about = document.getElementById('about-section');
    if (about) about.classList.remove('hidden');
}

function _renderCastDisplay(data) {
    const section = document.getElementById('cast-section');
    const list = document.getElementById('cast-list');
    if (!section || !list) return;
    const cast = (data.extra_json && data.extra_json.cast) || [];
    if (!cast.length) return;
    list.innerHTML = cast.map(c => {
        const photoHtml = c.photo
            ? `<img class="cast-card-photo" src="${c.photo}" alt="${c.name}" loading="lazy"
                    onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">`
              + `<div class="cast-card-photo-placeholder" style="display:none"><span class="material-icons" style="font-size:2rem;">person</span></div>`
            : `<div class="cast-card-photo-placeholder"><span class="material-icons" style="font-size:2rem;">person</span></div>`;
        return `<div class="cast-card">
            ${photoHtml}
            <div class="cast-card-name" title="${c.name}">${c.name}</div>
            ${c.role ? `<div class="cast-card-role" title="${c.role}">${c.role}</div>` : ''}
        </div>`;
    }).join('');
    section.classList.remove('hidden');
}

async function _renderSimilarDisplay(mediaId, isShow) {
    const section = document.getElementById('similar-section');
    const list = document.getElementById('similar-list');
    if (!section || !list) return;
    try {
        const res = await fetch(`/api/v1/media/${mediaId}/similar`, { credentials: 'include' });
        if (!res.ok) return;
        const items = await res.json();
        if (!items || !items.length) return;
        const base = isShow ? '/show' : '/movie';
        list.innerHTML = items.map(item => {
            const year = item.release_date ? new Date(item.release_date).getFullYear() : '';
            const poster = item.poster_url || '';
            return `<div class="similar-card" onclick="window.location.href='${base}/${item.id}'">
                <img class="similar-card-poster" src="${poster}" alt="${item.title}" loading="lazy">
                <div class="similar-card-title" title="${item.title}">${item.title}</div>
                ${year ? `<div class="similar-card-year">${year}</div>` : ''}
            </div>`;
        }).join('');
        section.classList.remove('hidden');
    } catch (e) { console.error('Similar fetch failed', e); }
}

async function _renderMediaInfo(mediaId) {
    const section = document.getElementById('mediainfo-section');
    const container = document.getElementById('mediainfo-list');
    if (!section || !container) return;
    try {
        const res = await fetch(`/api/v1/media/${mediaId}/mediainfo`, { credentials: 'include' });
        if (!res.ok) return;
        const info = await res.json();
        if (!info || Object.keys(info).length === 0) return;

        const cards = [];

        // Video card
        if (info.video) {
            const v = info.video;
            const rows = [];
            if (v.codec) rows.push(['Codec', v.codec.toUpperCase()]);
            if (v.profile) rows.push(['Profile', v.profile]);
            if (v.width && v.height) rows.push(['Resolution', `${v.width}×${v.height}`]);
            if (v.framerate) rows.push(['Framerate', `${v.framerate} fps`]);
            if (v.bitrate) rows.push(['Bitrate', `${(v.bitrate / 1000000).toFixed(1)} Mbps`]);
            if (v.pix_fmt) rows.push(['Pixel Format', v.pix_fmt]);
            if (rows.length) cards.push(_miCard('Video', rows));
        }

        // Audio tracks
        for (const t of (info.audio_tracks || [])) {
            const rows = [];
            if (t.language && t.language !== 'und') rows.push(['Language', t.language.toUpperCase()]);
            if (t.title && t.title !== t.language) rows.push(['Title', t.title]);
            if (t.codec) rows.push(['Codec', t.codec.toUpperCase()]);
            if (t.channels) rows.push(['Channels', String(t.channels)]);
            if (t.sample_rate) rows.push(['Sample Rate', `${t.sample_rate} Hz`]);
            if (rows.length) cards.push(_miCard('Audio', rows));
        }

        // Subtitle tracks (single card listing all)
        const subs = info.subtitle_tracks || [];
        if (subs.length) {
            const rows = subs.map((s, i) => {
                const lang = s.language && s.language !== 'und' ? s.language.toUpperCase() : '';
                const codec = s.codec ? `(${s.codec})` : '';
                const img = s.is_image ? ' [image]' : '';
                return [`${i + 1}.`, [lang, codec, img].filter(Boolean).join(' ')];
            });
            cards.push(_miCard('Subtitles', rows));
        }

        // File info
        if (info.size_bytes || info.duration) {
            const rows = [];
            if (info.path) rows.push(['File', info.path.split(/[\\/]/).pop()]);
            if (info.size_bytes) rows.push(['Size', _fmtSize(info.size_bytes)]);
            if (info.duration) rows.push(['Duration', _fmtDuration(info.duration)]);
            if (rows.length) cards.push(_miCard('File', rows));
        }

        if (!cards.length) return;
        container.innerHTML = cards.join('');
        section.classList.remove('hidden');
    } catch (e) { console.error('Media info fetch failed', e); }
}

function _miCard(type, rows) {
    return `<div class="mediainfo-card">
        <div class="mediainfo-card-type">${type}</div>
        ${rows.map(([label, value]) =>
            `<div class="mediainfo-card-row">
                <span class="mediainfo-card-label">${label}</span>
                <span class="mediainfo-card-value">${value}</span>
            </div>`).join('')}
    </div>`;
}

function _fmtSize(bytes) {
    if (bytes >= 1e9) return (bytes / 1e9).toFixed(2) + ' GB';
    if (bytes >= 1e6) return (bytes / 1e6).toFixed(0) + ' MB';
    return bytes + ' B';
}

function _fmtDuration(secs) {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

document.addEventListener("DOMContentLoaded", async () => {
    try {
        const idInput = document.getElementById("media-id");
        if (!idInput) {
            console.error("Media ID input missing");
            return;
        }
        mediaId = idInput.value;
        isShow = document.getElementById("is-show") !== null;

        // DOM Elements
        els = {
            backdrop: document.getElementById("backdrop-img"),
            poster: document.getElementById("poster-img"),
            title: document.getElementById("title"),
            year: document.getElementById("year"),
            overview: document.getElementById("overview"),
            duration: document.getElementById("duration"), // Movie only
            seasonsCount: document.getElementById("seasons-count"), // Show only
            seasonList: document.getElementById("season-list"), // Show only
            episodeGrid: document.getElementById("episodes-grid"), // Show only
            seasonTitle: document.getElementById("season-title") // Show only
        };

        await loadDetails();
        _checkMovieResume();
        if (isShow) {
            await loadSeasons();
        }
    } catch (e) {
        console.error("Failed to load details", e);
        if (els && els.title) els.title.innerText = "Error: " + e.message;
        if (els && els.overview) els.overview.innerText = "Please check console or refresh.";
    }
});

let currentMetadata = {};

async function loadDetails() {
    try {
        const res = await fetch(`/api/v1/media/${mediaId}`, {
            credentials: 'include'
        });
        if (!res.ok) throw new Error(`API Error ${res.status}`);
        const data = await res.json();
        currentMetadata = data; // Store for Edit Modal

        // Check Admin Status and Setup Edit
        checkAdminAndSetupEdit();

        // Update UI
        if (els.title) els.title.innerText = data.title;
        if (els.overview) els.overview.innerText = data.overview || "No overview available.";
        _renderExternalLinks(data);
        _renderGenresDisplay(data);
        _renderCastDisplay(data);
        _renderSimilarDisplay(mediaId, isShow);
        _renderMediaInfo(mediaId);

        if (data.release_date && els.year) {
            els.year.innerText = new Date(data.release_date).getFullYear();
        }

        if (data.backdrop_url && els.backdrop) els.backdrop.src = data.backdrop_url;
        if (data.poster_url && els.poster) els.poster.src = data.poster_url;

        // Type specific
        if (!isShow && els.duration) {
            els.duration.innerText = "2h 15m"; // TODO: Fetch from file metadata

            // Fetch multiple files (versions/trailers)
            try {
                const fRes = await fetch(`/api/v1/media/${mediaId}/files`, { credentials: 'include' });
                if (fRes.ok) {
                    const files = await fRes.json();
                    if (files && files.length > 0) {
                        // Sort by size descending (largest is likely the main feature)
                        files.sort((a, b) => b.size_bytes - a.size_bytes);
                        window.currentFileId = files[0].id; // Set default

                        if (files.length > 1) {
                            const container = document.getElementById("file-versions-container");
                            if (container) {
                                container.innerHTML = `<span style="color:var(--text-muted);font-size:0.875rem;margin-right:0.5rem">Versions:</span>`;
                                files.forEach(f => {
                                    const sizeMB = (f.size_bytes / (1024 * 1024)).toFixed(0);
                                    let nameDisp = f.filename;
                                    // Shorten long filenames for UI
                                    if (nameDisp.length > 30) nameDisp = nameDisp.substring(0, 27) + "...";

                                    const isDefault = f.id === window.currentFileId;
                                    const btn = document.createElement("button");
                                    // Using chip + active for styling
                                    btn.className = `badge ${isDefault ? 'active-version' : ''}`;
                                    btn.style.cursor = "pointer";
                                    btn.style.border = "none";
                                    if (isDefault) btn.style.backgroundColor = "var(--primary)";

                                    // textContent prevents a crafted filename from injecting HTML (XSS).
                                    btn.textContent = nameDisp;
                                    const sizeSpan = document.createElement('span');
                                    sizeSpan.style.cssText = 'opacity:0.7;font-size:0.9em;margin-left:4px';
                                    sizeSpan.textContent = `(${sizeMB}MB)`;
                                    btn.appendChild(sizeSpan);

                                    btn.onclick = () => {
                                        window.currentFileId = f.id;
                                        // Update active state visuals
                                        container.querySelectorAll(".badge").forEach(c => {
                                            c.style.backgroundColor = "";
                                            c.classList.remove("active-version");
                                        });
                                        btn.style.backgroundColor = "var(--primary)";
                                        btn.classList.add("active-version");

                                        // Force player reload on next play
                                        currentMediaId = null;
                                    };
                                    container.appendChild(btn);
                                });
                                container.classList.remove("hidden");
                            }
                        }
                    }
                }
            } catch (e) { console.error("Could not load files", e); }
        }
    } catch (e) {
        throw e; // Propagate to main catch
    }
}

// ── Edit modal state ──────────────────────────────────────────────────────────
let _editGenres = [];
let _editCast   = [];

function _renderGenres() {
    const list = document.getElementById('edit-genres-list');
    if (!list) return;
    if (_editGenres.length === 0) {
        list.innerHTML = '<span style="color:var(--text-muted);font-size:0.875rem;font-style:italic;">No genres. Add one below.</span>';
        return;
    }
    list.innerHTML = _editGenres.map((g, i) => `
        <span class="badge" style="display:inline-flex;align-items:center;gap:0.25rem;padding:0.3rem 0.55rem;">
            ${g}
            <button onclick="_removeGenre(${i})" style="background:none;border:none;color:inherit;cursor:pointer;padding:0;line-height:1;opacity:0.65;">
                <span class="material-icons" style="font-size:0.85rem;vertical-align:middle;">close</span>
            </button>
        </span>`).join('');
}

window._removeGenre = function (idx) {
    _editGenres.splice(idx, 1);
    _renderGenres();
};

function _renderCast() {
    const list = document.getElementById('edit-cast-list');
    if (!list) return;
    if (_editCast.length === 0) {
        list.innerHTML = '<span style="color:var(--text-muted);font-size:0.875rem;font-style:italic;">No cast added.</span>';
        return;
    }
    list.innerHTML = _editCast.map((c, i) => `
        <div style="display:flex;align-items:center;gap:0.6rem;padding:0.5rem 0.75rem;background:var(--surface-2);border-radius:var(--radius-sm);border:1px solid var(--border);">
            <span class="material-icons" style="font-size:1rem;color:var(--text-muted);flex-shrink:0;">person</span>
            <div style="flex:1;min-width:0;">
                <div style="font-size:0.875rem;font-weight:600;">${c.name}</div>
                ${c.role ? `<div style="font-size:0.78rem;color:var(--text-muted);">${c.role}</div>` : ''}
            </div>
            <button onclick="_removeCast(${i})" class="btn btn-ghost btn-sm" style="padding:0.2rem;flex-shrink:0;">
                <span class="material-icons" style="font-size:0.9rem;">close</span>
            </button>
        </div>`).join('');
}

window._removeCast = function (idx) {
    _editCast.splice(idx, 1);
    _renderCast();
};

function _showEditMsg(text, ok) {
    const el = document.getElementById('edit-msg');
    if (!el) return;
    el.textContent = text;
    el.style.color = ok ? '#4ade80' : '#f87171';
    el.style.display = 'block';
}

function _hideEditMsg() {
    const el = document.getElementById('edit-msg');
    if (el) el.style.display = 'none';
}

async function checkAdminAndSetupEdit() {
    try {
        const meRes = await fetch('/api/v1/auth/me', { credentials: 'include' });
        if (!meRes.ok) return;
        const me = await meRes.json();
        if (!me.is_superuser) return;

        const editBtn  = document.getElementById('editBtn');
        const modal    = document.getElementById('editModal');
        if (!editBtn || !modal) return;

        editBtn.classList.remove('hidden');

        // ── Tab switching ──────────────────────────────────────────────────────
        document.querySelectorAll('.edit-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                document.querySelectorAll('.edit-tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.edit-tab-panel').forEach(p => p.classList.add('hidden'));
                tab.classList.add('active');
                const panel = document.getElementById(`edit-tab-${tab.dataset.tab}`);
                if (panel) panel.classList.remove('hidden');
            });
        });

        // ── Image previews ─────────────────────────────────────────────────────
        const posterIn   = document.getElementById('edit-poster');
        const backdropIn = document.getElementById('edit-backdrop');
        if (posterIn) posterIn.addEventListener('input', () => {
            const preview = document.getElementById('edit-poster-preview');
            if (!preview) return;
            const img = preview.querySelector('img');
            if (posterIn.value) { img.src = posterIn.value; preview.style.display = 'block'; }
            else preview.style.display = 'none';
        });
        if (backdropIn) backdropIn.addEventListener('input', () => {
            const preview = document.getElementById('edit-backdrop-preview');
            if (!preview) return;
            const img = preview.querySelector('img');
            if (backdropIn.value) { img.src = backdropIn.value; preview.style.display = 'block'; }
            else preview.style.display = 'none';
        });

        // ── Genre editor ───────────────────────────────────────────────────────
        const genreAddBtn = document.getElementById('edit-genre-add');
        const genreInput  = document.getElementById('edit-genre-input');
        if (genreAddBtn && genreInput) {
            const addGenre = () => {
                const v = genreInput.value.trim();
                if (!v || _editGenres.includes(v)) { genreInput.value = ''; return; }
                _editGenres.push(v);
                genreInput.value = '';
                _renderGenres();
            };
            genreAddBtn.addEventListener('click', addGenre);
            genreInput.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); addGenre(); } });
        }

        // ── Cast editor ────────────────────────────────────────────────────────
        const castAddBtn = document.getElementById('edit-cast-add');
        const castName   = document.getElementById('edit-cast-name');
        const castRole   = document.getElementById('edit-cast-role');
        if (castAddBtn && castName) {
            castAddBtn.addEventListener('click', () => {
                const n = castName.value.trim();
                if (!n) return;
                const r = castRole ? castRole.value.trim() : '';
                _editCast.push({ name: n, role: r || null });
                castName.value = '';
                if (castRole) castRole.value = '';
                _renderCast();
            });
            castName.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); castAddBtn.click(); } });
        }

        // ── Close modal ────────────────────────────────────────────────────────
        const closeModal = () => modal.classList.add('hidden');
        document.getElementById('closeEditModal')?.addEventListener('click', closeModal);
        document.getElementById('cancelEditModal')?.addEventListener('click', closeModal);
        window.addEventListener('click', e => {
            if (e.target === modal) closeModal();
            const dm = document.getElementById('deleteModal');
            if (dm && e.target === dm) dm.classList.add('hidden');
        });

        // ── Fetch from TMDB ────────────────────────────────────────────────────
        const fetchTmdbBtn = document.getElementById('edit-fetch-tmdb');
        if (fetchTmdbBtn) {
            fetchTmdbBtn.addEventListener('click', async () => {
                const tmdbId = parseInt(document.getElementById('edit-tmdb').value) || null;
                if (!tmdbId) { _showEditMsg('Enter a TMDB ID first.', false); return; }
                fetchTmdbBtn.disabled = true;
                fetchTmdbBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">hourglass_top</span> Fetching…';
                try {
                    const r = await fetch(`/api/v1/media/${mediaId}`, {
                        method: 'PATCH',
                        credentials: 'include',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ tmdb_id: tmdbId, refresh_from_tmdb: true })
                    });
                    if (!r.ok) {
                        const err = await r.json().catch(() => ({}));
                        _showEditMsg(err.detail || 'TMDB fetch failed.', false);
                        fetchTmdbBtn.disabled = false;
                        fetchTmdbBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">download</span> Fetch from TMDB';
                    } else {
                        window.location.reload();
                    }
                } catch {
                    _showEditMsg('Request failed.', false);
                    fetchTmdbBtn.disabled = false;
                    fetchTmdbBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">download</span> Fetch from TMDB';
                }
            });
        }

        // ── Open modal & populate ──────────────────────────────────────────────
        editBtn.addEventListener('click', () => {
            const d  = currentMetadata;
            const xj = d.extra_json || {};

            // Reset to Info tab
            document.querySelectorAll('.edit-tab').forEach((t, i) => t.classList.toggle('active', i === 0));
            document.querySelectorAll('.edit-tab-panel').forEach((p, i) => p.classList.toggle('hidden', i !== 0));

            // Info tab
            document.getElementById('edit-title').value         = d.title || '';
            document.getElementById('edit-original-title').value = xj.original_title || '';
            document.getElementById('edit-sort-title').value    = d.sort_title || '';
            document.getElementById('edit-tagline').value       = xj.tagline || '';
            document.getElementById('edit-overview').value      = d.overview || '';
            document.getElementById('edit-release-date').value  = d.release_date ? d.release_date.slice(0, 10) : '';

            // IDs tab
            document.getElementById('edit-tmdb').value  = d.tmdb_id || xj.tmdb_id || '';
            document.getElementById('edit-imdb').value  = xj.imdb_id || '';
            document.getElementById('edit-tvdb').value  = xj.tvdb_id || '';

            // Genres
            _editGenres = Array.isArray(xj.genres) ? [...xj.genres] : [];
            _renderGenres();

            // Cast
            _editCast = Array.isArray(xj.cast)
                ? xj.cast.map(c => ({ name: c.name, role: c.role || null }))
                : [];
            _renderCast();

            // Images
            if (posterIn) {
                posterIn.value = d.poster_url || '';
                const pp = document.getElementById('edit-poster-preview');
                if (pp) {
                    pp.querySelector('img').src = d.poster_url || '';
                    pp.style.display = d.poster_url ? 'block' : 'none';
                }
            }
            if (backdropIn) {
                backdropIn.value = d.backdrop_url || '';
                const bp = document.getElementById('edit-backdrop-preview');
                if (bp) {
                    bp.querySelector('img').src = d.backdrop_url || '';
                    bp.style.display = d.backdrop_url ? 'block' : 'none';
                }
            }

            _hideEditMsg();
            modal.classList.remove('hidden');
        });

        // ── Save ───────────────────────────────────────────────────────────────
        const saveBtn = document.getElementById('saveEditModal');
        if (saveBtn) {
            saveBtn.addEventListener('click', async () => {
                const body = {
                    title:          document.getElementById('edit-title').value.trim() || null,
                    original_title: document.getElementById('edit-original-title').value.trim() || null,
                    sort_title:     document.getElementById('edit-sort-title').value.trim() || null,
                    tagline:        document.getElementById('edit-tagline').value.trim() || null,
                    overview:       document.getElementById('edit-overview').value.trim() || null,
                    release_date:   document.getElementById('edit-release-date').value || null,
                    tmdb_id:        parseInt(document.getElementById('edit-tmdb').value) || null,
                    imdb_id:        document.getElementById('edit-imdb').value.trim() || null,
                    tvdb_id:        parseInt(document.getElementById('edit-tvdb').value) || null,
                    poster_url:     posterIn  ? (posterIn.value.trim()   || null) : null,
                    backdrop_url:   backdropIn ? (backdropIn.value.trim() || null) : null,
                    genres:         _editGenres,
                    cast:           _editCast,
                    refresh_from_tmdb: false,
                };

                saveBtn.disabled = true;
                saveBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">hourglass_top</span> Saving…';

                try {
                    const r = await fetch(`/api/v1/media/${mediaId}`, {
                        method: 'PATCH',
                        credentials: 'include',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(body)
                    });
                    if (!r.ok) {
                        const err = await r.json().catch(() => ({}));
                        _showEditMsg(err.detail || 'Save failed.', false);
                        saveBtn.disabled = false;
                        saveBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">save</span> Save Changes';
                    } else {
                        window.location.reload();
                    }
                } catch {
                    _showEditMsg('Request failed.', false);
                    saveBtn.disabled = false;
                    saveBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">save</span> Save Changes';
                }
            });
        }

        // ── Delete button ──────────────────────────────────────────────────────
        setupDelete(mediaId, currentMetadata.title || 'This item', () => {
            window.location.href = isShow ? '/libraries/shows' : '/libraries/movies';
        });

    } catch (e) {
        console.error('Admin check failed', e);
    }
}

/**
 * Wire up #deleteBtn to show a confirmation modal and call DELETE /api/v1/media/{id}.
 */
function setupDelete(id, label, onSuccess) {
    const deleteBtn = document.getElementById("deleteBtn");
    const deleteModal = document.getElementById("deleteModal");
    const cancelBtn = document.getElementById("cancelDeleteBtn");
    const confirmBtn = document.getElementById("confirmDeleteBtn");
    const msgEl = document.getElementById("deleteModalMsg");

    if (!deleteBtn || !deleteModal) return;

    deleteBtn.classList.remove("hidden");
    deleteBtn.onclick = () => {
        if (msgEl) msgEl.innerText = `"${label}" will be removed from Arctic Media. Files on disk will NOT be deleted.`;
        deleteModal.classList.remove("hidden");
    };

    if (cancelBtn) cancelBtn.onclick = () => deleteModal.classList.add("hidden");

    if (confirmBtn) {
        // Clone to clear any previous listeners
        const freshBtn = confirmBtn.cloneNode(true);
        confirmBtn.parentNode.replaceChild(freshBtn, confirmBtn);
        freshBtn.onclick = async () => {
            freshBtn.disabled = true;
            freshBtn.innerText = "Removing...";
            try {
                const r = await fetch(`/api/v1/media/${id}`, {
                    method: 'DELETE',
                    credentials: 'include'
                });
                if (!r.ok) throw new Error(`Delete failed: ${r.status}`);
                deleteModal.classList.add("hidden");
                if (onSuccess) onSuccess();
            } catch (e) {
                alert("Failed to remove: " + e.message);
                freshBtn.disabled = false;
                freshBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">delete</span> Remove';
            }
        };
    }
}

// Show Specific Logic
async function loadSeasons() {
    const res = await fetch(`/api/v1/media/shows/${mediaId}/seasons`, {
        credentials: 'include'
    });
    const seasons = await res.json();

    if (els.seasonsCount) els.seasonsCount.innerText = `${seasons.length} Seasons`;

    if (!els.seasonList) return;

    els.seasonList.innerHTML = seasons.map((s, index) => {
        return `<button onclick="loadEpisodes(${s.id}, ${s.season_number})"
            class="chip season-btn ${index === 0 ? 'active' : ''}">
            Season ${s.season_number}
        </button>`;
    }).join("");

    if (seasons.length > 0) {
        loadEpisodes(seasons[0].id, seasons[0].season_number);
    }
}

window.loadEpisodes = async function (seasonId, seasonNum) {
    document.querySelectorAll(".season-btn").forEach(btn => {
        btn.classList.remove('active');
        if (btn.innerText.trim() === `Season ${seasonNum}`) {
            btn.classList.add('active');
        }
    });

    if (els.seasonTitle) els.seasonTitle.innerText = `Season ${seasonNum}`;
    if (els.episodeGrid) els.episodeGrid.innerHTML = "Loading...";

    const res = await fetch(`/api/v1/media/seasons/${seasonId}/episodes`, {
        credentials: 'include'
    });
    const episodes = await res.json();

    if (els.episodeGrid) {
        // Detect admin to show per-episode delete buttons
        let isAdmin = false;
        try {
            const meR = await fetch('/api/v1/auth/me', { credentials: 'include' });
            if (meR.ok) { const me = await meR.json(); isAdmin = !!me.is_superuser; }
        } catch (_) { }

        els.episodeGrid.innerHTML = episodes.map(ep => {
            const still = ep.poster_url || '';
            const safeTitle = (ep.title || 'Episode ' + ep.episode_number).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
            const delBtn = isAdmin
                ? `<button class="ep-delete-btn" onclick="deleteEpisode(event,${ep.id},'${safeTitle}',${seasonId},${seasonNum})" title="Remove episode">
                    <span class="material-icons" style="font-size:14px;">close</span>
                   </button>`
                : '';
            return `
            <div class="episode-card" id="ep-card-${ep.id}" onclick="playEpisode(${ep.id})">
                <div class="episode-thumb">
                    <img src="${still}" alt="" loading="lazy">
                    <div class="episode-num">E${ep.episode_number}</div>
                    <div class="episode-play-icon"><span class="material-icons">play_arrow</span></div>
                    <div class="episode-cast-icon" onclick="openCastModal(${ep.id}, event)" title="Cast to Roku" style="position:absolute;bottom:8px;right:8px;background:rgba(0,0,0,0.6);border-radius:50%;padding:4px;display:flex;cursor:pointer;z-index:10;transition:background 0.2s;"><span class="material-icons" style="font-size:1.2rem;color:#fff;">cast</span></div>
                    <div class="ep-progress-bar hidden" id="ep-prog-${ep.id}" style="position:absolute;bottom:0;left:0;right:0;height:3px;background:rgba(255,255,255,0.2);"><div class="ep-progress-fill" style="height:100%;background:var(--primary);width:0%;"></div></div>
                    ${delBtn}
                </div>
                <div class="episode-info">
                    <div class="episode-title">${ep.title || 'Episode ' + ep.episode_number}</div>
                    <p class="episode-desc">${ep.overview || 'No description.'}</p>
                </div>
            </div>`;
        }).join('');

        // Overlay progress bars for watched episodes
        const epIds = episodes.map(ep => ep.id);
        if (epIds.length > 0) {
            try {
                const progRes = await fetch('/api/v1/history/batch', {
                    method: 'POST',
                    credentials: 'include',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ media_ids: epIds })
                });
                if (progRes.ok) {
                    const progMap = await progRes.json();
                    for (const [idStr, prog] of Object.entries(progMap)) {
                        const bar = document.getElementById(`ep-prog-${idStr}`);
                        if (!bar) continue;
                        if (prog.completed) {
                            bar.querySelector('.ep-progress-fill').style.width = '100%';
                            bar.querySelector('.ep-progress-fill').style.background = 'rgba(255,255,255,0.4)';
                        } else if (prog.duration_seconds > 0) {
                            const pct = Math.min(100, prog.position_seconds / prog.duration_seconds * 100);
                            bar.querySelector('.ep-progress-fill').style.width = `${pct}%`;
                        }
                        bar.classList.remove('hidden');
                    }
                }
            } catch (e) { /* progress bars are cosmetic, don't block */ }
        }
    }
}

// --- Casting Logic ---
let targetCastMediaId = null;

window.openCastModal = async function (id, event) {
    if (event) event.stopPropagation();
    targetCastMediaId = id;
    const modal = document.getElementById('castModal');
    const list = document.getElementById('cast-device-list');

    modal.classList.remove('hidden');
    list.innerHTML = 'Scanning local network for Roku devices... <span class="material-icons" style="vertical-align:middle;font-size:16px;">search</span>';

    try {
        const res = await fetch('/api/v1/remote/devices', { credentials: 'include' });
        if (!res.ok) throw new Error("Failed to scan devices");
        const devices = await res.json();

        if (devices.length === 0) {
            list.innerHTML = '<span style="color:var(--text-muted)">No Roku devices found. Ensure they are powered on and connected to the same Wi-Fi network.</span>';
            return;
        }

        list.innerHTML = devices.map(d => `
            <button class="btn btn-ghost" style="justify-content:flex-start;text-align:left;padding:12px;display:flex;align-items:center;gap:12px;background:var(--surface-2);border-radius:var(--radius);width:100%;border:none;cursor:pointer;" onclick="castToDevice('${d.ip}')">
                <span class="material-icons" style="color:var(--primary)">tv</span>
                <div style="display:flex;flex-direction:column;">
                    <span style="font-weight:600;font-size:1rem;color:var(--text-color)">${d.name}</span>
                    <span style="font-size:0.8rem;color:var(--text-muted)">${d.ip}</span>
                </div>
            </button>
        `).join('');
    } catch (e) {
        list.innerHTML = `<span class="badge" style="background:var(--danger)">Error: ${e.message}</span>`;
    }
}

window.castToDevice = async function (ip) {
    if (!targetCastMediaId) return;
    const list = document.getElementById('cast-device-list');
    list.innerHTML = 'Sending Cast instruction to TV...';
    try {
        const res = await fetch('/api/v1/remote/cast', {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ device_ip: ip, media_id: targetCastMediaId })
        });
        if (!res.ok) throw new Error('Cast command rejected');
        document.getElementById('castModal').classList.add('hidden');
    } catch (e) {
        list.innerHTML = `<span class="badge" style="background:var(--danger)">Failed to cast: ${e.message}</span>`;
    }
}

/** Delete an episode card inline (no page reload, removes card from DOM). */
window.deleteEpisode = async function (event, epId, epLabel, seasonId, seasonNum) {
    event.stopPropagation(); // don't trigger playEpisode
    if (!confirm(`Remove "${epLabel}" from library? Files on disk will NOT be deleted.`)) return;
    try {
        const r = await fetch(`/api/v1/media/${epId}`, {
            method: 'DELETE',
            credentials: 'include'
        });
        if (!r.ok) throw new Error(`Delete failed: ${r.status}`);
        // Reload the season so counts stay correct
        await loadEpisodes(seasonId, seasonNum);
    } catch (e) {
        alert("Failed to remove episode: " + e.message);
    }
}

// --- Watch Progress Helpers ---

let _progressInterval = null;
let _progressMediaId = null;

function _fmtTime(sec) {
    sec = Math.floor(sec);
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    return `${m}:${String(s).padStart(2, '0')}`;
}

async function _fetchProgress(id) {
    try {
        const res = await fetch(`/api/v1/history/${id}`, { credentials: 'include' });
        if (res.ok) return await res.json();
    } catch (e) { }
    return null;
}

async function _saveProgress(id) {
    if (!plyr || !id || plyr.currentTime < 2) return;
    try {
        await fetch(`/api/v1/history/${id}`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                position_seconds: plyr.currentTime,
                duration_seconds: plyr.duration > 0 ? plyr.duration : null,
            })
        });
    } catch (e) { console.warn('Progress save failed', e); }
}

function _startProgressTracking(id) {
    _stopProgressTracking();
    _progressMediaId = id;
    _progressInterval = setInterval(() => _saveProgress(id), 10000);
}

function _stopProgressTracking() {
    if (_progressInterval) {
        clearInterval(_progressInterval);
        _progressInterval = null;
    }
}

// On movie pages: show Resume button if there's saved progress
async function _checkMovieResume() {
    if (isShow) return;
    const prog = await _fetchProgress(mediaId);
    if (prog && !prog.completed && prog.position_seconds > 5) {
        const btn = document.getElementById('resumeBtn');
        const txt = document.getElementById('resumeBtnText');
        if (btn && txt) {
            txt.textContent = `Resume from ${_fmtTime(prog.position_seconds)}`;
            btn.classList.remove('hidden');
        }
    }
}

// --- Video Player Logic ---

let plyr;

// Lazy getters — always resolved at call time, never at parse time
function _getPlayerEl() { return document.getElementById("video-player"); }
function _getContainerEl() { return document.getElementById("video-container"); }

// Wire up the 'ended' event once the DOM is ready
document.addEventListener("DOMContentLoaded", () => {
    const pe = _getPlayerEl();
    if (pe) {
        pe.addEventListener('ended', () => {
            if (_progressMediaId) _saveProgress(_progressMediaId);
            _stopProgressTracking();
        });
    }
});

// Save progress when navigating away (keepalive ensures the request completes)
window.addEventListener('beforeunload', () => {
    if (!_progressMediaId || !plyr || plyr.currentTime < 2) return;
    fetch(`/api/v1/history/${_progressMediaId}`, {
        method: 'POST',
        keepalive: true,
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            position_seconds: plyr.currentTime,
            duration_seconds: plyr.duration > 0 ? plyr.duration : null,
        }),
    });
});

window.playMovie = async function () {
    playStream(mediaId, null, null, null, 0);
}

window.resumeMovie = async function () {
    const prog = await _fetchProgress(mediaId);
    const t = (prog && !prog.completed && prog.position_seconds > 5) ? prog.position_seconds : 0;
    playStream(mediaId, null, null, null, t);
}

window.playEpisode = async function (episodeId) {
    if (event) event.stopPropagation();
    const prog = await _fetchProgress(episodeId);
    const t = (prog && !prog.completed && prog.position_seconds > 5) ? prog.position_seconds : 0;
    playStream(episodeId, null, null, null, t);
}

// Global state to prevent infinite loops
let currentMediaId = null;
let currentQuality = 0; // 0, 720, 480 (int)
let currentAidx = 0;
let currentSidx = null;

async function playStream(id, qualityStr = null, aidx = null, sidx = null, startTime = 0) {
    const token = await getValidStreamToken();
    if (!token) {
        alert("Login required.");
        window.location.href = "/login";
        return;
    }

    // Normalize inputs
    // qualityStr: "720p" or null
    let targetQInt = 0;
    if (qualityStr === "720p") targetQInt = 720;
    if (qualityStr === "480p") targetQInt = 480;

    let targetA = aidx !== null ? parseInt(aidx) : 0;
    let targetS = sidx !== null ? parseInt(sidx) : null;

    // Check if redundant
    if (id === currentMediaId && targetQInt === currentQuality && targetA === currentAidx && targetS === currentSidx && startTime === 0) {
        console.log("Skipping redundant reload.");
        return;
    }

    // Update State
    currentMediaId = id;
    currentQuality = targetQInt;
    currentAidx = targetA;
    currentSidx = targetS;

    // 1. Show Player UI
    const videoContainer = _getContainerEl();
    const playerElement  = _getPlayerEl();
    if (videoContainer) {
        videoContainer.style.display = "block";
        videoContainer.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    // 2. Fetch Metadata for Tracks
    let info = { audio_tracks: [], subtitle_tracks: [] };
    try {
        let infoUrl = `/api/v1/stream/${id}/info?token=${token}`;
        if (window.currentFileId) infoUrl += `&file_id=${window.currentFileId}`;
        const res = await fetch(infoUrl, { credentials: 'include' });
        if (res.ok) info = await res.json();
    } catch (e) { console.error("Meta fetch error", e); }

    // 4. Tear down previous player
    if (plyr) plyr.destroy();
    if (window.hls) { window.hls.destroy(); window.hls = null; }

    const _subTrack  = (targetS !== null && info.subtitle_tracks) ? info.subtitle_tracks[targetS] : null;
    const _isImageSub = _subTrack ? !!_subTrack.is_image : false;
    const _isTextSub  = _subTrack ? !_subTrack.is_image  : false;

    // Direct-play: H.264/AAC MP4 → native <video> with byte-range requests.
    // No FFmpeg, no segments, instant seek, zero startup delay.
    const _canDirect = !!info.can_direct_play && targetA === 0 && targetS === null && !qualityStr;

    const posterSrc = els.backdrop ? els.backdrop.src : "";

    if (!playerElement) return;

    // ── Initialize Plyr shell first so controls are ready ────────────────────
    plyr = new Plyr(playerElement, {
        controls: [
            'play-large', 'play', 'progress', 'current-time', 'duration', 'mute',
            'volume', 'captions', 'settings', 'pip', 'airplay', 'fullscreen'
        ],
        settings: ['quality', 'speed'],
        duration: info.duration,
        quality: { default: 0, options: [0], forced: true, onChange: () => {} },
        tooltips: { controls: true, seek: true }
    });
    plyr.poster = posterSrc;

    // ── Helper: start HLS (used as primary path and as direct-play fallback) ─
    function _startHls() {
        let srcUrl = `/api/v1/stream/${id}/master.m3u8?token=${token}&aidx=${targetA}`;
        if (window.currentFileId) srcUrl += `&file_id=${window.currentFileId}`;
        if (targetS !== null && _isImageSub) srcUrl += `&sidx=${targetS}&stype=image`;
        if (startTime > 2) srcUrl += `&t=${Math.floor(startTime)}`;

        if (Hls.isSupported()) {
            const hls = new Hls(_makeHlsConfig(startTime));
            hls.loadSource(srcUrl);
            hls.attachMedia(playerElement);
            window.hls = hls;

            hls.on(Hls.Events.MANIFEST_PARSED, () => {
                if (startTime > 0) playerElement.currentTime = startTime;
                playerElement.play().catch(e => console.log('Autoplay blocked', e));
                _startProgressTracking(id);
                if (_isTextSub) {
                    let vttUrl = `/api/v1/stream/${id}/subtitle.vtt?sidx=${targetS}&token=${token}`;
                    if (window.currentFileId) vttUrl += `&file_id=${window.currentFileId}`;
                    _loadVttTrack(vttUrl);
                }
            });

            hls.on(Hls.Events.ERROR, (event, data) => {
                if (data.fatal) {
                    if (data.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad();
                    else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
                    else hls.destroy();
                }
            });
        } else if (playerElement.canPlayType('application/vnd.apple.mpegurl')) {
            // Safari native HLS
            playerElement.src = srcUrl;
            playerElement.addEventListener('canplay', function onCp() {
                playerElement.removeEventListener('canplay', onCp);
                if (startTime > 0) playerElement.currentTime = startTime;
                playerElement.play();
                _startProgressTracking(id);
            });
        }
    }

    if (_canDirect) {
        // ── Direct-play path ─────────────────────────────────────────────────
        let directUrl = `/api/v1/stream/${id}?token=${token}`;
        if (window.currentFileId) directUrl += `&file_id=${window.currentFileId}`;

        playerElement.addEventListener('canplay', function onCp() {
            playerElement.removeEventListener('canplay', onCp);
            if (startTime > 0) playerElement.currentTime = startTime;
            playerElement.play().catch(e => console.log('Autoplay blocked', e));
            _startProgressTracking(id);
        }, { once: true });

        // If the browser can't play the file directly, fall back to HLS silently.
        playerElement.addEventListener('error', function onErr() {
            playerElement.removeEventListener('error', onErr);
            console.warn('[Arctic] Direct-play failed, falling back to HLS');
            playerElement.removeAttribute('src');
            playerElement.load();
            _startHls();
        }, { once: true });

        playerElement.src = directUrl;
        playerElement.load();
        console.log('[Arctic] Direct-play active');
    } else {
        _startHls();
    }

    // --- Custom UI Injectors (Audio/Sub Selectors) ---
    setupMenuInjection(info, id, qualityStr, targetA, targetS);
}

let menuObserver = null;

function setupMenuInjection(info, mediaId, qualityStr, aidx, sidx) {
    const menuContainer = document.querySelector('.plyr__menu__container');
    if (!menuContainer) return;

    // Disconnect old observer if exists
    if (menuObserver) menuObserver.disconnect();

    const inject = () => {
        // Target the "home" pane. 
        const homePane = menuContainer.querySelector('div > div');
        if (!homePane) return;

        // CRITICAL FIX: Remove existing ones to ensure event listeners get FRESH closures (mediaId, aidx, sidx)
        const oldAudio = homePane.querySelector('#plyr-custom-audio');
        if (oldAudio) oldAudio.remove();

        const oldSubs = homePane.querySelector('#plyr-custom-sub');
        if (oldSubs) oldSubs.remove();

        // Common Style for the select element
        const selectStyle = "background: rgba(0,0,0,0.5); color: #fff; border: 1px solid #444; text-align: right; width: 130px; outline: none; cursor: pointer; padding: 2px 4px; border-radius: 4px; font-size: 13px;";

        // --- Audio Selector Row ---
        if (info.audio_tracks.length > 0) {
            const row = document.createElement("div");
            row.id = "plyr-custom-audio";
            row.className = "plyr__control";
            row.style.cssText = "display: flex; justify-content: space-between; align-items: center; padding: 7px 10px; cursor: default;";

            const label = document.createElement("span");
            label.innerText = "Audio";
            row.appendChild(label);

            const select = document.createElement("select");
            select.className = "plyr__menu__value";
            select.style.cssText = selectStyle;

            select.innerHTML = info.audio_tracks.map((t, i) =>
                `<option value="${i}" ${i == aidx ? 'selected' : ''} style="color: black;">${t.language.toUpperCase()} (${t.codec})</option>`
            ).join("");

            select.onchange = (e) => {
                const val = parseInt(e.target.value);
                if (!isNaN(val)) playStream(mediaId, qualityStr, val, sidx, plyr ? plyr.currentTime : 0);
            };

            row.appendChild(select);
            homePane.insertBefore(row, homePane.firstChild);
        }

        // --- Burn-In Subtitle Selector Row ---
        if (info.subtitle_tracks.length > 0) {
            const row = document.createElement("div");
            row.id = "plyr-custom-sub";
            row.className = "plyr__control";
            row.style.cssText = "display: flex; justify-content: space-between; align-items: center; padding: 7px 10px; cursor: default;";

            const label = document.createElement("span");
            label.innerText = "Subtitles";
            row.appendChild(label);

            const select = document.createElement("select");
            select.style.cssText = selectStyle;

            let html = `<option value="off" style="color: black;">Off</option>`;
            info.subtitle_tracks.forEach((t, i) => {
                const typeLabel = t.is_image ? "(Img)" : "(Text)";
                const sel = (i === sidx) ? "selected" : "";
                html += `<option value="${i}" ${sel} style="color: black;">${t.language.toUpperCase()} ${typeLabel}</option>`;
            });

            select.innerHTML = html;
            select.onchange = async (e) => {
                const val = e.target.value;
                const newSidx = val === "off" ? null : parseInt(val);
                const newTrack = newSidx !== null ? info.subtitle_tracks[newSidx] : null;

                if (newTrack && !newTrack.is_image) {
                    // Text sub: extract + render as WebVTT — no stream restart, no black screen
                    _removeVttTracks();
                    currentSidx = newSidx;
                    const tok = await getStreamToken();
                    let vttUrl = `/api/v1/stream/${mediaId}/subtitle.vtt?sidx=${newSidx}&token=${tok}`;
                    if (window.currentFileId) vttUrl += `&file_id=${window.currentFileId}`;
                    _loadVttTrack(vttUrl);
                } else {
                    // Image sub or "off": reload stream (burn-in / clean)
                    _removeVttTracks();
                    playStream(mediaId, qualityStr, aidx, newSidx, plyr ? plyr.currentTime : 0);
                }
            };

            row.appendChild(select);
            homePane.insertBefore(row, homePane.firstChild);
        }
    };

    // Run once immediately
    inject();

    // Watch for menu rebuilds
    menuObserver = new MutationObserver(() => {
        // Prevent infinite loop by disconnecting while we modify DOM
        menuObserver.disconnect();
        inject();
        menuObserver.observe(menuContainer, { childList: true, subtree: true });
    });
    menuObserver.observe(menuContainer, { childList: true, subtree: true });
}

// ── WebVTT subtitle helpers ──────────────────────────────────────────────────
// Plyr v3 intercepts addtrack events and resets mode to "disabled", so we
// bypass the browser TextTrack API entirely and render cues in a <div> overlay.

let _vttCues = [], _vttOverlay = null, _vttRafId = null;

function _ensureVttOverlay() {
    if (_vttOverlay) return _vttOverlay;
    const wrapper = document.querySelector('.plyr') || (playerElement && playerElement.parentElement);
    if (!wrapper) return null;
    const ov = document.createElement('div');
    ov.id = '__arctic_sub_overlay';
    ov.style.cssText = [
        'position:absolute', 'bottom:12%', 'left:0', 'width:100%',
        'text-align:center', 'pointer-events:none', 'z-index:9999',
        'font-size:1.4em', 'line-height:1.4', 'color:#fff',
        'text-shadow:0 0 4px #000,0 0 4px #000', 'padding:0 8%',
        'white-space:pre-line'
    ].join(';');
    wrapper.style.position = 'relative';
    wrapper.appendChild(ov);
    _vttOverlay = ov;
    return ov;
}

function _vttTimeToSec(s) {
    const p = s.trim().split(':');
    if (p.length === 3) return +p[0] * 3600 + +p[1] * 60 + parseFloat(p[2]);
    if (p.length === 2) return +p[0] * 60 + parseFloat(p[1]);
    return parseFloat(p[0]);
}

function _parseVtt(text) {
    const cues = [];
    const blocks = text.replace(/\r\n/g, '\n').split(/\n{2,}/);
    for (const block of blocks) {
        const lines = block.trim().split('\n');
        // Find the timing line (contains " --> ")
        let timingIdx = lines.findIndex(l => l.includes(' --> '));
        if (timingIdx < 0) continue;
        const timing = lines[timingIdx].split(' --> ');
        if (timing.length < 2) continue;
        const start = _vttTimeToSec(timing[0]);
        const end   = _vttTimeToSec(timing[1].split(' ')[0]); // strip cue settings
        const textLines = lines.slice(timingIdx + 1).filter(l => l.trim());
        if (!textLines.length) continue;
        // Strip VTT tags like <b>, <i>, <c.color>, timestamps
        const html = textLines.join('\n').replace(/<[^>]+>/g, '');
        cues.push({ start, end, text: html });
    }
    return cues;
}

function _vttRenderLoop() {
    const ov = _vttOverlay;
    if (!ov || !playerElement) return;
    const t = playerElement.currentTime;
    const active = _vttCues.filter(c => t >= c.start && t < c.end);
    ov.textContent = active.map(c => c.text).join('\n');
    _vttRafId = requestAnimationFrame(_vttRenderLoop);
}

async function _loadVttTrack(vttUrl) {
    if (!playerElement) return;
    _removeVttTracks();
    try {
        const res = await fetch(vttUrl);
        if (!res.ok) return;
        const text = await res.text();
        _vttCues = _parseVtt(text);
        const ov = _ensureVttOverlay();
        if (ov) _vttRafId = requestAnimationFrame(_vttRenderLoop);
    } catch (e) {
        console.warn('[Subs] Failed to load VTT overlay:', e);
    }
}

function _removeVttTracks() {
    if (_vttRafId) { cancelAnimationFrame(_vttRafId); _vttRafId = null; }
    _vttCues = [];
    if (_vttOverlay) { _vttOverlay.textContent = ''; }
    // Also silence any native tracks so they don't double-render
    if (playerElement) {
        for (let i = 0; i < playerElement.textTracks.length; i++) {
            playerElement.textTracks[i].mode = "disabled";
        }
    }
}

window.closePlayer = function () {
    // Save final position before closing
    _saveProgress(_progressMediaId);
    _stopProgressTracking();

    // Reset Globals
    currentMediaId = null;
    currentQuality = 0;
    currentAidx = 0;
    currentSidx = null;

    if (plyr) {
        plyr.pause();
        plyr.source = {}; // Clear source to stop buffering
    }
    if (videoContainer) videoContainer.style.display = "none";
}

// ── Subtitle download ────────────────────────────────────────────────────────

let _subPollTimer = null;

function _subSetState(btn, state) {
    // state: 'idle' | 'pending' | 'active' | 'exists' | 'partial' | 'error'
    const icons = {
        idle:    'subtitles',
        pending: 'hourglass_top',
        active:  'downloading',
        exists:  'subtitles',
        partial: 'subtitles',
        error:   'subtitles',
    };
    const titles = {
        idle:    'Download subtitles',
        pending: 'Queued\u2026',
        active:  'Downloading\u2026',
        exists:  'Subtitles ready',
        partial: 'Some subtitles missing \u2014 click to retry',
        error:   'Download failed \u2014 click to retry',
    };
    btn.querySelector('.material-icons').textContent = icons[state] || 'subtitles';
    btn.title = titles[state] || 'Download subtitles';
    btn.disabled = (state === 'pending' || state === 'active');
    btn.style.opacity = (state === 'exists') ? '0.5' : '1';
}

function _subPoll(mediaId, btn) {
    if (_subPollTimer) clearInterval(_subPollTimer);
    _subPollTimer = setInterval(async () => {
        try {
            const res = await fetch('/api/v1/subtitles/' + mediaId + '/status', { credentials: 'include' });
            if (!res.ok) return;
            const data = await res.json();
            const overall = data.overall; // 'none','active','partial','exists'
            if (overall === 'active') {
                _subSetState(btn, 'active');
            } else {
                // Download finished (or failed with none/partial)
                clearInterval(_subPollTimer);
                _subPollTimer = null;
                _subSetState(btn, overall === 'exists' ? 'exists' : (overall === 'partial' ? 'partial' : 'idle'));
            }
        } catch (_) { /* ignore poll errors */ }
    }, 4000);
}

window.requestSubtitles = async function () {
    const btn = document.getElementById('subtitleBtn');
    const mediaId = document.getElementById('media-id')?.value;
    if (!mediaId || !btn) return;

    _subSetState(btn, 'pending');

    try {
        const res = await fetch('/api/v1/subtitles/' + mediaId + '/download', {
            method: 'POST',
            credentials: 'include',
        });
        if (!res.ok) {
            _subSetState(btn, 'error');
            return;
        }
        _subSetState(btn, 'active');
        _subPoll(mediaId, btn);
    } catch (_) {
        _subSetState(btn, 'error');
    }
};

// Check status on page load, reflect it on the button, and auto-download if missing.
(async function _initSubtitleBtn() {
    const btn = document.getElementById('subtitleBtn');
    const mediaId = document.getElementById('media-id')?.value;
    if (!btn || !mediaId) return;
    try {
        const res = await fetch('/api/v1/subtitles/' + mediaId + '/status', { credentials: 'include' });
        if (!res.ok) return;
        const data = await res.json();
        const overall = data.overall;

        if (overall === 'active') {
            _subSetState(btn, 'active');
            _subPoll(mediaId, btn);
        } else if (overall === 'exists') {
            _subSetState(btn, 'exists');
        } else if (overall === 'partial') {
            _subSetState(btn, 'partial');
            // Kick off background download for the missing ones
            fetch('/api/v1/subtitles/' + mediaId + '/download', {
                method: 'POST', credentials: 'include'
            }).then(r => { if (r.ok) { _subSetState(btn, 'active'); _subPoll(mediaId, btn); } });
        } else if (overall === 'none') {
            // No subtitles yet — kick off a background download automatically.
            // The service de-dupes so this is safe to call on every page open.
            fetch('/api/v1/subtitles/' + mediaId + '/download', {
                method: 'POST', credentials: 'include'
            }).then(r => { if (r.ok) { _subSetState(btn, 'active'); _subPoll(mediaId, btn); } });
        }
    } catch (_) { /* ignore */ }
})();
