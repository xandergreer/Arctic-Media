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
            <button onclick="resetPassword(${u.id}, '${u.username}')"
                style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);"
                onmouseenter="this.style.borderColor='var(--border-bright)';this.style.color='var(--text)'"
                onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                <span class="material-icons" style="font-size:13px;">lock_reset</span>Reset PW
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

    const createBtn = `
        <div style="display:flex;justify-content:flex-end;margin-bottom:1rem;">
            <button onclick="showCreateUserModal()"
                style="display:inline-flex;align-items:center;gap:0.4rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);padding:0.45rem 1rem;font-size:0.85rem;font-weight:600;cursor:pointer;font-family:var(--font);">
                <span class="material-icons" style="font-size:15px;">person_add</span>Create User
            </button>
        </div>`;
    el.innerHTML = createBtn + `<div style="display:flex;flex-direction:column;gap:0.75rem;">${rows}</div>`;
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

function showCreateUserModal() {
    const existing = document.getElementById('create-user-modal');
    if (existing) existing.remove();

    const modal = document.createElement('div');
    modal.id = 'create-user-modal';
    modal.style.cssText = `position:fixed;inset:0;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;z-index:9999;`;
    modal.innerHTML = `
        <div style="background:var(--surface);border:1px solid var(--border-bright);border-radius:var(--radius-lg);padding:2rem;max-width:420px;width:90%;box-shadow:0 8px 32px rgba(0,0,0,0.5);">
            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:1.5rem;">
                <span class="material-icons" style="color:var(--primary);">person_add</span>
                <h3 style="margin:0;font-size:1.1rem;">Create User</h3>
            </div>
            <div class="form-group" style="margin-bottom:1rem;">
                <label style="font-size:0.82rem;color:var(--text-muted);display:block;margin-bottom:0.3rem;">Username</label>
                <input id="cu-username" type="text" class="form-control" placeholder="e.g. john" autocomplete="off">
            </div>
            <div class="form-group" style="margin-bottom:1rem;">
                <label style="font-size:0.82rem;color:var(--text-muted);display:block;margin-bottom:0.3rem;">Password</label>
                <input id="cu-password" type="password" class="form-control" placeholder="At least 6 characters" autocomplete="new-password">
            </div>
            <div style="display:flex;align-items:center;gap:0.5rem;margin-bottom:1.5rem;">
                <input type="checkbox" id="cu-admin" style="accent-color:var(--primary);width:15px;height:15px;">
                <label for="cu-admin" style="font-size:0.88rem;cursor:pointer;">Make admin</label>
            </div>
            <div id="cu-error" style="font-size:0.83rem;color:#f87171;margin-bottom:0.75rem;display:none;"></div>
            <div style="display:flex;gap:0.75rem;">
                <button onclick="document.getElementById('create-user-modal').remove()"
                    style="flex:1;padding:0.6rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);font-size:0.9rem;cursor:pointer;font-family:var(--font);">
                    Cancel
                </button>
                <button onclick="createUser()"
                    style="flex:1;padding:0.6rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);font-size:0.9rem;font-weight:600;cursor:pointer;font-family:var(--font);">
                    Create
                </button>
            </div>
        </div>`;
    document.body.appendChild(modal);
    modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
    setTimeout(() => document.getElementById('cu-username')?.focus(), 50);
}

async function createUser() {
    const username = document.getElementById('cu-username').value.trim();
    const password = document.getElementById('cu-password').value;
    const isAdmin  = document.getElementById('cu-admin').checked;
    const errEl    = document.getElementById('cu-error');

    if (!username || !password) { errEl.textContent = 'Please fill in all fields.'; errEl.style.display = 'block'; return; }
    if (password.length < 6)    { errEl.textContent = 'Password must be at least 6 characters.'; errEl.style.display = 'block'; return; }

    try {
        const params = new URLSearchParams({ username, password, is_superuser: isAdmin });
        const res = await fetch(`/api/v1/admin/users?${params}`, {
            method: 'POST',
            headers: getAuthHeaders(),
        });
        if (!res.ok) {
            const err = await res.json();
            errEl.textContent = err.detail || 'Failed.';
            errEl.style.display = 'block';
            return;
        }
        document.getElementById('create-user-modal').remove();
        loadUsers();
    } catch (e) {
        errEl.textContent = 'Request failed.';
        errEl.style.display = 'block';
    }
}

async function resetPassword(userId, username) {
    if (!confirm(`Reset password for "${username}"? A new temporary password will be generated.`)) return;
    try {
        const res = await fetch(`/api/v1/admin/users/${userId}/reset-password`, {
            method: 'POST',
            headers: getAuthHeaders(),
        });
        if (!res.ok) {
            const err = await res.json();
            alert(err.detail || 'Failed.');
            return;
        }
        const data = await res.json();
        // Show modal with the new password so admin can copy it
        showPasswordModal(data.username, data.new_password);
    } catch (e) {
        alert('Request failed.');
    }
}

function showPasswordModal(username, password) {
    const existing = document.getElementById('pw-reset-modal');
    if (existing) existing.remove();

    const modal = document.createElement('div');
    modal.id = 'pw-reset-modal';
    modal.style.cssText = `position:fixed;inset:0;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;z-index:9999;`;
    modal.innerHTML = `
        <div style="background:var(--surface);border:1px solid var(--border-bright);border-radius:var(--radius-lg);padding:2rem;max-width:420px;width:90%;box-shadow:0 8px 32px rgba(0,0,0,0.5);">
            <div style="display:flex;align-items:center;gap:0.75rem;margin-bottom:1.25rem;">
                <span class="material-icons" style="color:var(--primary);">lock_reset</span>
                <h3 style="margin:0;font-size:1.1rem;">Password Reset</h3>
            </div>
            <p style="color:var(--text-muted);font-size:0.88rem;margin:0 0 1rem;">
                New temporary password for <strong style="color:var(--text);">${username}</strong>. Share this with the user.
            </p>
            <div style="display:flex;align-items:center;gap:0.5rem;background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-sm);padding:0.6rem 1rem;margin-bottom:1.5rem;">
                <code id="pw-reset-value" style="flex:1;font-size:1.1rem;letter-spacing:0.05em;color:var(--text);">${password}</code>
                <button onclick="
                    navigator.clipboard.writeText('${password}');
                    this.textContent='Copied!';
                    this.style.color='var(--primary)';
                    setTimeout(()=>{this.innerHTML='<span class=\\'material-icons\\' style=\\'font-size:16px;\\'>content_copy</span>';this.style.color='';},1500);"
                    style="background:none;border:none;cursor:pointer;color:var(--text-muted);display:flex;align-items:center;padding:0;">
                    <span class="material-icons" style="font-size:16px;">content_copy</span>
                </button>
            </div>
            <button onclick="document.getElementById('pw-reset-modal').remove()"
                style="width:100%;padding:0.6rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);font-size:0.9rem;font-weight:600;cursor:pointer;font-family:var(--font);">
                Done
            </button>
        </div>`;
    document.body.appendChild(modal);
    modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
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
