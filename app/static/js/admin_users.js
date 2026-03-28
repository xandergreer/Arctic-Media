// Arctic Media – Admin Users Tab

function _fmtWatchTime(seconds) {
    if (!seconds || seconds < 60) return '< 1 min';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h === 0) return `${m}m`;
    return `${h}h ${m}m`;
}

function _timeAgo(isoStr) {
    if (!isoStr) return 'Never';
    const diff = Math.floor((Date.now() - new Date(isoStr).getTime()) / 1000);
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 86400 * 30) return `${Math.floor(diff / 86400)}d ago`;
    return new Date(isoStr).toLocaleDateString();
}

async function loadUsers() {
    const el = document.getElementById('users-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;

    try {
        const res = await fetch('/api/v1/admin/users', { headers: getAuthHeaders() });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderUsers(data.users);
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load users.</p>
        </div>`;
    }
}

function renderUsers(users) {
    const el = document.getElementById('users-content');

    if (users.length === 0) {
        el.innerHTML = `<div style="text-align:center;padding:5rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:3rem;display:block;margin-bottom:1rem;">person_off</span>
            <p>No users found.</p>
        </div>`;
        return;
    }

    const rows = users.map(u => {
        const initial = u.username.charAt(0).toUpperCase();
        const adminBadge = u.is_superuser
            ? `<span style="font-size:0.68rem;background:rgba(139,92,246,0.15);border:1px solid rgba(139,92,246,0.35);color:#a78bfa;padding:0.1rem 0.45rem;border-radius:var(--radius-pill);font-weight:600;margin-left:0.4rem;">Admin</span>`
            : '';
        const youBadge = u.is_self
            ? `<span style="font-size:0.68rem;background:var(--blue-glow);border:1px solid var(--border-bright);color:var(--blue-300);padding:0.1rem 0.45rem;border-radius:var(--radius-pill);margin-left:0.4rem;">You</span>`
            : '';

        const joined = u.created_at ? new Date(u.created_at).toLocaleDateString() : '—';

        const promoteLabel = u.is_superuser ? 'Demote' : 'Promote';
        const promoteIcon = u.is_superuser ? 'arrow_downward' : 'arrow_upward';
        const actionBtns = u.is_self ? '' : `
            <button onclick="toggleSuperuser(${u.id}, '${u.username}')"
                style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);"
                onmouseenter="this.style.borderColor='var(--border-bright)';this.style.color='var(--text)'"
                onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                <span class="material-icons" style="font-size:13px;">${promoteIcon}</span>${promoteLabel}
            </button>
            <button onclick="deleteUser(${u.id}, '${u.username}')"
                style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);"
                onmouseenter="this.style.borderColor='#f87171';this.style.color='#f87171'"
                onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                <span class="material-icons" style="font-size:13px;">delete</span>Delete
            </button>`;

        return `
        <div id="user-row-${u.id}" style="display:grid;grid-template-columns:1fr auto auto auto;align-items:center;gap:1.25rem;padding:1rem 1.25rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);transition:border-color 0.2s;"
             onmouseenter="this.style.borderColor='var(--border-bright)'"
             onmouseleave="this.style.borderColor='var(--border)'">

            <!-- User info -->
            <div style="display:flex;align-items:center;gap:0.75rem;min-width:0;">
                <div style="width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,var(--blue-700),var(--blue-500));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:1rem;flex-shrink:0;">
                    ${initial}
                </div>
                <div style="min-width:0;">
                    <div style="font-weight:600;font-size:0.92rem;">
                        ${u.username}${adminBadge}${youBadge}
                    </div>
                    <div style="font-size:0.75rem;color:var(--text-muted);margin-top:0.1rem;">Joined ${joined}</div>
                </div>
            </div>

            <!-- Watch stats -->
            <div style="text-align:center;flex-shrink:0;">
                <div style="font-size:0.88rem;font-weight:600;">${_fmtWatchTime(u.watch_seconds)}</div>
                <div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.1rem;">Watch time</div>
            </div>

            <!-- Last active -->
            <div style="text-align:center;flex-shrink:0;">
                <div style="font-size:0.88rem;font-weight:600;">${_timeAgo(u.last_active)}</div>
                <div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.1rem;">Last active</div>
            </div>

            <!-- Actions -->
            <div style="display:flex;gap:0.5rem;flex-shrink:0;">
                ${actionBtns}
            </div>
        </div>`;
    }).join('');

    el.innerHTML = `<div style="display:flex;flex-direction:column;gap:0.75rem;">${rows}</div>`;
}

async function toggleSuperuser(userId, username) {
    if (!confirm(`${username} will have their admin status toggled. Continue?`)) return;
    try {
        const res = await fetch(`/api/v1/admin/users/${userId}/superuser`, {
            method: 'PATCH',
            headers: getAuthHeaders(),
        });
        if (!res.ok) {
            const err = await res.json();
            alert(err.detail || 'Failed.');
            return;
        }
        loadUsers();
    } catch (e) {
        alert('Request failed.');
    }
}

async function deleteUser(userId, username) {
    if (!confirm(`Delete "${username}"? This will permanently remove their account and all watch history.`)) return;
    try {
        const res = await fetch(`/api/v1/admin/users/${userId}`, {
            method: 'DELETE',
            headers: getAuthHeaders(),
        });
        if (!res.ok) {
            const err = await res.json();
            alert(err.detail || 'Failed.');
            return;
        }
        // Remove row from DOM without full reload
        const row = document.getElementById(`user-row-${userId}`);
        if (row) row.remove();
    } catch (e) {
        alert('Request failed.');
    }
}
