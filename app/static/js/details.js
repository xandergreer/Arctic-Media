// Arctic Media 2.0 - Details Page Logic

let mediaId, isShow, els;

document.addEventListener("DOMContentLoaded", async () => {
    try {
        const idInput = document.getElementById("media-id");
        if (!idInput) {
            console.error("Media ID input missing");
            return;
        }
        mediaId = idInput.value;
        isShow = document.getElementById("is-show") !== null;

        // DOM Elements
        els = {
            backdrop: document.getElementById("backdrop-img"),
            poster: document.getElementById("poster-img"),
            title: document.getElementById("title"),
            year: document.getElementById("year"),
            overview: document.getElementById("overview"),
            duration: document.getElementById("duration"), // Movie only
            seasonsCount: document.getElementById("seasons-count"), // Show only
            seasonList: document.getElementById("season-list"), // Show only
            episodeGrid: document.getElementById("episodes-grid"), // Show only
            seasonTitle: document.getElementById("season-title") // Show only
        };

        await loadDetails();
        _checkMovieResume();
        if (isShow) {
            await loadSeasons();
        }
    } catch (e) {
        console.error("Failed to load details", e);
        if (els && els.title) els.title.innerText = "Error: " + e.message;
        if (els && els.overview) els.overview.innerText = "Please check console or refresh.";
    }
});

let currentMetadata = {};

async function loadDetails() {
    try {
        // Verify Auth Helper
        if (typeof getAuthHeaders !== "function") {
            throw new Error("Auth helper missing (main.js not loaded?)");
        }

        const res = await fetch(`/api/v1/media/${mediaId}`, {
            headers: getAuthHeaders()
        });
        if (!res.ok) throw new Error(`API Error ${res.status}`);
        const data = await res.json();
        currentMetadata = data; // Store for Edit Modal

        // Check Admin Status and Setup Edit
        checkAdminAndSetupEdit();

        // Update UI
        if (els.title) els.title.innerText = data.title;
        if (els.overview) els.overview.innerText = data.overview || "No overview available.";

        if (data.release_date && els.year) {
            els.year.innerText = new Date(data.release_date).getFullYear();
        }

        if (data.backdrop_url && els.backdrop) els.backdrop.src = data.backdrop_url;
        if (data.poster_url && els.poster) els.poster.src = data.poster_url;

        // Type specific
        if (!isShow && els.duration) {
            els.duration.innerText = "2h 15m"; // TODO: Fetch from file metadata

            // Fetch multiple files (versions/trailers)
            try {
                const fRes = await fetch(`/api/v1/media/${mediaId}/files`, { headers: getAuthHeaders() });
                if (fRes.ok) {
                    const files = await fRes.json();
                    if (files && files.length > 0) {
                        // Sort by size descending (largest is likely the main feature)
                        files.sort((a, b) => b.size_bytes - a.size_bytes);
                        window.currentFileId = files[0].id; // Set default

                        if (files.length > 1) {
                            const container = document.getElementById("file-versions-container");
                            if (container) {
                                container.innerHTML = `<span style="color:var(--text-muted);font-size:0.875rem;margin-right:0.5rem">Versions:</span>`;
                                files.forEach(f => {
                                    const sizeMB = (f.size_bytes / (1024 * 1024)).toFixed(0);
                                    let nameDisp = f.filename;
                                    // Shorten long filenames for UI
                                    if (nameDisp.length > 30) nameDisp = nameDisp.substring(0, 27) + "...";

                                    const isDefault = f.id === window.currentFileId;
                                    const btn = document.createElement("button");
                                    // Using chip + active for styling
                                    btn.className = `badge ${isDefault ? 'active-version' : ''}`;
                                    btn.style.cursor = "pointer";
                                    btn.style.border = "none";
                                    if (isDefault) btn.style.backgroundColor = "var(--primary)";

                                    btn.innerHTML = `${nameDisp} <span style="opacity:0.7;font-size:0.9em;margin-left:4px">(${sizeMB}MB)</span>`;

                                    btn.onclick = () => {
                                        window.currentFileId = f.id;
                                        // Update active state visuals
                                        container.querySelectorAll(".badge").forEach(c => {
                                            c.style.backgroundColor = "";
                                            c.classList.remove("active-version");
                                        });
                                        btn.style.backgroundColor = "var(--primary)";
                                        btn.classList.add("active-version");

                                        // Force player reload on next play
                                        currentMediaId = null;
                                    };
                                    container.appendChild(btn);
                                });
                                container.classList.remove("hidden");
                            }
                        }
                    }
                }
            } catch (e) { console.error("Could not load files", e); }
        }
    } catch (e) {
        throw e; // Propagate to main catch
    }
}

function checkAdminAndSetupEdit() {
    try {
        const token = getCookie("access_token");
        if (!token) return;

        // Simple JWT Parse (Base64)
        const base64Url = token.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(window.atob(base64).split('').map(function (c) {
            return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        }).join(''));
        const payload = JSON.parse(jsonPayload);

        if (payload.is_superuser) {
            const editBtn = document.getElementById("editBtn");
            const modal = document.getElementById("editModal");
            const closeBtn = document.getElementById("closeEditModal");
            const saveBtn = document.getElementById("saveEditModal");

            if (editBtn) {
                editBtn.classList.remove("hidden");
                editBtn.onclick = () => {
                    // Populate Modal
                    document.getElementById("edit-title").value = currentMetadata.title || "";
                    document.getElementById("edit-tmdb").value = (currentMetadata.extra_json && currentMetadata.extra_json.tmdb_id) || "";
                    document.getElementById("edit-poster").value = currentMetadata.poster_url || "";
                    document.getElementById("edit-backdrop").value = currentMetadata.backdrop_url || "";
                    document.getElementById("edit-refresh").checked = false;

                    modal.classList.remove("hidden");
                };
            }

            if (closeBtn) {
                closeBtn.onclick = () => modal.classList.add("hidden");
            }

            // Close on click outside
            window.onclick = (event) => {
                if (event.target == modal) {
                    modal.classList.add("hidden");
                }
                const deleteModal = document.getElementById("deleteModal");
                if (deleteModal && event.target == deleteModal) {
                    deleteModal.classList.add("hidden");
                }
            }

            if (saveBtn) {
                saveBtn.onclick = async () => {
                    const body = {
                        title: document.getElementById("edit-title").value,
                        tmdb_id: parseInt(document.getElementById("edit-tmdb").value) || null,
                        poster_url: document.getElementById("edit-poster").value,
                        backdrop_url: document.getElementById("edit-backdrop").value,
                        refresh_from_tmdb: document.getElementById("edit-refresh").checked
                    };

                    saveBtn.innerText = "Saving...";
                    saveBtn.disabled = true;

                    try {
                        const r = await fetch(`/api/v1/media/${mediaId}`, {
                            method: 'PATCH',
                            headers: {
                                'Content-Type': 'application/json',
                                ...getAuthHeaders()
                            },
                            body: JSON.stringify(body)
                        });

                        if (!r.ok) throw new Error("Update failed");

                        window.location.reload();
                    } catch (e) {
                        alert("Failed to save: " + e.message);
                        saveBtn.innerText = "Save";
                        saveBtn.disabled = false;
                    }
                };
            }

            // --- Wire delete button for the whole movie / show ---
            setupDelete(mediaId, currentMetadata.title || "This item", () => {
                window.location.href = isShow ? "/libraries/shows" : "/libraries/movies";
            });
        }
    } catch (e) {
        console.error("Admin check failed", e);
    }
}

/**
 * Wire up #deleteBtn to show a confirmation modal and call DELETE /api/v1/media/{id}.
 */
function setupDelete(id, label, onSuccess) {
    const deleteBtn = document.getElementById("deleteBtn");
    const deleteModal = document.getElementById("deleteModal");
    const cancelBtn = document.getElementById("cancelDeleteBtn");
    const confirmBtn = document.getElementById("confirmDeleteBtn");
    const msgEl = document.getElementById("deleteModalMsg");

    if (!deleteBtn || !deleteModal) return;

    deleteBtn.classList.remove("hidden");
    deleteBtn.onclick = () => {
        if (msgEl) msgEl.innerText = `"${label}" will be removed from Arctic Media. Files on disk will NOT be deleted.`;
        deleteModal.classList.remove("hidden");
    };

    if (cancelBtn) cancelBtn.onclick = () => deleteModal.classList.add("hidden");

    if (confirmBtn) {
        // Clone to clear any previous listeners
        const freshBtn = confirmBtn.cloneNode(true);
        confirmBtn.parentNode.replaceChild(freshBtn, confirmBtn);
        freshBtn.onclick = async () => {
            freshBtn.disabled = true;
            freshBtn.innerText = "Removing...";
            try {
                const r = await fetch(`/api/v1/media/${id}`, {
                    method: 'DELETE',
                    headers: getAuthHeaders()
                });
                if (!r.ok) throw new Error(`Delete failed: ${r.status}`);
                deleteModal.classList.add("hidden");
                if (onSuccess) onSuccess();
            } catch (e) {
                alert("Failed to remove: " + e.message);
                freshBtn.disabled = false;
                freshBtn.innerHTML = '<span class="material-icons" style="font-size:1rem;">delete</span> Remove';
            }
        };
    }
}

// Show Specific Logic
async function loadSeasons() {
    const res = await fetch(`/api/v1/media/shows/${mediaId}/seasons`, {
        headers: getAuthHeaders()
    });
    const seasons = await res.json();

    if (els.seasonsCount) els.seasonsCount.innerText = `${seasons.length} Seasons`;

    if (!els.seasonList) return;

    els.seasonList.innerHTML = seasons.map((s, index) => {
        return `<button onclick="loadEpisodes(${s.id}, ${s.season_number})"
            class="chip season-btn ${index === 0 ? 'active' : ''}">
            Season ${s.season_number}
        </button>`;
    }).join("");

    if (seasons.length > 0) {
        loadEpisodes(seasons[0].id, seasons[0].season_number);
    }
}

window.loadEpisodes = async function (seasonId, seasonNum) {
    document.querySelectorAll(".season-btn").forEach(btn => {
        btn.classList.remove('active');
        if (btn.innerText.trim() === `Season ${seasonNum}`) {
            btn.classList.add('active');
        }
    });

    if (els.seasonTitle) els.seasonTitle.innerText = `Season ${seasonNum}`;
    if (els.episodeGrid) els.episodeGrid.innerHTML = "Loading...";

    const res = await fetch(`/api/v1/media/seasons/${seasonId}/episodes`, {
        headers: getAuthHeaders()
    });
    const episodes = await res.json();

    if (els.episodeGrid) {
        // Detect admin to show per-episode delete buttons
        let isAdmin = false;
        try {
            const token = getCookie("access_token");
            if (token) {
                const b64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
                const pl = JSON.parse(decodeURIComponent(window.atob(b64).split('').map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join('')));
                isAdmin = pl.is_superuser === true;
            }
        } catch (_) { }

        els.episodeGrid.innerHTML = episodes.map(ep => {
            const still = ep.poster_url || '';
            const safeTitle = (ep.title || 'Episode ' + ep.episode_number).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
            const delBtn = isAdmin
                ? `<button class="ep-delete-btn" onclick="deleteEpisode(event,${ep.id},'${safeTitle}',${seasonId},${seasonNum})" title="Remove episode">
                    <span class="material-icons" style="font-size:14px;">close</span>
                   </button>`
                : '';
            return `
            <div class="episode-card" id="ep-card-${ep.id}" onclick="playEpisode(${ep.id})">
                <div class="episode-thumb">
                    <img src="${still}" alt="" loading="lazy">
                    <div class="episode-num">E${ep.episode_number}</div>
                    <div class="episode-play-icon"><span class="material-icons">play_arrow</span></div>
                    <div class="episode-cast-icon" onclick="openCastModal(${ep.id}, event)" title="Cast to Roku" style="position:absolute;bottom:8px;right:8px;background:rgba(0,0,0,0.6);border-radius:50%;padding:4px;display:flex;cursor:pointer;z-index:10;transition:background 0.2s;"><span class="material-icons" style="font-size:1.2rem;color:#fff;">cast</span></div>
                    <div class="ep-progress-bar hidden" id="ep-prog-${ep.id}" style="position:absolute;bottom:0;left:0;right:0;height:3px;background:rgba(255,255,255,0.2);"><div class="ep-progress-fill" style="height:100%;background:var(--primary);width:0%;"></div></div>
                    ${delBtn}
                </div>
                <div class="episode-info">
                    <div class="episode-title">${ep.title || 'Episode ' + ep.episode_number}</div>
                    <p class="episode-desc">${ep.overview || 'No description.'}</p>
                </div>
            </div>`;
        }).join('');

        // Overlay progress bars for watched episodes
        const epIds = episodes.map(ep => ep.id);
        if (epIds.length > 0) {
            try {
                const progRes = await fetch('/api/v1/history/batch', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', ...getAuthHeaders() },
                    body: JSON.stringify({ media_ids: epIds })
                });
                if (progRes.ok) {
                    const progMap = await progRes.json();
                    for (const [idStr, prog] of Object.entries(progMap)) {
                        const bar = document.getElementById(`ep-prog-${idStr}`);
                        if (!bar) continue;
                        if (prog.completed) {
                            bar.querySelector('.ep-progress-fill').style.width = '100%';
                            bar.querySelector('.ep-progress-fill').style.background = 'rgba(255,255,255,0.4)';
                        } else if (prog.duration_seconds > 0) {
                            const pct = Math.min(100, prog.position_seconds / prog.duration_seconds * 100);
                            bar.querySelector('.ep-progress-fill').style.width = `${pct}%`;
                        }
                        bar.classList.remove('hidden');
                    }
                }
            } catch (e) { /* progress bars are cosmetic, don't block */ }
        }
    }
}

// --- Casting Logic ---
let targetCastMediaId = null;

window.openCastModal = async function (id, event) {
    if (event) event.stopPropagation();
    targetCastMediaId = id;
    const modal = document.getElementById('castModal');
    const list = document.getElementById('cast-device-list');

    modal.classList.remove('hidden');
    list.innerHTML = 'Scanning local network for Roku devices... <span class="material-icons" style="vertical-align:middle;font-size:16px;">search</span>';

    try {
        const res = await fetch('/api/v1/remote/devices', { headers: getAuthHeaders() });
        if (!res.ok) throw new Error("Failed to scan devices");
        const devices = await res.json();

        if (devices.length === 0) {
            list.innerHTML = '<span style="color:var(--text-muted)">No Roku devices found. Ensure they are powered on and connected to the same Wi-Fi network.</span>';
            return;
        }

        list.innerHTML = devices.map(d => `
            <button class="btn btn-ghost" style="justify-content:flex-start;text-align:left;padding:12px;display:flex;align-items:center;gap:12px;background:var(--surface-2);border-radius:var(--radius);width:100%;border:none;cursor:pointer;" onclick="castToDevice('${d.ip}')">
                <span class="material-icons" style="color:var(--primary)">tv</span>
                <div style="display:flex;flex-direction:column;">
                    <span style="font-weight:600;font-size:1rem;color:var(--text-color)">${d.name}</span>
                    <span style="font-size:0.8rem;color:var(--text-muted)">${d.ip}</span>
                </div>
            </button>
        `).join('');
    } catch (e) {
        list.innerHTML = `<span class="badge" style="background:var(--danger)">Error: ${e.message}</span>`;
    }
}

window.castToDevice = async function (ip) {
    if (!targetCastMediaId) return;
    const list = document.getElementById('cast-device-list');
    list.innerHTML = 'Sending Cast instruction to TV...';
    try {
        const res = await fetch('/api/v1/remote/cast', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', ...getAuthHeaders() },
            body: JSON.stringify({ device_ip: ip, media_id: targetCastMediaId })
        });
        if (!res.ok) throw new Error('Cast command rejected');
        document.getElementById('castModal').classList.add('hidden');
    } catch (e) {
        list.innerHTML = `<span class="badge" style="background:var(--danger)">Failed to cast: ${e.message}</span>`;
    }
}

/** Delete an episode card inline (no page reload, removes card from DOM). */
window.deleteEpisode = async function (event, epId, epLabel, seasonId, seasonNum) {
    event.stopPropagation(); // don't trigger playEpisode
    if (!confirm(`Remove "${epLabel}" from library? Files on disk will NOT be deleted.`)) return;
    try {
        const r = await fetch(`/api/v1/media/${epId}`, {
            method: 'DELETE',
            headers: getAuthHeaders()
        });
        if (!r.ok) throw new Error(`Delete failed: ${r.status}`);
        // Reload the season so counts stay correct
        await loadEpisodes(seasonId, seasonNum);
    } catch (e) {
        alert("Failed to remove episode: " + e.message);
    }
}

// --- Watch Progress Helpers ---

let _progressInterval = null;
let _progressMediaId = null;

function _fmtTime(sec) {
    sec = Math.floor(sec);
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    return `${m}:${String(s).padStart(2, '0')}`;
}

async function _fetchProgress(id) {
    try {
        const res = await fetch(`/api/v1/history/${id}`, { headers: getAuthHeaders() });
        if (res.ok) return await res.json();
    } catch (e) { }
    return null;
}

async function _saveProgress(id) {
    if (!plyr || !id || plyr.currentTime < 2) return;
    try {
        await fetch(`/api/v1/history/${id}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', ...getAuthHeaders() },
            body: JSON.stringify({
                position_seconds: plyr.currentTime,
                duration_seconds: plyr.duration > 0 ? plyr.duration : null,
            })
        });
    } catch (e) { console.warn('Progress save failed', e); }
}

function _startProgressTracking(id) {
    _stopProgressTracking();
    _progressMediaId = id;
    _progressInterval = setInterval(() => _saveProgress(id), 10000);
}

function _stopProgressTracking() {
    if (_progressInterval) {
        clearInterval(_progressInterval);
        _progressInterval = null;
    }
}

// On movie pages: show Resume button if there's saved progress
async function _checkMovieResume() {
    if (isShow) return;
    const prog = await _fetchProgress(mediaId);
    if (prog && !prog.completed && prog.position_seconds > 5) {
        const btn = document.getElementById('resumeBtn');
        const txt = document.getElementById('resumeBtnText');
        if (btn && txt) {
            txt.textContent = `Resume from ${_fmtTime(prog.position_seconds)}`;
            btn.classList.remove('hidden');
        }
    }
}

// --- Video Player Logic ---

let plyr;
const playerElement = document.getElementById("video-player");
const videoContainer = document.getElementById("video-container");

window.playMovie = async function () {
    playStream(mediaId, null, null, null, 0);
}

window.resumeMovie = async function () {
    const prog = await _fetchProgress(mediaId);
    const t = (prog && !prog.completed && prog.position_seconds > 5) ? prog.position_seconds : 0;
    playStream(mediaId, null, null, null, t);
}

window.playEpisode = async function (episodeId) {
    if (event) event.stopPropagation();
    const prog = await _fetchProgress(episodeId);
    const t = (prog && !prog.completed && prog.position_seconds > 5) ? prog.position_seconds : 0;
    playStream(episodeId, null, null, null, t);
}

// Global state to prevent infinite loops
let currentMediaId = null;
let currentQuality = 0; // 0, 720, 480 (int)
let currentAidx = 0;
let currentSidx = null;

async function playStream(id, qualityStr = null, aidx = null, sidx = null, startTime = 0) {
    const token = getCookie("access_token");
    if (!token) {
        alert("Login required.");
        window.location.href = "/login";
        return;
    }

    // Normalize inputs
    // qualityStr: "720p" or null
    let targetQInt = 0;
    if (qualityStr === "720p") targetQInt = 720;
    if (qualityStr === "480p") targetQInt = 480;

    let targetA = aidx !== null ? parseInt(aidx) : 0;
    let targetS = sidx !== null ? parseInt(sidx) : null;

    // Check if redundant
    if (id === currentMediaId && targetQInt === currentQuality && targetA === currentAidx && targetS === currentSidx && startTime === 0) {
        console.log("Skipping redundant reload.");
        return;
    }

    // Update State
    currentMediaId = id;
    currentQuality = targetQInt;
    currentAidx = targetA;
    currentSidx = targetS;

    // 1. Show Player UI
    if (videoContainer) {
        videoContainer.style.display = "block";
        videoContainer.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    // 2. Fetch Metadata for Tracks
    let info = { audio_tracks: [], subtitle_tracks: [] };
    try {
        let infoUrl = `/api/v1/stream/${id}/info?token=${token}`;
        if (window.currentFileId) infoUrl += `&file_id=${window.currentFileId}`;
        const res = await fetch(infoUrl);
        if (res.ok) info = await res.json();
    } catch (e) { console.error("Meta fetch error", e); }

    // 4. Initialize Plyr (HLS ONLY)
    if (plyr) plyr.destroy();
    if (window.hls) {
        window.hls.destroy();
        window.hls = null;
    }

    // ALWAYS USE HLS
    let srcUrl = `/api/v1/stream/${id}/master.m3u8?token=${token}&aidx=${targetA}`;
    if (window.currentFileId) srcUrl += `&file_id=${window.currentFileId}`;
    if (targetS !== null) {
        srcUrl += `&sidx=${targetS}`;
        if (info.subtitle_tracks && info.subtitle_tracks[targetS]) {
            srcUrl += `&stype=${info.subtitle_tracks[targetS].is_image ? 'image' : 'text'}`;
        }
    }
    const posterSrc = els.backdrop ? els.backdrop.src : "";

    if (playerElement) {
        if (Hls.isSupported()) {
            const hls = new Hls({
                startPosition: startTime > 0 ? startTime : -1,
                capLevelToPlayerSize: true,
                debug: false
            });

            hls.loadSource(srcUrl);
            hls.attachMedia(playerElement);
            window.hls = hls; // Global ref

            hls.on(Hls.Events.MANIFEST_PARSED, function () {
                if (startTime > 0) playerElement.currentTime = startTime;
                playerElement.play().catch(e => console.log("Autoplay blocked/failed", e));
                _startProgressTracking(id);
            });

            hls.on(Hls.Events.ERROR, function (event, data) {
                if (data.fatal) {
                    switch (data.type) {
                        case Hls.ErrorTypes.NETWORK_ERROR:
                            console.log("fatal network error encountered, try to recover");
                            hls.startLoad();
                            break;
                        case Hls.ErrorTypes.MEDIA_ERROR:
                            console.log("fatal media error encountered, try to recover");
                            hls.recoverMediaError();
                            break;
                        default:
                            hls.destroy();
                            break;
                    }
                }
            });
        }
        else if (playerElement.canPlayType('application/vnd.apple.mpegurl')) {
            playerElement.src = srcUrl;
            playerElement.addEventListener('canplay', function onCanPlay() {
                playerElement.removeEventListener('canplay', onCanPlay);
                if (startTime > 0) playerElement.currentTime = startTime;
                playerElement.play();
                _startProgressTracking(id);
            });
        }

        // Initialize Plyr UI (Controls only)
        plyr = new Plyr(playerElement, {
            controls: [
                'play-large', 'play', 'progress', 'current-time', 'duration', 'mute',
                'volume', 'captions', 'settings', 'pip', 'airplay', 'fullscreen'
            ],
            settings: ['quality', 'speed'],
            duration: info.duration,
            quality: {
                default: 0,
                options: [0],
                forced: true,
                onChange: (q) => { }
            },
            tooltips: { controls: true, seek: true }
        });

        plyr.poster = posterSrc;

        // No source setting for Plyr - Hls.js handles it
    }

    // --- Custom UI Injectors (Audio/Sub Selectors) ---
    setupMenuInjection(info, id, qualityStr, targetA, targetS);
}

let menuObserver = null;

function setupMenuInjection(info, mediaId, qualityStr, aidx, sidx) {
    const menuContainer = document.querySelector('.plyr__menu__container');
    if (!menuContainer) return;

    // Disconnect old observer if exists
    if (menuObserver) menuObserver.disconnect();

    const inject = () => {
        // Target the "home" pane. 
        const homePane = menuContainer.querySelector('div > div');
        if (!homePane) return;

        // CRITICAL FIX: Remove existing ones to ensure event listeners get FRESH closures (mediaId, aidx, sidx)
        const oldAudio = homePane.querySelector('#plyr-custom-audio');
        if (oldAudio) oldAudio.remove();

        const oldSubs = homePane.querySelector('#plyr-custom-sub');
        if (oldSubs) oldSubs.remove();

        // Common Style for the select element
        const selectStyle = "background: rgba(0,0,0,0.5); color: #fff; border: 1px solid #444; text-align: right; width: 130px; outline: none; cursor: pointer; padding: 2px 4px; border-radius: 4px; font-size: 13px;";

        // --- Audio Selector Row ---
        if (info.audio_tracks.length > 0) {
            const row = document.createElement("div");
            row.id = "plyr-custom-audio";
            row.className = "plyr__control";
            row.style.cssText = "display: flex; justify-content: space-between; align-items: center; padding: 7px 10px; cursor: default;";

            const label = document.createElement("span");
            label.innerText = "Audio";
            row.appendChild(label);

            const select = document.createElement("select");
            select.className = "plyr__menu__value";
            select.style.cssText = selectStyle;

            select.innerHTML = info.audio_tracks.map((t, i) =>
                `<option value="${i}" ${i == aidx ? 'selected' : ''} style="color: black;">${t.language.toUpperCase()} (${t.codec})</option>`
            ).join("");

            select.onchange = (e) => {
                const val = parseInt(e.target.value);
                if (!isNaN(val)) playStream(mediaId, qualityStr, val, sidx, plyr ? plyr.currentTime : 0);
            };

            row.appendChild(select);
            homePane.insertBefore(row, homePane.firstChild);
        }

        // --- Burn-In Subtitle Selector Row ---
        if (info.subtitle_tracks.length > 0) {
            const row = document.createElement("div");
            row.id = "plyr-custom-sub";
            row.className = "plyr__control";
            row.style.cssText = "display: flex; justify-content: space-between; align-items: center; padding: 7px 10px; cursor: default;";

            const label = document.createElement("span");
            label.innerText = "Subtitles";
            row.appendChild(label);

            const select = document.createElement("select");
            select.style.cssText = selectStyle;

            let html = `<option value="off" style="color: black;">Off</option>`;
            info.subtitle_tracks.forEach((t, i) => {
                const typeLabel = t.is_image ? "(Img)" : "(Text)";
                const sel = (i === sidx) ? "selected" : "";
                html += `<option value="${i}" ${sel} style="color: black;">${t.language.toUpperCase()} ${typeLabel}</option>`;
            });

            select.innerHTML = html;
            select.onchange = (e) => {
                const val = e.target.value;
                const newSidx = val === "off" ? null : parseInt(val);
                playStream(mediaId, qualityStr, aidx, newSidx, plyr ? plyr.currentTime : 0);
            };

            row.appendChild(select);
            homePane.insertBefore(row, homePane.firstChild);
        }
    };

    // Run once immediately
    inject();

    // Watch for menu rebuilds
    menuObserver = new MutationObserver(() => {
        // Prevent infinite loop by disconnecting while we modify DOM
        menuObserver.disconnect();
        inject();
        menuObserver.observe(menuContainer, { childList: true, subtree: true });
    });
    menuObserver.observe(menuContainer, { childList: true, subtree: true });
}

window.closePlayer = function () {
    // Save final position before closing
    _saveProgress(_progressMediaId);
    _stopProgressTracking();

    // Reset Globals
    currentMediaId = null;
    currentQuality = 0;
    currentAidx = 0;
    currentSidx = null;

    if (plyr) {
        plyr.pause();
        plyr.source = {}; // Clear source to stop buffering
    }
    if (videoContainer) videoContainer.style.display = "none";
}
