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
        const res = await fetch('/api/v1/admin/users', { credentials: 'include' });
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

function _makeBtnStyle(danger) {
    return `display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);`;
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

    const createBtnDiv = document.createElement('div');
    createBtnDiv.style.cssText = `display:flex;justify-content:flex-end;margin-bottom:1rem;`;
    const createBtn = document.createElement('button');
    createBtn.style.cssText = `display:inline-flex;align-items:center;gap:0.4rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);padding:0.45rem 1rem;font-size:0.85rem;font-weight:600;cursor:pointer;font-family:var(--font);`;
    createBtn.innerHTML = `<span class="material-icons" style="font-size:15px;">person_add</span>`;
    createBtn.appendChild(document.createTextNode('Create User'));
    createBtn.addEventListener('click', showCreateUserModal);
    createBtnDiv.appendChild(createBtn);

    const list = document.createElement('div');
    list.style.cssText = `display:flex;flex-direction:column;gap:0.75rem;`;

    for (const u of users) {
        const joined = u.created_at ? new Date(u.created_at).toLocaleDateString() : '—';

        const row = document.createElement('div');
        row.id = `user-row-${u.id}`;
        row.style.cssText = `display:grid;grid-template-columns:1fr auto auto auto;align-items:center;gap:1.25rem;padding:1rem 1.25rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);transition:border-color 0.2s;`;
        row.addEventListener('mouseenter', () => row.style.borderColor = 'var(--border-bright)');
        row.addEventListener('mouseleave', () => row.style.borderColor = 'var(--border)');

        // User info cell
        const infoCell = document.createElement('div');
        infoCell.style.cssText = `display:flex;align-items:center;gap:0.75rem;min-width:0;`;
        const avatar = document.createElement('div');
        avatar.style.cssText = `width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,var(--blue-700),var(--blue-500));display:flex;align-items:center;justify-content:center;font-weight:700;font-size:1rem;flex-shrink:0;`;
        avatar.textContent = u.username.charAt(0).toUpperCase();
        const nameBlock = document.createElement('div');
        nameBlock.style.minWidth = '0';
        const nameRow = document.createElement('div');
        nameRow.style.cssText = `font-weight:600;font-size:0.92rem;`;
        const nameSpan = document.createElement('span');
        nameSpan.textContent = u.username;
        nameRow.appendChild(nameSpan);
        if (u.is_superuser) {
            const badge = document.createElement('span');
            badge.style.cssText = `font-size:0.68rem;background:rgba(139,92,246,0.15);border:1px solid rgba(139,92,246,0.35);color:#a78bfa;padding:0.1rem 0.45rem;border-radius:var(--radius-pill);font-weight:600;margin-left:0.4rem;`;
            badge.textContent = 'Admin';
            nameRow.appendChild(badge);
        }
        if (u.is_self) {
            const you = document.createElement('span');
            you.style.cssText = `font-size:0.68rem;background:var(--blue-glow);border:1px solid var(--border-bright);color:var(--blue-300);padding:0.1rem 0.45rem;border-radius:var(--radius-pill);margin-left:0.4rem;`;
            you.textContent = 'You';
            nameRow.appendChild(you);
        }
        const joinedDiv = document.createElement('div');
        joinedDiv.style.cssText = `font-size:0.75rem;color:var(--text-muted);margin-top:0.1rem;`;
        joinedDiv.textContent = `Joined ${joined}`;
        nameBlock.appendChild(nameRow);
        nameBlock.appendChild(joinedDiv);
        infoCell.appendChild(avatar);
        infoCell.appendChild(nameBlock);

        // Watch stats cell
        const watchCell = document.createElement('div');
        watchCell.style.cssText = `text-align:center;flex-shrink:0;`;
        watchCell.innerHTML = `<div style="font-size:0.88rem;font-weight:600;">${_fmtWatchTime(u.watch_seconds)}</div><div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.1rem;">Watch time</div>`;

        // Last active cell
        const activeCell = document.createElement('div');
        activeCell.style.cssText = `text-align:center;flex-shrink:0;`;
        activeCell.innerHTML = `<div style="font-size:0.88rem;font-weight:600;">${_timeAgo(u.last_active)}</div><div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.1rem;">Last active</div>`;

        // Actions cell
        const actionsCell = document.createElement('div');
        actionsCell.style.cssText = `display:flex;gap:0.5rem;flex-shrink:0;`;
        if (!u.is_self) {
            const promoteBtn = document.createElement('button');
            promoteBtn.style.cssText = _makeBtnStyle(false);
            promoteBtn.innerHTML = `<span class="material-icons" style="font-size:13px;">${u.is_superuser ? 'arrow_downward' : 'arrow_upward'}</span>`;
            promoteBtn.appendChild(document.createTextNode(u.is_superuser ? 'Demote' : 'Promote'));
            promoteBtn.addEventListener('mouseenter', () => { promoteBtn.style.borderColor = 'var(--border-bright)'; promoteBtn.style.color = 'var(--text)'; });
            promoteBtn.addEventListener('mouseleave', () => { promoteBtn.style.borderColor = 'var(--border)'; promoteBtn.style.color = 'var(--text-muted)'; });
            promoteBtn.addEventListener('click', () => toggleSuperuser(u.id, u.username));

            const resetBtn = document.createElement('button');
            resetBtn.style.cssText = _makeBtnStyle(false);
            resetBtn.innerHTML = `<span class="material-icons" style="font-size:13px;">lock_reset</span>`;
            resetBtn.appendChild(document.createTextNode('Reset PW'));
            resetBtn.addEventListener('mouseenter', () => { resetBtn.style.borderColor = 'var(--border-bright)'; resetBtn.style.color = 'var(--text)'; });
            resetBtn.addEventListener('mouseleave', () => { resetBtn.style.borderColor = 'var(--border)'; resetBtn.style.color = 'var(--text-muted)'; });
            resetBtn.addEventListener('click', () => resetPassword(u.id, u.username));

            const delBtn = document.createElement('button');
            delBtn.style.cssText = _makeBtnStyle(true);
            delBtn.innerHTML = `<span class="material-icons" style="font-size:13px;">delete</span>`;
            delBtn.appendChild(document.createTextNode('Delete'));
            delBtn.addEventListener('mouseenter', () => { delBtn.style.borderColor = '#f87171'; delBtn.style.color = '#f87171'; });
            delBtn.addEventListener('mouseleave', () => { delBtn.style.borderColor = 'var(--border)'; delBtn.style.color = 'var(--text-muted)'; });
            delBtn.addEventListener('click', () => deleteUser(u.id, u.username));

            actionsCell.appendChild(promoteBtn);
            actionsCell.appendChild(resetBtn);
            actionsCell.appendChild(delBtn);
        }

        row.appendChild(infoCell);
        row.appendChild(watchCell);
        row.appendChild(activeCell);
        row.appendChild(actionsCell);
        list.appendChild(row);
    }

    el.innerHTML = '';
    el.appendChild(createBtnDiv);
    el.appendChild(list);
}

async function toggleSuperuser(userId, username) {
    if (!confirm(`${username} will have their admin status toggled. Continue?`)) return;
    try {
        const res = await fetch(`/api/v1/admin/users/${userId}/superuser`, {
            method: 'PATCH',
            credentials: 'include',
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
        const res = await fetch('/api/v1/admin/users', {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password, is_superuser: isAdmin }),
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
            credentials: 'include',
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

    // Build content via DOM to prevent XSS
    const inner = document.createElement('div');
    inner.style.cssText = `background:var(--surface);border:1px solid var(--border-bright);border-radius:var(--radius-lg);padding:2rem;max-width:420px;width:90%;box-shadow:0 8px 32px rgba(0,0,0,0.5);`;

    const header = document.createElement('div');
    header.style.cssText = `display:flex;align-items:center;gap:0.75rem;margin-bottom:1.25rem;`;
    header.innerHTML = `<span class="material-icons" style="color:var(--primary);">lock_reset</span>`;
    const h3 = document.createElement('h3');
    h3.style.cssText = `margin:0;font-size:1.1rem;`;
    h3.textContent = 'Password Reset';
    header.appendChild(h3);

    const desc = document.createElement('p');
    desc.style.cssText = `color:var(--text-muted);font-size:0.88rem;margin:0 0 1rem;`;
    desc.textContent = 'New temporary password for ';
    const strong = document.createElement('strong');
    strong.style.color = 'var(--text)';
    strong.textContent = username;
    desc.appendChild(strong);
    desc.appendChild(document.createTextNode('. Share this with the user.'));

    const pwRow = document.createElement('div');
    pwRow.style.cssText = `display:flex;align-items:center;gap:0.5rem;background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-sm);padding:0.6rem 1rem;margin-bottom:1.5rem;`;
    const code = document.createElement('code');
    code.id = 'pw-reset-value';
    code.style.cssText = `flex:1;font-size:1.1rem;letter-spacing:0.05em;color:var(--text);`;
    code.textContent = password;
    const copyBtn = document.createElement('button');
    copyBtn.style.cssText = `background:none;border:none;cursor:pointer;color:var(--text-muted);display:flex;align-items:center;padding:0;`;
    copyBtn.innerHTML = `<span class="material-icons" style="font-size:16px;">content_copy</span>`;
    copyBtn.addEventListener('click', function() {
        navigator.clipboard.writeText(password);
        this.textContent = 'Copied!';
        this.style.color = 'var(--primary)';
        setTimeout(() => {
            this.innerHTML = `<span class="material-icons" style="font-size:16px;">content_copy</span>`;
            this.style.color = '';
        }, 1500);
    });
    pwRow.appendChild(code);
    pwRow.appendChild(copyBtn);

    const doneBtn = document.createElement('button');
    doneBtn.style.cssText = `width:100%;padding:0.6rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);font-size:0.9rem;font-weight:600;cursor:pointer;font-family:var(--font);`;
    doneBtn.textContent = 'Done';
    doneBtn.addEventListener('click', () => modal.remove());

    inner.appendChild(header);
    inner.appendChild(desc);
    inner.appendChild(pwRow);
    inner.appendChild(doneBtn);
    modal.appendChild(inner);
    document.body.appendChild(modal);
    modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
}

async function deleteUser(userId, username) {
    if (!confirm(`Delete "${username}"? This will permanently remove their account and all watch history.`)) return;
    try {
        const res = await fetch(`/api/v1/admin/users/${userId}`, {
            method: 'DELETE',
            credentials: 'include',
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
