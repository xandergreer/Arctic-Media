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
        }
    } catch (e) {
        console.error("Admin check failed", e);
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
        class="season-btn ${index === 0 ? 'active' : ''}"
        style="padding: 0.5rem 1.5rem; background: var(--surface-color); border: 1px solid var(--border-color); color: white; border-radius: 20px; cursor: pointer; white-space: nowrap;">
            Season ${s.season_number}
        </button>`;
    }).join("");

    if (seasons.length > 0) {
        loadEpisodes(seasons[0].id, seasons[0].season_number);
    }
}

window.loadEpisodes = async function (seasonId, seasonNum) {
    document.querySelectorAll(".season-btn").forEach(btn => {
        btn.style.background = "var(--surface-color)";
        if (btn.innerText.includes(`Season ${seasonNum}`)) {
            btn.style.background = "var(--primary-color)";
        }
    });

    if (els.seasonTitle) els.seasonTitle.innerText = `Season ${seasonNum}`;
    if (els.episodeGrid) els.episodeGrid.innerHTML = "Loading...";

    const res = await fetch(`/api/v1/media/seasons/${seasonId}/episodes`, {
        headers: getAuthHeaders()
    });
    const episodes = await res.json();

    if (els.episodeGrid) {
        els.episodeGrid.innerHTML = episodes.map(ep => {
            const still = ep.poster_url || "";
            return `
            <div class="media-card" style="background: var(--surface-color); border-radius: 8px; overflow: hidden; cursor: pointer;" onclick="playEpisode(${ep.id})">
                <div style="height: 140px; background: #000; position: relative;">
                    <img src="${still}" style="width: 100%; height: 100%; object-fit: cover; opacity: 0.8;">
                    <div style="position: absolute; bottom: 0.5rem; left: 0.5rem; background: rgba(0,0,0,0.6); padding: 2px 6px; border-radius: 4px; font-size: 0.8rem;">
                        E${ep.episode_number}
                    </div>
                </div>
                <div style="padding: 1rem;">
                    <h4 style="margin: 0 0 0.5rem 0; font-size: 1rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${ep.title || 'Episode ' + ep.episode_number}</h4>
                    <p style="font-size: 0.85rem; color: #94a3b8; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; margin: 0;">
                        ${ep.overview || "No description."}
                    </p>
                </div>
            </div>
            `;
        }).join("");
    }
}

// --- Video Player Logic ---

let plyr;
const playerElement = document.getElementById("video-player");
const videoContainer = document.getElementById("video-container");

window.playMovie = function () {
    playStream(mediaId);
}

window.playEpisode = function (episodeId) {
    if (event) event.stopPropagation();
    playStream(episodeId);
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
        const res = await fetch(`/api/v1/stream/${id}/info?token=${token}`);
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
            playerElement.addEventListener('canplay', function () {
                if (startTime > 0) playerElement.currentTime = startTime;
                playerElement.play();
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
