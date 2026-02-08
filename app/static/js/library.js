// Arctic Media 2.0 - Library View Logic

// Helper: Get Cookie (Shared)
function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
}

function getAuthHeaders() {
    const token = getCookie("access_token");
    return token ? { 'Authorization': `Bearer ${token}` } : {};
}

document.addEventListener("DOMContentLoaded", async () => {
    const grid = document.getElementById("media-grid");
    const loading = document.getElementById("loading");
    const emptyState = document.getElementById("empty-state");
    const titleEl = document.getElementById("library-title");

    // Set Title
    titleEl.textContent = LIBRARY_TYPE === 'movies' ? 'Movies' : 'TV Shows';

    // Fetch Data
    try {
        const endpoint = LIBRARY_TYPE === 'movies' ? '/api/v1/media/movies' : '/api/v1/media/shows';
        const res = await fetch(endpoint, {
            headers: getAuthHeaders()
        });

        if (!res.ok) throw new Error("Failed to fetch media");

        const data = await res.json();

        loading.classList.add("hidden");

        if (data.length === 0) {
            emptyState.classList.remove("hidden");
            return;
        }

        renderGrid(data);

    } catch (err) {
        console.error(err);
        loading.textContent = "Error loading content. Please try again.";
    }

    function renderGrid(items) {
        grid.innerHTML = items.map(item => {
            const poster = item.poster_url ?
                `<img src="${item.poster_url}" style="width: 100%; height: 100%; object-fit: cover;" loading="lazy">` :
                `<div style="width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; background: #1e293b; color: #475569; font-weight: bold; font-size: 2rem;">
                    ${item.title.substring(0, 1)}
                 </div>`;

            const link = LIBRARY_TYPE === 'movies' ? `/movie/${item.id}` : `/show/${item.id}`;

            return `
            <div class="media-card" style="position: relative; aspect-ratio: 2/3; background: var(--surface-color); border-radius: var(--border-radius); overflow: hidden; cursor: pointer; transition: transform 0.2s;"
                 onclick="window.location.href='${link}'">
                
                ${poster}

                <div style="position: absolute; bottom: 0; left: 0; right: 0; padding: 1rem; background: linear-gradient(to top, rgba(0,0,0,0.9), transparent);">
                    <div style="font-weight: 600; text-overflow: ellipsis; overflow: hidden; white-space: nowrap;">${item.title}</div>
                    <div style="font-size: 0.8rem; color: var(--text-secondary);">
                        ${item.release_date ? new Date(item.release_date).getFullYear() : ''}
                    </div>
                </div>
            </div>
            `;
        }).join("");
    }
});
