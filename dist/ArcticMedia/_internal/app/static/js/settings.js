// Arctic Media 2.0 - Settings Page Logic

// Helper: Get Cookie (Shared logic)
function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
}

function getAuthHeaders() {
    const token = getCookie("access_token");
    return token ? { 'Authorization': `Bearer ${token}` } : {};
}

document.addEventListener("DOMContentLoaded", () => {

    // --- GENERAL SETTINGS ---
    const generalForm = document.getElementById("general-settings-form");
    const customDomainInput = document.getElementById("custom-domain");

    // Load initial settings
    if (customDomainInput) {
        fetch("/api/v1/settings/custom_domain", {
            headers: getAuthHeaders()
        })
            .then(res => {
                if (res.ok) return res.json();
                return { value: "" };
            })
            .then(data => {
                if (data && data.value) {
                    customDomainInput.value = data.value;
                }
            })
            .catch(err => console.error("Failed to load settings", err));
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
                    headers: {
                        ...getAuthHeaders(),
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        key: "custom_domain",
                        value: domain
                    })
                });

                if (res.ok) {
                    // Visual feedback
                    submitBtn.textContent = "Saved!";
                    setTimeout(() => {
                        submitBtn.textContent = originalText;
                        submitBtn.disabled = false;
                    }, 2000);
                } else {
                    alert("Failed to save settings.");
                    submitBtn.textContent = originalText;
                    submitBtn.disabled = false;
                }
            } catch (err) {
                console.error(err);
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

            if (!path) {
                alert("Please enter a Path.");
                return;
            }

            // Send JSON! Much more reliable than Form Data for APIs
            const payload = {
                name: name,
                path: path,
                type: type
            };

            try {
                const res = await fetch("/api/v1/libraries", {
                    method: "POST",
                    headers: {
                        ...getAuthHeaders(),
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(payload)
                });

                if (res.ok) {
                    window.location.reload(); // Refresh to see new library
                } else {
                    const err = await res.json();
                    alert("Error: " + (err.detail || "Failed to add library"));
                }
            } catch (err) {
                console.error(err);
                alert("Connection failed.");
            }
        });
    }

    // --- DELETE LIBRARY ---
    document.querySelectorAll('.delete-lib-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const libId = e.currentTarget.getAttribute('data-id');
            if (!confirm('Are you sure? This removes it from the database.')) return;
            try {
                const res = await fetch(`/api/v1/libraries/${libId}`, {
                    method: 'DELETE',
                    headers: getAuthHeaders()
                });
                if (res.ok) window.location.reload();
            } catch (err) {
                alert('Failed to delete.');
            }
        });
    });

    // --- RESCAN SINGLE LIBRARY ---
    document.querySelectorAll('.rescan-lib-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const libId = e.currentTarget.getAttribute('data-id');
            const icon = e.currentTarget.querySelector('.material-icons');
            const orig = icon.textContent;
            icon.style.animation = 'spin 1s linear infinite';
            e.currentTarget.disabled = true;
            try {
                const res = await fetch(`/api/v1/scan/library/${libId}`, {
                    method: 'POST',
                    headers: getAuthHeaders()
                });
                const data = await res.json();
                if (res.ok) {
                    alert(`Rescan complete: ${data.library}`);
                    window.location.reload();
                } else {
                    alert(`Rescan failed: ${data.detail || 'Unknown error'}`);
                }
            } catch (err) {
                alert('Rescan request failed.');
                console.error(err);
            }
            icon.style.animation = '';
            icon.textContent = orig;
            e.currentTarget.disabled = false;
        });
    });



    // --- SCAN NOW ---
    const scanBtn = document.getElementById('scan-btn');
    if (scanBtn) {
        scanBtn.addEventListener('click', async () => {
            const orig = scanBtn.innerHTML;
            scanBtn.innerHTML = '<span class="material-icons" style="font-size:0.95rem;animation:spin 1s linear infinite;">sync</span> Scanning…';
            scanBtn.disabled = true;
            try {
                const res = await fetch('/api/v1/scan/run', {
                    method: 'POST',
                    headers: getAuthHeaders()
                });
                const data = await res.json();

                if (data.status === 'no_libraries') {
                    alert('No libraries configured. Add a library below first.');
                } else if (data.status === 'partial') {
                    const errors = data.results.filter(r => r.status === 'error');
                    const ok = data.results.filter(r => r.status === 'ok');
                    alert(`Scan finished with errors.\n\nCompleted: ${ok.map(r => r.library).join(', ') || 'none'}\n\nFailed:\n${errors.map(r => `• ${r.library}: ${r.detail}`).join('\n')}`);
                    window.location.reload();
                } else if (data.status === 'ok') {
                    alert(`Scan complete! ${data.results.length} library(s) scanned successfully.`);
                    window.location.reload();
                } else {
                    alert('Scan returned an unexpected response.');
                }
            } catch (err) {
                alert('Scan request failed — check server connection.');
                console.error(err);
            }
            scanBtn.innerHTML = orig;
            scanBtn.disabled = false;
        });
    }

});
