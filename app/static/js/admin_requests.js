// Arctic Media – Admin Requests Tab

function _reqTimeAgo(isoStr) {
    if (!isoStr) return '';
    const diff = Math.floor((Date.now() - new Date(isoStr).getTime()) / 1000);
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 86400 * 30) return `${Math.floor(diff / 86400)}d ago`;
    return new Date(isoStr).toLocaleDateString();
}

async function loadRequests() {
    const el = document.getElementById('requests-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;
    try {
        const res = await fetch('/api/v1/admin/requests', { credentials: 'include' });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderRequests(data);
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load requests.</p>
        </div>`;
    }
}

function renderRequests(requests) {
    const el = document.getElementById('requests-content');
    if (requests.length === 0) {
        el.innerHTML = `<div style="text-align:center;padding:5rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:3rem;display:block;margin-bottom:1rem;">inbox</span>
            <p>No requests yet.</p>
        </div>`;
        return;
    }

    const rows = requests.map(r => {
        const statusColor = r.status === 'fulfilled' ? '#22c55e' : r.status === 'acknowledged' ? '#f97316' : 'var(--text-muted)';
        const statusLabel = r.status === 'fulfilled' ? 'Fulfilled' : r.status === 'acknowledged' ? 'Acknowledged' : 'Pending';

        let actionBtn = '';
        if (r.status === 'pending') {
            actionBtn = `<button onclick="updateRequestStatus(${r.id}, 'acknowledged')"
                style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;font-family:var(--font);transition:all 0.15s;"
                onmouseenter="this.style.borderColor='#f97316';this.style.color='#f97316'"
                onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                <span class="material-icons" style="font-size:13px;">check</span>Acknowledge
            </button>`;
        } else if (r.status === 'acknowledged') {
            actionBtn = `<button onclick="updateRequestStatus(${r.id}, 'fulfilled')"
                style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;font-family:var(--font);transition:all 0.15s;"
                onmouseenter="this.style.borderColor='#22c55e';this.style.color='#22c55e'"
                onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                <span class="material-icons" style="font-size:13px;">done_all</span>Mark Fulfilled
            </button>`;
        }

        const initial = (r.username || '?').charAt(0).toUpperCase();

        return `
        <div id="req-row-${r.id}" style="display:flex;flex-direction:column;gap:0.6rem;padding:1rem 1.25rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);transition:border-color 0.2s;"
             onmouseenter="this.style.borderColor='var(--border-bright)'"
             onmouseleave="this.style.borderColor='var(--border)'">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:1rem;">
                <div style="display:flex;align-items:center;gap:0.6rem;">
                    <div style="width:28px;height:28px;border-radius:50%;background:linear-gradient(135deg,var(--blue-700),var(--blue-500));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:0.8rem;flex-shrink:0;">${initial}</div>
                    <span style="font-weight:600;font-size:0.88rem;">${r.username}</span>
                    <span style="font-size:0.72rem;color:var(--text-muted);">${_reqTimeAgo(r.created_at)}</span>
                </div>
                <span style="font-size:0.72rem;font-weight:700;color:${statusColor};background:${statusColor}22;padding:0.15rem 0.55rem;border-radius:var(--radius-pill);">${statusLabel}</span>
            </div>
            <p style="margin:0;font-size:0.9rem;color:var(--text);line-height:1.5;">${r.message}</p>
            <div style="display:flex;justify-content:flex-end;">${actionBtn}</div>
        </div>`;
    }).join('');

    el.innerHTML = `<div style="display:flex;flex-direction:column;gap:0.75rem;">${rows}</div>`;
}

async function updateRequestStatus(id, status) {
    try {
        const res = await fetch(`/api/v1/admin/requests/${id}`, {
            method: 'PATCH',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ status })
        });
        if (!res.ok) throw new Error((await res.json()).detail || 'Failed');
        loadRequests();
    } catch (e) {
        alert(e.message || 'Failed to update request.');
    }
}
