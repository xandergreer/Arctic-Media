// Arctic Media – Admin Server Tab

function _fmtBytes(bytes) {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

async function loadServer() {
    const el = document.getElementById('server-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;

    try {
        const res = await fetch('/api/v1/admin/server', { headers: getAuthHeaders() });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderServer(data);
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load server stats.</p>
        </div>`;
    }
}

function renderServer(data) {
    const el = document.getElementById('server-content');
    const t = data.totals;

    // --- Summary row ---
    const summaryCards = [
        { icon: 'movie', label: 'Movies', value: t.movies },
        { icon: 'tv', label: 'Shows', value: t.shows },
        { icon: 'video_library', label: 'Episodes', value: t.episodes },
        { icon: 'folder', label: 'Total Files', value: t.files },
        { icon: 'storage', label: 'Media Size', value: _fmtBytes(t.total_bytes) },
        { icon: 'database', label: 'Database', value: _fmtBytes(data.db_size_bytes) },
    ].map(c => `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.1rem 1.25rem;display:flex;align-items:center;gap:0.875rem;">
            <span class="material-icons" style="font-size:1.5rem;color:var(--primary);flex-shrink:0;">${c.icon}</span>
            <div>
                <div style="font-size:1.25rem;font-weight:700;line-height:1.2;">${c.value}</div>
                <div style="font-size:0.75rem;color:var(--text-muted);margin-top:0.1rem;">${c.label}</div>
            </div>
        </div>`).join('');

    // --- Library cards ---
    const libCards = data.libraries.map(lib => {
        const typeIcon = lib.type === 'movies' ? 'movie' : 'tv';
        const typeLabel = lib.type === 'movies' ? 'Movies' : 'TV Shows';
        const itemLabel = lib.type === 'movies'
            ? `${lib.movie_count} movie${lib.movie_count !== 1 ? 's' : ''}`
            : `${lib.show_count} show${lib.show_count !== 1 ? 's' : ''} · ${lib.episode_count} episode${lib.episode_count !== 1 ? 's' : ''}`;

        let diskBar = '';
        if (lib.disk) {
            const usedPct = Math.round(lib.disk.used_bytes / lib.disk.total_bytes * 100);
            const color = usedPct > 90 ? '#f87171' : usedPct > 70 ? '#fb923c' : 'var(--primary)';
            diskBar = `
            <div style="margin-top:0.875rem;padding-top:0.875rem;border-top:1px solid var(--border);">
                <div style="display:flex;justify-content:space-between;font-size:0.75rem;color:var(--text-muted);margin-bottom:0.4rem;">
                    <span>Disk usage</span>
                    <span>${_fmtBytes(lib.disk.used_bytes)} / ${_fmtBytes(lib.disk.total_bytes)} · ${_fmtBytes(lib.disk.free_bytes)} free</span>
                </div>
                <div style="height:5px;background:rgba(255,255,255,0.08);border-radius:3px;">
                    <div style="height:100%;width:${usedPct}%;background:${color};border-radius:3px;transition:width 0.6s ease;"></div>
                </div>
            </div>`;
        }

        return `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.25rem;">
            <div style="display:flex;align-items:flex-start;gap:0.75rem;margin-bottom:0.875rem;">
                <span class="material-icons" style="font-size:1.4rem;color:var(--primary);margin-top:1px;">${typeIcon}</span>
                <div style="flex:1;min-width:0;">
                    <div style="font-weight:600;font-size:0.95rem;">${lib.name}</div>
                    <div style="font-size:0.75rem;color:var(--text-muted);margin-top:0.1rem;">${typeLabel}</div>
                </div>
                <div style="text-align:right;flex-shrink:0;">
                    <div style="font-weight:600;font-size:0.9rem;">${_fmtBytes(lib.total_bytes)}</div>
                    <div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.1rem;">${lib.file_count} file${lib.file_count !== 1 ? 's' : ''}</div>
                </div>
            </div>
            <div style="font-size:0.8rem;color:var(--text-muted);background:var(--surface-2);border-radius:var(--radius-sm);padding:0.4rem 0.6rem;font-family:monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${lib.path}">${lib.path}</div>
            <div style="margin-top:0.6rem;font-size:0.82rem;color:var(--text-sub);">${itemLabel}</div>
            ${diskBar}
        </div>`;
    }).join('');

    el.innerHTML = `
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:1rem;margin-bottom:2rem;">
            ${summaryCards}
        </div>

        <h3 style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin-bottom:1rem;">Libraries</h3>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:1.25rem;">
            ${libCards || '<p style="color:var(--text-muted)">No libraries configured.</p>'}
        </div>`;
}
