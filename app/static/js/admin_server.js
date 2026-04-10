// Arctic Media – Admin Server Tab

function _fmtBytes(bytes) {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function _fmtUptime(secs) {
    const d = Math.floor(secs / 86400);
    const h = Math.floor((secs % 86400) / 3600);
    const m = Math.floor((secs % 3600) / 60);
    if (d > 0) return `${d}d ${h}h ${m}m`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m ${secs % 60}s`;
}

// ─── Live Metrics ──────────────────────────────────────────────────────────────

let _metricsTimer = null;
let _prevNet = null;
let _prevNetTime = null;

function stopServerMetrics() {
    if (_metricsTimer) { clearInterval(_metricsTimer); _metricsTimer = null; }
    _prevNet = null;
    _prevNetTime = null;
}

function _gaugeBar(pct, color) {
    return `
    <div style="height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
        <div style="height:100%;width:${pct}%;background:${color};border-radius:3px;transition:width 0.8s ease;"></div>
    </div>`;
}

function _metricColor(pct) {
    return pct > 90 ? '#f87171' : pct > 70 ? '#fb923c' : 'var(--primary)';
}

async function _refreshMetrics() {
    const panel = document.getElementById('live-metrics-panel');
    if (!panel) { stopServerMetrics(); return; }

    try {
        const res = await fetch('/api/v1/admin/server/metrics', { credentials: 'include' });
        if (!res.ok) {
            panel.innerHTML = `<div style="text-align:center;padding:1.5rem;color:var(--text-muted);font-size:0.85rem;">
                <span class="material-icons" style="font-size:1.5rem;display:block;margin-bottom:0.5rem;color:#f87171;">error_outline</span>
                Metrics endpoint returned ${res.status}
            </div>`;
            stopServerMetrics(); return;
        }
        const d = await res.json();
        if (!d.available) {
            panel.innerHTML = `<div style="text-align:center;padding:1.5rem;color:var(--text-muted);font-size:0.85rem;">
                <span class="material-icons" style="font-size:1.5rem;display:block;margin-bottom:0.5rem;">info_outline</span>
                Live metrics unavailable — psutil not found in this build.
            </div>`;
            stopServerMetrics(); return;
        }

        // Compute network rate (bytes/sec)
        const now = Date.now();
        let netUpStr = '—', netDownStr = '—';
        if (_prevNet && _prevNetTime) {
            const dt = (now - _prevNetTime) / 1000;
            if (dt > 0) {
                netUpStr   = _fmtBytes(Math.max(0, d.net_bytes_sent - _prevNet.sent) / dt) + '/s';
                netDownStr = _fmtBytes(Math.max(0, d.net_bytes_recv - _prevNet.recv) / dt) + '/s';
            }
        }
        _prevNet = { sent: d.net_bytes_sent, recv: d.net_bytes_recv };
        _prevNetTime = now;

        const cpuColor  = _metricColor(d.cpu_pct);
        const ramColor  = _metricColor(d.mem_pct);

        panel.innerHTML = `
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem;">
            <h3 style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin:0;">Live System Metrics</h3>
            <div style="display:flex;align-items:center;gap:0.4rem;font-size:0.75rem;color:var(--text-muted);">
                <span style="width:7px;height:7px;border-radius:50%;background:#4ade80;display:inline-block;animation:pulse 2s infinite;"></span>
                Live · ${_fmtUptime(d.uptime_seconds)} uptime
            </div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin-bottom:1rem;">

            <div style="background:var(--surface-2);border-radius:var(--radius-lg);padding:1rem;">
                <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:0.5rem;">
                    <span style="font-size:0.78rem;color:var(--text-muted);font-weight:600;text-transform:uppercase;letter-spacing:0.05em;">CPU</span>
                    <span style="font-size:1.3rem;font-weight:700;color:${cpuColor};">${d.cpu_pct}%</span>
                </div>
                ${_gaugeBar(d.cpu_pct, cpuColor)}
                <div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.4rem;">${d.cpu_cores_physical} physical · ${d.cpu_cores_logical} logical core${d.cpu_cores_logical !== 1 ? 's' : ''}</div>
            </div>

            <div style="background:var(--surface-2);border-radius:var(--radius-lg);padding:1rem;">
                <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:0.5rem;">
                    <span style="font-size:0.78rem;color:var(--text-muted);font-weight:600;text-transform:uppercase;letter-spacing:0.05em;">RAM</span>
                    <span style="font-size:1.3rem;font-weight:700;color:${ramColor};">${d.mem_pct}%</span>
                </div>
                ${_gaugeBar(d.mem_pct, ramColor)}
                <div style="font-size:0.72rem;color:var(--text-muted);margin-top:0.4rem;">${_fmtBytes(d.mem_used)} used · ${_fmtBytes(d.mem_available)} free · ${_fmtBytes(d.mem_total)} total</div>
            </div>

        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:1rem;">
            <div style="background:var(--surface-2);border-radius:var(--radius-lg);padding:0.9rem 1rem;display:flex;align-items:center;gap:0.75rem;">
                <span class="material-icons" style="font-size:1.3rem;color:var(--primary);">upload</span>
                <div>
                    <div style="font-size:1rem;font-weight:700;">${netUpStr}</div>
                    <div style="font-size:0.72rem;color:var(--text-muted);">Upload · ${_fmtBytes(d.net_bytes_sent)} total</div>
                </div>
            </div>
            <div style="background:var(--surface-2);border-radius:var(--radius-lg);padding:0.9rem 1rem;display:flex;align-items:center;gap:0.75rem;">
                <span class="material-icons" style="font-size:1.3rem;color:var(--primary);">download</span>
                <div>
                    <div style="font-size:1rem;font-weight:700;">${netDownStr}</div>
                    <div style="font-size:0.72rem;color:var(--text-muted);">Download · ${_fmtBytes(d.net_bytes_recv)} total</div>
                </div>
            </div>
        </div>`;
    } catch { /* ignore */ }
}

function _startMetricsPolling() {
    stopServerMetrics();
    _refreshMetrics();
    _metricsTimer = setInterval(_refreshMetrics, 2000);
}


// ─── Static library stats ──────────────────────────────────────────────────────

async function loadServer() {
    const el = document.getElementById('server-content');
    el.innerHTML = `<div style="text-align:center;padding:3rem 2rem;color:var(--text-muted);">
        <span class="material-icons" style="font-size:2rem;display:block;margin-bottom:0.5rem;">hourglass_empty</span>
        <p>Loading…</p>
    </div>`;

    try {
        const res = await fetch('/api/v1/admin/server', { credentials: 'include' });
        if (!res.ok) throw new Error(res.status);
        const data = await res.json();
        renderServer(data);
        _startMetricsPolling();
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

    const summaryCards = [
        { icon: 'movie',         label: 'Movies',      value: t.movies },
        { icon: 'tv',            label: 'Shows',       value: t.shows },
        { icon: 'video_library', label: 'Episodes',    value: t.episodes },
        { icon: 'folder',        label: 'Total Files', value: t.files },
        { icon: 'storage',       label: 'Media Size',  value: _fmtBytes(t.total_bytes) },
        { icon: 'database',      label: 'Database',    value: _fmtBytes(data.db_size_bytes) },
    ].map(c => `
        <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.1rem 1.25rem;display:flex;align-items:center;gap:0.875rem;">
            <span class="material-icons" style="font-size:1.5rem;color:var(--primary);flex-shrink:0;">${c.icon}</span>
            <div>
                <div style="font-size:1.25rem;font-weight:700;line-height:1.2;">${c.value}</div>
                <div style="font-size:0.75rem;color:var(--text-muted);margin-top:0.1rem;">${c.label}</div>
            </div>
        </div>`).join('');

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
        <div id="live-metrics-panel" style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:1.25rem;margin-bottom:2rem;">
            <div style="text-align:center;padding:1.5rem;color:var(--text-muted);font-size:0.85rem;">
                <span class="material-icons" style="font-size:1.5rem;display:block;margin-bottom:0.5rem;animation:spin 1s linear infinite;">sync</span>
                Loading metrics…
            </div>
        </div>

        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:1rem;margin-bottom:2rem;">
            ${summaryCards}
        </div>

        <h3 style="font-size:0.8rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);margin-bottom:1rem;">Libraries</h3>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:1.25rem;">
            ${libCards || '<p style="color:var(--text-muted)">No libraries configured.</p>'}
        </div>`;
}
