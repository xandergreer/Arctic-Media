// Arctic Media – Admin History Tab

async function loadHistory() {
    const el = document.getElementById('history-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;
    try {
        const res = await fetch('/api/v1/admin/history', { headers: getAuthHeaders() });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderHistory(data);
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load history.</p>
        </div>`;
    }
}

function _fmtSeconds(s) {
    s = Math.floor(s || 0);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m`;
    return `${s}s`;
}

function _timeAgo(iso) {
    if (!iso) return '—';
    const diff = Math.floor((Date.now() - new Date(iso)) / 1000);
    if (diff < 60) return 'just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
    return new Date(iso).toLocaleDateString();
}

function renderHistory(data) {
    const el = document.getElementById('history-content');
    const { totals, most_watched_movies, most_watched_shows, users } = data;

    // ── Stat cards ───────────────────────────────────────────────────────────────
    const statCards = [
        { icon: 'schedule',      label: 'Total Watch Time', value: _fmtSeconds(totals.total_seconds) },
        { icon: 'play_circle',   label: 'Total Plays',      value: totals.total_plays.toLocaleString() },
        { icon: 'check_circle',  label: 'Completed',        value: totals.total_completed.toLocaleString() },
        { icon: 'group',         label: 'Watchers',         value: totals.unique_watchers.toLocaleString() },
    ].map(c => `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.1rem 1.25rem;flex:1;min-width:0;">
            <div style="display:flex;align-items:center;gap:0.5rem;color:var(--text-muted);font-size:0.75rem;font-weight:600;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:0.5rem;">
                <span class="material-icons" style="font-size:15px;">${c.icon}</span>${c.label}
            </div>
            <div style="font-size:1.5rem;font-weight:700;">${c.value}</div>
        </div>`).join('');

    // ── Most watched helpers ─────────────────────────────────────────────────────
    function _watchedRow(item, countLabel) {
        const poster = item.poster_url
            ? `<img src="${item.poster_url}" style="width:36px;height:54px;object-fit:cover;border-radius:4px;flex-shrink:0;" loading="lazy">`
            : `<div style="width:36px;height:54px;background:var(--surface-2);border-radius:4px;flex-shrink:0;display:flex;align-items:center;justify-content:center;"><span class="material-icons" style="font-size:16px;color:var(--text-muted);">movie</span></div>`;
        return `
        <div style="display:flex;align-items:center;gap:0.75rem;padding:0.6rem 0;border-bottom:1px solid var(--border);">
            ${poster}
            <div style="flex:1;min-width:0;">
                <div style="font-size:0.85rem;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${item.title}</div>
                <div style="font-size:0.75rem;color:var(--text-muted);">${_fmtSeconds(item.total_seconds)} watched</div>
            </div>
            <div style="font-size:0.78rem;color:var(--primary);font-weight:600;white-space:nowrap;">${countLabel}</div>
        </div>`;
    }

    const movieRows = most_watched_movies.length
        ? most_watched_movies.map(m => _watchedRow(m, `${m.play_count} play${m.play_count !== 1 ? 's' : ''}`)).join('')
        : `<div style="padding:2rem 0;text-align:center;color:var(--text-muted);font-size:0.85rem;">No movie history yet.</div>`;

    const showRows = most_watched_shows.length
        ? most_watched_shows.map(s => _watchedRow(s, `${s.ep_count} ep${s.ep_count !== 1 ? 's' : ''}`)).join('')
        : `<div style="padding:2rem 0;text-align:center;color:var(--text-muted);font-size:0.85rem;">No show history yet.</div>`;

    function _sectionCard(title, icon, content) {
        return `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.1rem 1.25rem;flex:1;min-width:0;">
            <div style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin-bottom:0.75rem;display:flex;align-items:center;gap:0.4rem;">
                <span class="material-icons" style="font-size:15px;">${icon}</span>${title}
            </div>
            ${content}
        </div>`;
    }

    // ── Per-user history ─────────────────────────────────────────────────────────
    const userSections = users.map((u, idx) => {
        const rows = u.history.map(item => {
            const barColor = item.completed ? '#4ade80' : 'var(--primary)';
            const epChip = item.ep_label
                ? `<span style="font-size:0.7rem;background:var(--surface-2);padding:0.1rem 0.4rem;border-radius:var(--radius-sm);margin-left:0.4rem;color:var(--text-muted);">${item.ep_label}</span>`
                : '';
            const timeStr = item.duration_seconds
                ? `${_fmtSeconds(item.position_seconds)} / ${_fmtSeconds(item.duration_seconds)}`
                : _fmtSeconds(item.position_seconds);
            return `
            <div style="display:flex;align-items:center;gap:0.75rem;padding:0.55rem 0;border-bottom:1px solid var(--border);">
                <div style="flex:1;min-width:0;">
                    <div style="font-size:0.82rem;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
                        ${item.title}${epChip}
                    </div>
                    <div style="margin-top:0.3rem;display:flex;align-items:center;gap:0.5rem;">
                        <div style="flex:1;height:3px;background:var(--border);border-radius:2px;max-width:140px;">
                            <div style="height:100%;width:${item.progress_pct}%;background:${barColor};border-radius:2px;"></div>
                        </div>
                        <span style="font-size:0.7rem;color:var(--text-muted);">${timeStr}</span>
                    </div>
                </div>
                <div style="font-size:0.72rem;color:var(--text-muted);white-space:nowrap;text-align:right;">
                    ${_timeAgo(item.last_watched_at)}
                </div>
            </div>`;
        }).join('');

        const isEmpty = u.history.length === 0;
        const bodyId = `hist-body-${u.user_id}`;
        const arrowId = `hist-arrow-${u.user_id}`;
        const isOpen = idx === 0;

        return `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);overflow:hidden;">
            <div onclick="toggleHistUser('${bodyId}','${arrowId}')"
                style="display:flex;align-items:center;justify-content:space-between;padding:0.9rem 1.1rem;cursor:pointer;user-select:none;"
                onmouseenter="this.style.background='var(--surface-2)'"
                onmouseleave="this.style.background=''">
                <div style="display:flex;align-items:center;gap:0.75rem;">
                    <div style="width:32px;height:32px;border-radius:50%;background:var(--primary);display:flex;align-items:center;justify-content:center;font-size:0.85rem;font-weight:700;color:#fff;flex-shrink:0;">
                        ${u.username[0].toUpperCase()}
                    </div>
                    <div>
                        <div style="font-size:0.88rem;font-weight:600;">${u.username}</div>
                        <div style="font-size:0.75rem;color:var(--text-muted);">${u.item_count} item${u.item_count !== 1 ? 's' : ''} · ${_fmtSeconds(u.total_seconds)} watched</div>
                    </div>
                </div>
                <span class="material-icons" id="${arrowId}" style="color:var(--text-muted);transition:transform 0.2s;transform:rotate(${isOpen ? '180' : '0'}deg);">expand_more</span>
            </div>
            <div id="${bodyId}" style="display:${isOpen ? 'block' : 'none'};padding:0 1.1rem 0.5rem;">
                ${isEmpty
                    ? `<div style="padding:1.5rem 0;text-align:center;color:var(--text-muted);font-size:0.85rem;">No watch history yet.</div>`
                    : rows}
            </div>
        </div>`;
    }).join('');

    el.innerHTML = `
        <div style="display:flex;gap:1rem;margin-bottom:1.5rem;flex-wrap:wrap;">
            ${statCards}
        </div>

        <div style="display:flex;gap:1rem;margin-bottom:1.5rem;flex-wrap:wrap;">
            ${_sectionCard('Most Watched Movies', 'movie', movieRows)}
            ${_sectionCard('Most Watched Shows', 'tv', showRows)}
        </div>

        <div style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin-bottom:0.75rem;">Per-User History</div>
        <div style="display:flex;flex-direction:column;gap:0.75rem;">
            ${users.length ? userSections : '<div style="text-align:center;padding:3rem;color:var(--text-muted);">No users yet.</div>'}
        </div>`;
}

function toggleHistUser(bodyId, arrowId) {
    const body = document.getElementById(bodyId);
    const arrow = document.getElementById(arrowId);
    const open = body.style.display !== 'none';
    body.style.display = open ? 'none' : 'block';
    arrow.style.transform = open ? 'rotate(0deg)' : 'rotate(180deg)';
}
