// Arctic Media 2.0 – Library View

let allItems = [];

document.addEventListener('DOMContentLoaded', async () => {
    const grid = document.getElementById('media-grid');
    const loading = document.getElementById('loading');
    const empty = document.getElementById('empty-state');
    const titleEl = document.getElementById('library-title');
    const countEl = document.getElementById('library-count');

    titleEl.textContent = LIBRARY_TYPE === 'movies' ? 'Movies' : 'TV Shows';

    try {
        const ep = LIBRARY_TYPE === 'movies' ? '/api/v1/media/movies' : '/api/v1/media/shows';
        const res = await fetch(ep, { credentials: 'include' });
        if (!res.ok) throw new Error('Failed to fetch media');
        allItems = await res.json();

        // Remove skeleton placeholders
        grid.innerHTML = '';
        loading.style.display = 'none';

        if (allItems.length === 0) {
            empty.classList.remove('hidden');
            return;
        }

        countEl.textContent = `${allItems.length} item${allItems.length !== 1 ? 's' : ''}`;
        renderGrid(allItems);

    } catch (err) {
        console.error(err);
        loading.textContent = 'Error loading content. Please try again.';
    }
});

function renderGrid(items) {
    const grid = document.getElementById('media-grid');
    grid.innerHTML = items.map(item => {
        const poster = item.poster_url
            ? `<img src="${item.poster_url}" alt="${item.title}" loading="lazy">`
            : `<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:var(--surface-2);color:var(--text-muted);font-size:2.5rem;font-weight:700;">${item.title.charAt(0)}</div>`;

        const link = LIBRARY_TYPE === 'movies' ? `/movie/${item.id}` : `/show/${item.id}`;
        const year = item.release_date ? new Date(item.release_date).getFullYear() : '';

        return `
        <div class="media-card" onclick="window.location.href='${link}'">
            <div class="poster-wrap">${poster}</div>
            <div class="media-info">
                <div class="media-title">${item.title}</div>
                <div class="media-meta">${year}</div>
            </div>
        </div>`;
    }).join('');
}

// Sort support (called from library.html chip strip)
window.sortGrid = function (mode) {
    let sorted = [...allItems];
    if (mode === 'az') sorted.sort((a, b) => a.title.localeCompare(b.title));
    else if (mode === 'year') sorted.sort((a, b) => {
        const ya = a.release_date ? new Date(a.release_date).getFullYear() : 0;
        const yb = b.release_date ? new Date(b.release_date).getFullYear() : 0;
        return yb - ya;
    });
    // 'added' = default DB order (already sorted by server)
    renderGrid(sorted);
};
