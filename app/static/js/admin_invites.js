// Arctic Media – Admin Invites Tab

async function loadInvites() {
    const el = document.getElementById('invites-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;
    try {
        const res = await fetch('/api/v1/admin/invites', { headers: getAuthHeaders() });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderInvites(data);
    } catch (e) {
        el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
            <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">error_outline</span>
            <p>Failed to load invite data.</p>
        </div>`;
    }
}

function renderInvites(data) {
    const el = document.getElementById('invites-content');
    const origin = window.location.origin;

    // --- Registration toggle ---
    const toggleChecked = data.open_registration ? 'checked' : '';
    const toggleStatus = data.open_registration
        ? '<span style="color:#4ade80;font-weight:600;">Open</span> — anyone can register'
        : '<span style="color:#fb923c;font-weight:600;">Invite only</span> — invite code required';

    const toggleRow = `
    <div style="display:flex;align-items:center;justify-content:space-between;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.1rem 1.25rem;margin-bottom:2rem;">
        <div>
            <div style="font-weight:600;font-size:0.95rem;margin-bottom:0.2rem;">Registration Mode</div>
            <div style="font-size:0.82rem;color:var(--text-muted);">${toggleStatus}</div>
        </div>
        <label style="position:relative;display:inline-block;width:46px;height:26px;flex-shrink:0;cursor:pointer;">
            <input type="checkbox" id="reg-toggle" ${toggleChecked}
                style="opacity:0;width:0;height:0;"
                onchange="setOpenRegistration(this.checked)">
            <span id="reg-toggle-track" style="position:absolute;inset:0;border-radius:13px;background:${data.open_registration ? 'var(--primary)' : 'rgba(255,255,255,0.12)'};transition:background 0.2s;">
                <span style="position:absolute;top:3px;left:${data.open_registration ? '23px' : '3px'};width:20px;height:20px;border-radius:50%;background:#fff;transition:left 0.2s;" id="reg-toggle-knob"></span>
            </span>
        </label>
    </div>`;

    // --- Invite list ---
    const rows = data.invites.map(inv => {
        let statusBadge, statusColor;
        if (inv.used_by) {
            statusBadge = `Used by <strong>${inv.used_by}</strong>`;
            statusColor = 'var(--text-muted)';
        } else if (inv.expired) {
            statusBadge = 'Expired';
            statusColor = '#f87171';
        } else {
            statusBadge = '<span style="color:#4ade80;">Active</span>';
            statusColor = 'var(--text-muted)';
        }

        const registerLink = `${origin}/register?code=${inv.code}`;
        const canDelete = !inv.used_by;

        return `
        <div id="invite-row-${inv.id}" style="display:grid;grid-template-columns:1fr auto;align-items:center;gap:1rem;padding:1rem 1.25rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);transition:border-color 0.2s;${inv.used_by || inv.expired ? 'opacity:0.6;' : ''}"
             onmouseenter="this.style.borderColor='var(--border-bright)'"
             onmouseleave="this.style.borderColor='var(--border)'">
            <div style="min-width:0;">
                <div style="display:flex;align-items:center;gap:0.6rem;margin-bottom:0.35rem;flex-wrap:wrap;">
                    <code style="font-size:0.85rem;background:var(--surface-2);padding:0.2rem 0.5rem;border-radius:var(--radius-sm);letter-spacing:0.04em;">${inv.code}</code>
                    <span style="font-size:0.78rem;color:${statusColor};">${statusBadge}</span>
                </div>
                <div style="font-size:0.75rem;color:var(--text-muted);">
                    Created ${inv.created_at ? new Date(inv.created_at).toLocaleDateString() : '—'}
                    ${inv.used_at ? ' · Used ' + new Date(inv.used_at).toLocaleDateString() : ''}
                </div>
                ${!inv.used_by && !inv.expired ? `<div style="margin-top:0.4rem;font-size:0.73rem;color:var(--text-muted);font-family:monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${registerLink}">${registerLink}</div>` : ''}
            </div>
            <div style="display:flex;gap:0.5rem;flex-shrink:0;">
                ${!inv.used_by && !inv.expired ? `
                <button onclick="copyInviteLink('${registerLink}', this)"
                    style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);"
                    onmouseenter="this.style.borderColor='var(--border-bright)';this.style.color='var(--text)'"
                    onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                    <span class="material-icons" style="font-size:13px;">content_copy</span>Copy link
                </button>` : ''}
                ${canDelete ? `
                <button onclick="deleteInvite(${inv.id})"
                    style="display:inline-flex;align-items:center;gap:0.3rem;background:none;border:1px solid var(--border);color:var(--text-muted);border-radius:var(--radius-sm);padding:0.3rem 0.65rem;font-size:0.78rem;cursor:pointer;transition:all 0.15s;font-family:var(--font);"
                    onmouseenter="this.style.borderColor='#f87171';this.style.color='#f87171'"
                    onmouseleave="this.style.borderColor='var(--border)';this.style.color='var(--text-muted)'">
                    <span class="material-icons" style="font-size:13px;">delete</span>Revoke
                </button>` : ''}
            </div>
        </div>`;
    }).join('');

    const emptyState = data.invites.length === 0
        ? `<div style="text-align:center;padding:3rem 2rem;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);color:var(--text-muted);">
               <span class="material-icons" style="font-size:2.5rem;display:block;margin-bottom:0.75rem;">mail_outline</span>
               <p>No invite codes yet. Generate one below.</p>
           </div>`
        : `<div style="display:flex;flex-direction:column;gap:0.75rem;">${rows}</div>`;

    el.innerHTML = `
        ${toggleRow}
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem;">
            <h3 style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin:0;">Invite Codes</h3>
            <button onclick="generateInvite()"
                style="display:inline-flex;align-items:center;gap:0.4rem;background:var(--primary);color:#fff;border:none;border-radius:var(--radius-sm);padding:0.4rem 0.9rem;font-size:0.85rem;font-weight:600;cursor:pointer;font-family:var(--font);transition:opacity 0.15s;"
                onmouseenter="this.style.opacity='0.85'" onmouseleave="this.style.opacity='1'">
                <span class="material-icons" style="font-size:15px;">add</span>Generate
            </button>
        </div>
        ${emptyState}`;
}

async function setOpenRegistration(enabled) {
    // Update toggle visual immediately
    const track = document.getElementById('reg-toggle-track');
    const knob = document.getElementById('reg-toggle-knob');
    if (track) track.style.background = enabled ? 'var(--primary)' : 'rgba(255,255,255,0.12)';
    if (knob) knob.style.left = enabled ? '23px' : '3px';

    try {
        await fetch(`/api/v1/admin/invites/settings?open_registration=${enabled}`, {
            method: 'PATCH',
            headers: getAuthHeaders(),
        });
        // Refresh to update status text
        loadInvites();
    } catch (e) {
        alert('Failed to update setting.');
        loadInvites();
    }
}

async function generateInvite() {
    try {
        const res = await fetch('/api/v1/admin/invites', {
            method: 'POST',
            headers: getAuthHeaders(),
        });
        if (!res.ok) throw new Error();
        loadInvites();
    } catch (e) {
        alert('Failed to generate invite.');
    }
}

async function deleteInvite(inviteId) {
    try {
        const res = await fetch(`/api/v1/admin/invites/${inviteId}`, {
            method: 'DELETE',
            headers: getAuthHeaders(),
        });
        if (!res.ok) throw new Error();
        const row = document.getElementById(`invite-row-${inviteId}`);
        if (row) row.remove();
    } catch (e) {
        alert('Failed to revoke invite.');
    }
}

function copyInviteLink(link, btn) {
    navigator.clipboard.writeText(link).then(() => {
        const orig = btn.innerHTML;
        btn.innerHTML = '<span class="material-icons" style="font-size:13px;">check</span>Copied!';
        btn.style.color = '#4ade80';
        btn.style.borderColor = '#4ade80';
        setTimeout(() => {
            btn.innerHTML = orig;
            btn.style.color = '';
            btn.style.borderColor = '';
        }, 2000);
    });
}
