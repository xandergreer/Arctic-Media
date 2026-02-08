// Arctic Media 2.0 - Home Page Logic

function getAuthHeaders() {
    // Reusing the same auth logic. Ideally this should be in a shared utils.js
    const value = `; ${document.cookie}`;
    const parts = value.split(`; access_token=`);
    if (parts.length === 2) {
        const token = parts.pop().split(';').shift();
        return { 'Authorization': `Bearer ${token}` };
    }
    return {};
}

document.addEventListener("DOMContentLoaded", async () => {
    const moviesContainer = document.getElementById("movies-row");
    const showsContainer = document.getElementById("shows-row");
    const loading = document.getElementById("loading");

    try {
        const res = await fetch('/api/v1/media/recently-added?limit=10', {
            headers: getAuthHeaders()
        });

        if (!res.ok) throw new Error("Failed to load dashboard");
        const data = await res.json();

        loading.classList.add("hidden");

        // Render Movies
        if (data.movies.length > 0) {
            document.getElementById("movies-section").classList.remove("hidden");
            renderRow(moviesContainer, data.movies);
        }

        // Render Shows
        if (data.shows.length > 0) {
            document.getElementById("tv-section").classList.remove("hidden");
            renderRow(showsContainer, data.shows);
        }

        if (data.movies.length === 0 && data.shows.length === 0) {
            document.getElementById("empty-state").classList.remove("hidden");
        }

    } catch (e) {
        console.error(e);
        loading.innerText = "Error loading dashboard.";
    }

    function renderRow(container, items) {
        container.innerHTML = items.map(item => {
            const poster = item.poster_url ?
                `<img src="${item.poster_url}" style="width: 100%; height: 100%; object-fit: cover;" loading="lazy">` :
                `<div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; background: #1e293b; color: #475569; font-weight: bold; font-size: 2rem;">
                    ${item.title.substring(0, 1)}
                 </div>`;

            const link = item.kind === 'movie' ? `/movie/${item.id}` : `/show/${item.id}`;

            return `
            <div class="media-card" style="flex: 0 0 auto; width: 160px; aspect-ratio: 2/3; position: relative; background: var(--surface-color); border-radius: var(--border-radius); overflow: hidden; cursor: pointer; scroll-snap-align: start;"
                 onclick="window.location.href='${link}'">
                 ${poster}
                 <div style="position: absolute; bottom: 0; left: 0; right: 0; padding: 0.5rem; background: linear-gradient(to top, rgba(0,0,0,0.9), transparent);">
                    <div style="font-size: 0.85rem; font-weight: 600; text-overflow: ellipsis; overflow: hidden; white-space: nowrap;">${item.title}</div>
                 </div>
            </div>`;
        }).join("");
    }
});
