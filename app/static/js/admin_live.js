// Arctic Media – Admin Live View

const REFRESH_INTERVAL = 10; // seconds
let countdown = REFRESH_INTERVAL;
let refreshTimer = null;
let countdownTimer = null;

const DEVICE_ICONS = {
    desktop: 'computer',
    mobile: 'smartphone',
    tablet: 'tablet',
    tv: 'tv',
    unknown: 'device_unknown',
};

async function loadLive() {
    try {
        const res = await fetch('/api/v1/admin/live', { credentials: 'include' });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderViewers(data.viewers);
    } catch (e) {
        document.getElementById('viewer-grid').innerHTML = `
            <div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
                <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
                <p>Failed to load live data.</p>
            </div>`;
    }
}

function renderViewers(viewers) {
    const grid = document.getElementById('viewer-grid');
    const badge = document.getElementById('viewer-count-badge');

    const count = viewers.length;
    badge.textContent = count === 0 ? 'No viewers' : count === 1 ? '1 watching' : `${count} watching`;
    badge.style.background = count > 0 ? 'rgba(34,197,94,0.15)' : 'var(--blue-glow)';
    badge.style.borderColor = count > 0 ? 'rgba(34,197,94,0.4)' : 'var(--border-bright)';
    badge.style.color = count > 0 ? '#4ade80' : 'var(--blue-300)';

    if (count === 0) {
        grid.innerHTML = `
            <div style="text-align:center;padding:5rem 2rem;background:var(--surface);border-radius:var(--radius-lg);border:1px solid var(--border);">
                <span class="material-icons" style="font-size:3.5rem;color:var(--text-muted);display:block;margin-bottom:1rem;">tv_off</span>
                <h3 style="margin-bottom:0.5rem;">No one is watching right now</h3>
                <p style="color:var(--text-muted);font-size:0.9rem;">Live data refreshes every ${REFRESH_INTERVAL} seconds.</p>
            </div>`;
        return;
    }

    grid.innerHTML = `<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:1.25rem;">
        ${viewers.map(v => viewerCard(v)).join('')}
    </div>`;
}

function viewerCard(v) {
    const initial = v.username.charAt(0).toUpperCase();
    const deviceIcon = DEVICE_ICONS[v.device.type] || 'devices';
    const agoLabel = v.seconds_ago < 5 ? 'just now'
        : v.seconds_ago < 60 ? `${v.seconds_ago}s ago`
        : `${Math.round(v.seconds_ago / 60)}m ago`;

    const progressBar = v.duration_fmt
        ? `<div style="margin-top:0.75rem;">
            <div style="display:flex;justify-content:space-between;font-size:0.75rem;color:var(--text-muted);margin-bottom:0.3rem;">
                <span>${v.position_fmt}</span>
                <span>${v.duration_fmt}</span>
            </div>
            <div style="height:4px;background:rgba(255,255,255,0.1);border-radius:2px;">
                <div style="height:100%;background:var(--primary);border-radius:2px;width:${v.progress_pct}%;transition:width 0.5s ease;"></div>
            </div>
           </div>`
        : `<div style="margin-top:0.5rem;font-size:0.75rem;color:var(--text-muted);">At ${v.position_fmt}</div>`;

    const epBadge = v.ep_label
        ? `<span style="font-size:0.7rem;background:var(--surface-3);padding:0.15rem 0.5rem;border-radius:var(--radius-pill);color:var(--text-muted);margin-left:0.4rem;">${v.ep_label}</span>`
        : '';

    const ipDisplay = v.ip
        ? `<span style="font-family:monospace;font-size:0.75rem;">${v.ip}</span>`
        : `<span style="color:var(--text-muted);font-size:0.75rem;">Unknown IP</span>`;

    const poster = v.poster_url
        ? `<img src="${v.poster_url}" alt="" style="width:100%;height:100%;object-fit:cover;border-radius:var(--radius-sm);">`
        : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:var(--surface-3);border-radius:var(--radius-sm);color:var(--text-muted);">
               <span class="material-icons" style="font-size:2rem;">movie</span>
           </div>`;

    return `
    <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.25rem;display:flex;flex-direction:column;gap:0.75rem;transition:border-color 0.2s;"
         onmouseenter="this.style.borderColor='var(--border-bright)'"
         onmouseleave="this.style.borderColor='var(--border)'">

        <!-- Top row: avatar + user + live indicator -->
        <div style="display:flex;align-items:center;gap:0.75rem;">
            <div style="width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,var(--blue-700),var(--blue-500));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:1rem;flex-shrink:0;">
                ${initial}
            </div>
            <div style="flex:1;min-width:0;">
                <div style="font-weight:600;font-size:0.95rem;">${v.username}</div>
                <div style="font-size:0.75rem;color:var(--text-muted);">${agoLabel}</div>
            </div>
            <div style="display:flex;align-items:center;gap:0.3rem;font-size:0.75rem;color:#4ade80;">
                <span style="width:7px;height:7px;border-radius:50%;background:#4ade80;display:inline-block;animation:pulse-dot 2s infinite;"></span>
                Live
            </div>
        </div>

        <!-- Media row: poster + title + progress -->
        <div style="display:flex;gap:0.875rem;align-items:flex-start;">
            <div style="width:56px;height:84px;flex-shrink:0;">${poster}</div>
            <div style="flex:1;min-width:0;">
                <div style="font-weight:600;font-size:0.9rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">
                    ${v.display_title}${epBadge}
                </div>
                <div style="font-size:0.75rem;color:var(--text-muted);text-transform:capitalize;margin-top:0.15rem;">${v.media_kind}</div>
                ${progressBar}
            </div>
        </div>

        <!-- Device + IP row -->
        <div style="display:flex;align-items:center;justify-content:space-between;padding-top:0.5rem;border-top:1px solid var(--border);">
            <div style="display:flex;align-items:center;gap:0.4rem;color:var(--text-muted);font-size:0.8rem;min-width:0;overflow:hidden;">
                <span class="material-icons" style="font-size:16px;flex-shrink:0;">${deviceIcon}</span>
                <span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${v.device.label}</span>
            </div>
            <div style="display:flex;align-items:center;gap:0.4rem;flex-shrink:0;">
                <span class="material-icons" style="font-size:14px;color:var(--text-muted);">location_on</span>
                ${ipDisplay}
            </div>
        </div>
    </div>`;
}

function startCountdown() {
    clearInterval(countdownTimer);
    countdown = REFRESH_INTERVAL;
    const el = document.getElementById('refresh-countdown');
    countdownTimer = setInterval(() => {
        countdown--;
        if (el) el.textContent = `${countdown}s`;
        if (countdown <= 0) {
            countdown = REFRESH_INTERVAL;
        }
    }, 1000);
}

function startAutoRefresh() {
    clearInterval(refreshTimer);
    refreshTimer = setInterval(() => {
        loadLive();
        startCountdown();
    }, REFRESH_INTERVAL * 1000);
    startCountdown();
}

// Inject the pulse animation
const style = document.createElement('style');
style.textContent = `@keyframes pulse-dot { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:0.5;transform:scale(0.8)} }`;
document.head.appendChild(style);

document.addEventListener('DOMContentLoaded', async () => {
    try {
        const r = await fetch('/api/v1/auth/me', { credentials: 'include' });
        if (!r.ok) { window.location.replace('/'); return; }
        const me = await r.json();
        if (!me.is_superuser) { window.location.replace('/'); return; }
    } catch { window.location.replace('/'); return; }
    loadLive();
    startAutoRefresh();
});
