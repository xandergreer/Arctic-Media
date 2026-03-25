// Arctic Media 2.0 – Home Page

function getAuthHeaders() {
    const v = `; ${document.cookie}`;
    const p = v.split(`; access_token=`);
    if (p.length === 2) return { 'Authorization': `Bearer ${p.pop().split(';').shift()}` };
    return {};
}

document.addEventListener('DOMContentLoaded', async () => {
    const loading = document.getElementById('loading');

    try {
        const [recentRes, continueRes] = await Promise.all([
            fetch('/api/v1/media/recently-added?limit=12', { headers: getAuthHeaders() }),
            fetch('/api/v1/history', { headers: getAuthHeaders() }),
        ]);

        if (!recentRes.ok) throw new Error('Failed to load dashboard');
        const data = await recentRes.json();
        let continueItems = [];
        if (continueRes.ok) {
            const raw = await continueRes.json();
            continueItems = Array.isArray(raw) ? raw : [];
        }

        loading.classList.add('hidden');

        if (continueItems.length > 0) {
            renderContinueRow('continue-row', continueItems);
            document.getElementById('continue-section').classList.remove('hidden');
        }

        if (data.movies && data.movies.length > 0) {
            document.getElementById('movies-section').classList.remove('hidden');
            renderRow('movies-row', data.movies, 'movie');
        }

        if (data.shows && data.shows.length > 0) {
            document.getElementById('tv-section').classList.remove('hidden');
            renderRow('shows-row', data.shows, 'show');
        }

        if ((!data.movies || data.movies.length === 0) && (!data.shows || data.shows.length === 0) && continueItems.length === 0) {
            document.getElementById('empty-state').classList.remove('hidden');
        }

    } catch (e) {
        console.error(e);
        if (loading) loading.innerText = 'Error loading dashboard.';
    }
});

function renderContinueRow(containerId, items) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = items.map(item => {
        const poster = item.poster_url
            ? `<img src="${item.poster_url}" alt="${item.title}" loading="lazy" style="width:100%;height:100%;object-fit:cover;">`
            : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:var(--surface-2);color:var(--text-muted);font-size:2rem;font-weight:700;">${item.title.charAt(0)}</div>`;
        const epLabel = item.kind === 'episode' && item.episode_number ? `<div style="font-size:0.75rem;color:var(--text-muted);">E${item.episode_number}</div>` : '';
        return `
        <div class="media-card h-scroll-item" onclick="window.location.href='${item.link}'" style="width:175px;">
            <div class="poster-wrap" style="position:relative;">
                ${poster}
                <div style="position:absolute;bottom:0;left:0;right:0;height:4px;background:rgba(255,255,255,0.15);">
                    <div style="height:100%;background:var(--primary);width:${item.progress_pct}%;"></div>
                </div>
            </div>
            <div class="media-info">
                <div class="media-title">${item.title}</div>
                ${epLabel}
            </div>
        </div>`;
    }).join('');
}

function renderRow(containerId, items, kind) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = items.map(item => {
        const link = kind === 'movie' ? `/movie/${item.id}` : `/show/${item.id}`;
        const poster = item.poster_url
            ? `<img src="${item.poster_url}" alt="${item.title}" loading="lazy" style="width:100%;height:100%;object-fit:cover;">`
            : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:var(--surface-2);color:var(--text-muted);font-size:2rem;font-weight:700;">${item.title.charAt(0)}</div>`;

        return `
        <div class="media-card h-scroll-item" onclick="window.location.href='${link}'" style="width:175px;">
            <div class="poster-wrap">${poster}</div>
            <div class="media-info">
                <div class="media-title">${item.title}</div>
                <div class="media-meta">${item.release_date ? new Date(item.release_date).getFullYear() : ''}</div>
            </div>
        </div>`;
    }).join('');
}
