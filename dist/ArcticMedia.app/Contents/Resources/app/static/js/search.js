class Search {
    constructor() {
        this.searchContainer = document.getElementById('search-container');
        this.searchBtn = document.getElementById('search-toggle-btn');
        this.searchInputWrapper = document.querySelector('.search-input-wrapper');
        this.searchInput = document.getElementById('search-input');
        this.searchClear = document.getElementById('search-clear');
        this.searchResultsPopup = document.getElementById('search-results');

        this.searchTimeout = null;
        this.isExpanded = false;

        // Use a simple Map for caching results
        this.searchCache = new Map();

        this.init();
    }

    init() {
        if (!this.searchBtn) return;

        this.searchBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            this.toggleSearch();
        });

        this.searchClear?.addEventListener('click', () => this.clearSearch());
        this.searchInput?.addEventListener('input', (e) => this.handleSearch(e.target.value));
        this.searchInput?.addEventListener('keydown', (e) => this.handleKeydown(e));

        // Collapse search when clicking outside
        document.addEventListener('click', (e) => this.handleOutsideClick(e));

        // Collapse on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isExpanded) {
                e.preventDefault();
                this.collapseSearch();
            }
        });

        // Expand on Ctrl+K or Cmd+K
        document.addEventListener('keydown', (e) => {
            if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
                e.preventDefault();
                this.expandSearch();
            }
        });
    }

    toggleSearch() {
        if (this.isExpanded) {
            this.collapseSearch();
        } else {
            this.expandSearch();
        }
    }

    expandSearch() {
        if (this.isExpanded) return;
        this.isExpanded = true;
        this.searchContainer.style.display = 'block';
        this.searchBtn.classList.add('active');

        // Focus after display update
        setTimeout(() => {
            this.searchInput.focus();
            this.updateClearButton();
            if (this.searchInput.value.trim().length >= 2) {
                this.searchResultsPopup.classList.add('visible');
            }
        }, 50);
    }

    collapseSearch() {
        if (!this.isExpanded) return;
        this.isExpanded = false;
        this.searchContainer.style.display = 'none';
        this.searchBtn.classList.remove('active');
        this.searchResultsPopup.classList.remove('visible');
    }

    handleOutsideClick(e) {
        if (this.isExpanded && !this.searchContainer.contains(e.target) && e.target !== this.searchBtn && !this.searchBtn.contains(e.target)) {
            this.collapseSearch();
        }
    }

    clearSearch() {
        this.searchInput.value = '';
        this.searchInput.focus();
        this.updateClearButton();
        this.showPlaceholder();
        this.clearSearchTimeout();
    }

    updateClearButton() {
        if (this.searchClear) {
            this.searchClear.style.display = this.searchInput.value ? 'flex' : 'none';
        }
    }

    handleKeydown(e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            const firstResult = this.searchResultsPopup.querySelector('.search-result-item');
            if (firstResult) {
                firstResult.click();
            } else if (this.searchInput.value.trim().length >= 2) {
                this.performSearch(this.searchInput.value.trim());
            }
        }
    }

    handleSearch(query) {
        query = query.trim();
        this.updateClearButton();
        this.clearSearchTimeout();

        if (!query || query.length < 2) {
            this.showPlaceholder();
            return;
        }

        this.searchResultsPopup.classList.add('visible');

        // Check cache before debating API call
        if (this.searchCache.has(query)) {
            this.renderResults(this.searchCache.get(query));
            return;
        }

        // Debounce search
        this.searchTimeout = setTimeout(() => {
            this.performSearch(query);
        }, 300);
    }

    clearSearchTimeout() {
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
            this.searchTimeout = null;
        }
    }

    async performSearch(query) {
        this.showLoading();

        try {
            const response = await fetch(`/api/v1/media/search?q=${encodeURIComponent(query)}`);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();

            // Cache results (max limit 50 items to prevent huge memory leak over long sessions)
            if (this.searchCache.size > 50) {
                const firstKey = this.searchCache.keys().next().value;
                this.searchCache.delete(firstKey);
            }
            this.searchCache.set(query, data);

            this.renderResults(data);
        } catch (error) {
            console.error('Search failed:', error);
            this.showError();
        }
    }

    renderResults(data) {
        this.searchResultsPopup.innerHTML = '';

        const movies = data.movies || [];
        const tvShows = data.shows || [];

        if (movies.length === 0 && tvShows.length === 0) {
            this.showNoResults();
            return;
        }

        if (movies.length > 0) {
            this.searchResultsPopup.innerHTML += this.renderSection('Movies', movies, 'movie');
        }
        if (tvShows.length > 0) {
            this.searchResultsPopup.innerHTML += this.renderSection('TV Shows', tvShows, 'show');
        }
    }

    renderSection(title, items, type) {
        let html = `<div class="search-section"><h4 class="search-section-title">${title}</h4>`;
        items.forEach(item => {
            const posterUrl = item.poster_url || '/static/img/placeholder.png'; // Assuming you have a placeholder
            const itemYear = item.year ? `<span class="search-result-year">(${item.year})</span>` : '';

            // Limit overview length
            let itemOverview = item.overview || '';
            if (itemOverview.length > 80) {
                itemOverview = itemOverview.substring(0, 80) + '...';
            } else if (!itemOverview) {
                itemOverview = 'No overview available.';
            }

            // Route correctly depending on the app's structure
            const routeType = type === 'movie' ? 'movie' : 'show';

            html += `
                <a href="/${routeType}/${item.id}" class="search-result-item">
                    <img src="${posterUrl}" alt="${item.title}" class="search-result-poster" loading="lazy">
                    <div class="search-result-info">
                        <div class="search-result-title">${item.title} ${itemYear}</div>
                        <div class="search-result-overview">${itemOverview}</div>
                    </div>
                </a>
            `;
        });
        html += `</div>`;
        return html;
    }

    showLoading() {
        this.searchResultsPopup.innerHTML = `
            <div class="search-placeholder">
                <span class="material-icons rotating" style="display:inline-block; animation: rotate 1s linear infinite;">autorenew</span>
                <p>Searching...</p>
            </div>
            <style>
            @keyframes rotate {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }
            </style>
        `;
        this.searchResultsPopup.classList.add('visible');
    }

    showPlaceholder() {
        this.searchResultsPopup.innerHTML = `
            <div class="search-placeholder">
                <p>Start typing to search movies and TV shows</p>
            </div>
        `;
        this.searchResultsPopup.classList.add('visible');
    }

    showNoResults() {
        this.searchResultsPopup.innerHTML = `
            <div class="search-placeholder">
                <span class="material-icons" style="font-size: 32px; opacity: 0.5; margin-bottom: 8px;">search_off</span>
                <p>No results found.</p>
            </div>
        `;
        this.searchResultsPopup.classList.add('visible');
    }

    showError() {
        this.searchResultsPopup.innerHTML = `
            <div class="search-placeholder">
                <span class="material-icons" style="font-size: 32px; opacity: 0.5; margin-bottom: 8px; color: #ff6b6b">error_outline</span>
                <p>An error occurred. Please try again.</p>
            </div>
        `;
        this.searchResultsPopup.classList.add('visible');
    }
}

document.addEventListener('DOMContentLoaded', () => {
    new Search();
});
