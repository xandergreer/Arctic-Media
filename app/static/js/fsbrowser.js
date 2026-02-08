// Arctic Media 2.0 - File Browser Logic

(() => {
    const modal = document.getElementById('fs-modal');
    const btnOpen = document.getElementById('browse-btn');
    const btnClose = document.getElementById('fs-close');
    const btnSelect = document.getElementById('fs-select');

    // Inputs in the modal
    const rootsSel = document.getElementById('fs-roots');
    const pathInp = document.getElementById('fs-path'); // Hidden or visible input showing current path
    const listEl = document.getElementById('fs-list');
    const bcEl = document.getElementById('fs-bc');

    // The target input on the main page
    const targetInput = document.getElementById('folder-path-input');

    let curPath = '';

    const set = (el, html) => { if (el) el.innerHTML = html; };
    const show = () => modal?.classList.remove('hidden');
    const hide = () => modal?.classList.add('hidden');

    // Helper: Get Cookie (Duplicated from main.js to keep this file self-contained)
    function getCookie(name) {
        const value = `; ${document.cookie}`;
        const parts = value.split(`; ${name}=`);
        if (parts.length === 2) return parts.pop().split(';').shift();
    }

    // Helper: Auth Headers
    function getAuthHeaders() {
        const token = getCookie("access_token");
        return token ? { 'Authorization': `Bearer ${token}` } : {};
    }

    // Fetch API: Get Roots
    async function loadRoots() {
        set(listEl, '<div class="muted" style="color:var(--text-secondary)">Loading drives...</div>');
        try {
            const res = await fetch('/api/v1/system/fs/roots', {
                headers: getAuthHeaders()
            });
            if (!res.ok) throw new Error("Failed to load roots");

            const data = await res.json();
            // data is Array of FSNode: [{path: "C:\\", name: "C:\\", is_dir: true}, ...]

            if (!data.length) {
                set(listEl, '<div class="muted">No drives found</div>');
                return;
            }

            rootsSel.innerHTML = '';

            // Populate Dropdown
            data.forEach(r => {
                const opt = document.createElement('option');
                opt.value = r.path;
                opt.textContent = r.name;
                rootsSel.appendChild(opt);
            });

            // Select first drive and list it
            curPath = data[0].path;
            list(curPath);

        } catch (e) {
            console.error('roots error', e);
            set(listEl, '<div class="muted" style="color:#ef4444">Error loading drives</div>');
        }
    }

    // Build Breadcrumbs
    function breadcrumb(path) {
        if (!bcEl) return;
        bcEl.innerHTML = '';
        if (!path) return;

        // Windows vs Linux separators
        const sep = path.includes('\\') ? '\\' : '/';

        // Split path but keep the root intact (e.g. "C:\" or "/")
        // Simple strategy: just split by separator
        const parts = path.split(/[\\/]+/).filter(Boolean);

        // Reconstruct root
        // If Windows "C:", then "C:\"
        let root = path.match(/^[A-Za-z]:/) ? (parts[0] + sep) : '/';

        const rootBtn = document.createElement('button');
        rootBtn.textContent = root;
        rootBtn.onclick = () => list(root);
        bcEl.appendChild(rootBtn);

        let acc = root;
        // If Linux, parts[0] is "home" etc.
        // If Windows, parts[0] is "C:" which we handled.

        const start = path.match(/^[A-Za-z]:/) ? 1 : 0;

        for (let i = start; i < parts.length; i++) {
            bcEl.appendChild(Object.assign(document.createElement('span'), { textContent: ' › ' }));

            // Rebuild path for this segment
            // Careful with double separators
            const segment = parts[i];

            // Join logic
            const nextPath = acc.endsWith(sep) ? (acc + segment) : (acc + sep + segment);
            acc = nextPath;

            const b = document.createElement('button');
            b.textContent = segment;

            // Closure captures 'acc' at this moment? No, let's allow it to be dynamic or use 'let'
            // We need a stable value for the click handler
            const clickPath = acc;
            b.onclick = () => list(clickPath);
            bcEl.appendChild(b);
        }
    }

    // Fetch API: List Directory
    async function list(path) {
        set(listEl, '<div class="muted" style="color:var(--text-secondary)">Loading...</div>');
        try {
            // Encode path param
            const url = `/api/v1/system/fs/ls?path=${encodeURIComponent(path)}&include_files=false`;
            const res = await fetch(url, {
                headers: getAuthHeaders()
            });

            if (!res.ok) {
                const err = await res.json();
                throw new Error(err.detail || "Failed");
            }

            const data = await res.json();
            // data = { path: "...", entries: [...] }

            curPath = data.path;
            if (pathInp) pathInp.value = curPath;

            breadcrumb(curPath);
            listEl.innerHTML = '';

            // Up Directory Link (if we are deep)
            // Naive check: if length > 3 (C:\) or > 1 (/)
            if (curPath.length > 3) {
                const upDiv = document.createElement('div');
                upDiv.className = 'fs-row';
                upDiv.innerHTML = `<span class="icon">📁</span><button class="link">.. (Up)</button>`;
                // Logic to go up: specific parent calc or just rely on manual handling?
                // Python's os.path.dirname is reliable. In JS:
                const sep = curPath.includes('\\') ? '\\' : '/';
                const parent = curPath.substring(0, curPath.lastIndexOf(sep)) || (sep === '/' ? '/' : (curPath.split(sep)[0] + sep));

                upDiv.onclick = () => list(parent);
                listEl.appendChild(upDiv);
            }

            if (!data.entries.length) {
                set(listEl, '<div class="muted" style="color:var(--text-secondary); padding:0.5rem">No subfolders</div>');
                // Even if empty, we update curPath so user can select THIS folder
            } else {
                for (const e of data.entries) {
                    const row = document.createElement('div');
                    row.className = 'fs-row';
                    row.innerHTML = `<span class="icon">📁</span><span class="link">${e.name}</span>`;
                    row.onclick = () => list(e.path);
                    listEl.appendChild(row);
                }
            }

        } catch (e) {
            console.error('list error', e);
            set(listEl, `<div class="muted" style="color:#ef4444">Error: ${e.message}</div>`);
        }
    }

    // Event Listeners
    if (btnOpen) {
        btnOpen.addEventListener('click', async (e) => {
            e.preventDefault(); // prevent form submit if inside form
            show();
            await loadRoots();
        });
    }

    if (btnClose) btnClose.addEventListener('click', hide);

    if (rootsSel) {
        rootsSel.addEventListener('change', (e) => {
            list(e.target.value);
        });
    }

    if (btnSelect) {
        btnSelect.addEventListener('click', () => {
            if (targetInput) targetInput.value = curPath;
            hide();
        });
    }

    // Close on clicking outside
    if (modal) {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) hide();
        });
    }

})();
