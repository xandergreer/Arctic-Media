// Arctic Media – Settings Page

// ─── Scan Progress Panel ───────────────────────────────────────────────────────

let _pollTimer = null;

const _STATUS = {
    pending:  { icon: 'schedule',     color: 'var(--text-muted)', spin: false, label: 'Pending'  },
    scanning: { icon: 'sync',         color: 'var(--primary)',    spin: true,  label: 'Scanning' },
    done:     { icon: 'check_circle', color: '#4ade80',           spin: false, label: 'Done'     },
    error:    { icon: 'error',        color: '#f87171',           spin: false, label: 'Error'    },
};

function _duration(startIso, endIso) {
    if (!startIso || !endIso) return '';
    const secs = Math.round((new Date(endIso) - new Date(startIso)) / 1000);
    if (secs < 60) return `${secs}s`;
    return `${Math.floor(secs / 60)}m ${secs % 60}s`;
}

function _stopPoll() {
    if (_pollTimer) { clearInterval(_pollTimer); _pollTimer = null; }
}

function _getScanPanel() {
    return document.getElementById('scan-progress-panel');
}

function _insertPanel() {
    let panel = _getScanPanel();
    if (panel) return panel;

    panel = document.createElement('div');
    panel.id = 'scan-progress-panel';
    panel.style.cssText = [
        'background:var(--surface-2)',
        'border:1px solid var(--border)',
        'border-radius:var(--radius-lg)',
        'margin-top:1rem',
        'overflow:hidden',
    ].join(';');

    // Insert right after the scan-btn's row div
    const scanBtn = document.getElementById('scan-btn');
    if (scanBtn) {
        const row = scanBtn.parentNode;
        row.insertAdjacentElement('afterend', panel);
    }

    return panel;
}

function _renderPanel(libs, allDone) {
    const panel = _insertPanel();

    const headerIcon = allDone
        ? `<span class="material-icons" style="font-size:16px;color:#4ade80;">check_circle</span>`
        : `<span class="material-icons" style="font-size:16px;color:var(--primary);animation:spin 1s linear infinite;">sync</span>`;

    const reloadLink = allDone
        ? `<a href="" style="font-size:0.78rem;color:var(--primary);text-decoration:none;margin-right:0.75rem;">Reload page</a>`
        : '';

    const rows = libs.map(lib => {
        const s = _STATUS[lib.status] || _STATUS.pending;
        const dur = _duration(lib.started_at, lib.finished_at);
        const spinCss = s.spin ? 'animation:spin 1s linear infinite;' : '';
        const sublabel = lib.status === 'done' && dur ? `Done · ${dur}`
                       : lib.status === 'error'       ? 'Error'
                       : s.label;
        const errLine = lib.error
            ? `<div style="font-size:0.72rem;color:#f87171;margin-top:0.1rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${lib.error}">${lib.error}</div>`
            : '';

        return `
        <div style="display:flex;align-items:center;gap:0.75rem;padding:0.6rem 1.1rem;border-top:1px solid var(--border);">
            <span class="material-icons" style="font-size:18px;color:${s.color};${spinCss}flex-shrink:0;">${s.icon}</span>
            <div style="flex:1;min-width:0;">
                <div style="font-size:0.85rem;font-weight:500;">${lib.library_name}</div>
                ${errLine}
            </div>
            <div style="font-size:0.75rem;color:var(--text-muted);white-space:nowrap;">${sublabel}</div>
        </div>`;
    }).join('');

    panel.innerHTML = `
        <div style="display:flex;align-items:center;justify-content:space-between;padding:0.75rem 1.1rem;">
            <div style="display:flex;align-items:center;gap:0.5rem;font-size:0.85rem;font-weight:600;">
                ${headerIcon}
                ${allDone ? 'Scan complete' : 'Scanning libraries…'}
            </div>
            <div style="display:flex;align-items:center;">
                ${reloadLink}
                <button onclick="dismissScanPanel()" style="background:none;border:none;color:var(--text-muted);cursor:pointer;font-size:0.78rem;padding:0.2rem 0.5rem;border-radius:var(--radius-sm);">Dismiss</button>
            </div>
        </div>
        ${rows}`;
}

function dismissScanPanel() {
    _stopPoll();
    const panel = _getScanPanel();
    if (panel) panel.remove();
}

async function _poll() {
    try {
        const res = await fetch('/api/v1/scan/status', { credentials: 'include' });
        if (res.status === 401) { _stopPoll(); return; }
        if (!res.ok) return;
        const data = await res.json();
        const allDone = !data.scanning;
        _renderPanel(data.libraries, allDone);
        if (allDone) _stopPoll();
    } catch (e) { /* ignore transient poll errors */ }
}

function _startPolling(initialLibs) {
    _stopPoll();
    _renderPanel(initialLibs, false);
    _poll(); // immediate first fetch
    _pollTimer = setInterval(_poll, 1500);
}


// ─── Page Init ─────────────────────────────────────────────────────────────────

document.addEventListener("DOMContentLoaded", () => {

    // --- GENERAL SETTINGS ---
    const generalForm = document.getElementById("general-settings-form");
    const customDomainInput = document.getElementById("custom-domain");

    if (customDomainInput) {
        fetch("/api/v1/settings/custom_domain", { credentials: 'include' })
            .then(res => res.ok ? res.json() : { value: "" })
            .then(data => { if (data && data.value) customDomainInput.value = data.value; })
            .catch(() => {});
    }

    if (generalForm) {
        generalForm.addEventListener("submit", async (e) => {
            e.preventDefault();
            const domain = customDomainInput.value.trim();
            const submitBtn = generalForm.querySelector("button[type='submit']");
            const originalText = submitBtn.textContent;
            submitBtn.disabled = true;
            submitBtn.textContent = "Saving...";
            try {
                const res = await fetch("/api/v1/settings", {
                    method: "POST",
                    credentials: 'include',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: "custom_domain", value: domain }),
                });
                if (res.ok) {
                    submitBtn.textContent = "Saved!";
                    setTimeout(() => { submitBtn.textContent = originalText; submitBtn.disabled = false; }, 2000);
                } else {
                    alert("Failed to save settings.");
                    submitBtn.textContent = originalText;
                    submitBtn.disabled = false;
                }
            } catch {
                alert("Error saving settings.");
                submitBtn.textContent = originalText;
                submitBtn.disabled = false;
            }
        });
    }

    // --- ADD LIBRARY ---
    const addLibForm = document.getElementById("add-library-form");
    if (addLibForm) {
        addLibForm.addEventListener("submit", async (e) => {
            e.preventDefault();
            const name = document.getElementById("lib-name").value.trim();
            const path = document.getElementById("folder-path-input").value.trim();
            const type = document.getElementById("lib-type").value;
            if (!path) { alert("Please enter a Path."); return; }
            try {
                const res = await fetch("/api/v1/libraries", {
                    method: "POST",
                    credentials: 'include',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, path, type }),
                });
                if (res.ok) {
                    window.location.reload();
                } else {
                    const err = await res.json();
                    alert("Error: " + (err.detail || "Failed to add library"));
                }
            } catch { alert("Connection failed."); }
        });
    }

    // --- DELETE LIBRARY ---
    document.querySelectorAll('.delete-lib-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const libId = e.currentTarget.getAttribute('data-id');
            if (!confirm('Are you sure? This removes it from the database.')) return;
            try {
                const res = await fetch(`/api/v1/libraries/${libId}`, { method: 'DELETE', credentials: 'include' });
                if (res.ok) window.location.reload();
            } catch { alert('Failed to delete.'); }
        });
    });

    // --- RESCAN SINGLE LIBRARY ---
    async function _triggerLibraryScan(libId, force = false) {
        const url = `/api/v1/scan/library/${libId}${force ? '?force=true' : ''}`;
        const res = await fetch(url, { method: 'POST', credentials: 'include' });
        const data = await res.json();
        if (data.status === 'already_running') {
            _startPolling(_getScanPanel()
                ? []
                : [{ library_id: parseInt(libId), library_name: data.library || `Library ${libId}`, status: 'scanning', started_at: null, finished_at: null, error: null }]
            );
        } else {
            _startPolling([{
                library_id: data.library_id || parseInt(libId),
                library_name: data.library || `Library ${libId}`,
                status: 'pending',
                started_at: null,
                finished_at: null,
                error: null,
            }]);
        }
    }

    document.querySelectorAll('.rescan-lib-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const libId = e.currentTarget.getAttribute('data-id');
            e.currentTarget.disabled = true;
            try {
                await _triggerLibraryScan(libId, false);
            } catch { alert('Failed to start rescan.'); }
            e.currentTarget.disabled = false;
        });
    });

    document.querySelectorAll('.force-rescan-lib-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const libId = e.currentTarget.getAttribute('data-id');
            if (!confirm('Force rescan ignores the mtime cache and re-checks every folder — useful if files were copied with old timestamps. Continue?')) return;
            e.currentTarget.disabled = true;
            try {
                await _triggerLibraryScan(libId, true);
            } catch { alert('Failed to start force rescan.'); }
            e.currentTarget.disabled = false;
        });
    });

    // --- SCAN ALL ---
    const scanBtn = document.getElementById('scan-btn');
    if (scanBtn) {
        scanBtn.addEventListener('click', async () => {
            scanBtn.disabled = true;
            try {
                const res = await fetch('/api/v1/scan/run', {
                    method: 'POST',
                    credentials: 'include',
                });
                const data = await res.json();

                if (data.status === 'no_libraries') {
                    alert('No libraries configured. Add a library below first.');
                    scanBtn.disabled = false;
                    return;
                }

                if (data.status === 'already_running') {
                    // Attach to in-progress scan — poll will populate the panel
                    _startPolling([]);
                } else {
                    // data.libraries is [{id, name}, ...]
                    const libs = (data.libraries || []).map(l => ({
                        library_id: l.id,
                        library_name: l.name,
                        status: 'pending',
                        started_at: null,
                        finished_at: null,
                        error: null,
                    }));
                    _startPolling(libs);
                }
            } catch (err) {
                console.error(err);
                alert('Failed to start scan — check server connection.');
            }
            scanBtn.disabled = false;
        });
    }

    // Resume polling if a scan is already running (page was reloaded mid-scan)
    (async () => {
        try {
            const res = await fetch('/api/v1/scan/status', { credentials: 'include' });
            if (!res.ok) return;
            const data = await res.json();
            if (data.scanning && data.libraries.length) {
                _startPolling(data.libraries);
            }
        } catch { /* not critical */ }
    })();

    // ─── Change Password ──────────────────────────────────────────────────────────

    const cpForm = document.getElementById('change-password-form');
    if (cpForm) {
        cpForm.addEventListener('submit', async e => {
            e.preventDefault();
            const current = document.getElementById('cp-current').value;
            const newPw   = document.getElementById('cp-new').value;
            const confirm = document.getElementById('cp-confirm').value;
            const msg     = document.getElementById('cp-msg');

            const show = (text, ok) => {
                msg.textContent = text;
                msg.style.color = ok ? 'var(--primary)' : '#f87171';
                msg.style.display = 'block';
            };

            if (!current || !newPw || !confirm) { show('Please fill in all fields.', false); return; }
            if (newPw !== confirm) { show('New passwords do not match.', false); return; }
            if (newPw.length < 6) { show('New password must be at least 6 characters.', false); return; }

            try {
                const res = await fetch('/api/v1/auth/change-password', {
                    method: 'POST',
                    credentials: 'include',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ current_password: current, new_password: newPw }),
                });
                const data = await res.json();
                if (!res.ok) { show(data.detail || 'Failed.', false); return; }
                show('Password updated successfully.', true);
                cpForm.reset();
            } catch (err) {
                show('Request failed.', false);
            }
        });
    }

});
