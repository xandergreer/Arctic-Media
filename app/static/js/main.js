// Arctic Media 2.0 - Main Logic

// Helper: fetch with credentials included (sends HttpOnly cookie automatically)
function authFetch(url, options = {}) {
    return fetch(url, { credentials: 'include', ...options });
}

// Obtain a short-lived streaming token for use in media/HLS URL query params.
// Resolves to a string token or null on failure.
async function getStreamToken() {
    try {
        const res = await authFetch('/api/v1/auth/stream-token', { method: 'POST' });
        if (!res.ok) return null;
        const data = await res.json();
        return data.token || null;
    } catch (_) {
        return null;
    }
}

document.addEventListener("DOMContentLoaded", () => {

    // --- AUTHENTICATION CHECK ---
    // Cookie is HttpOnly so JS cannot read it directly.
    // Check login state and admin status via /api/v1/auth/me.
    const loginBtn = document.getElementById("loginBtn");
    const logoutBtn = document.getElementById("logoutBtn");

    (async () => {
        try {
            const res = await fetch("/api/v1/auth/me", { credentials: "include" });
            if (res.ok) {
                const me = await res.json();
                if (loginBtn) loginBtn.style.display = "none";
                if (logoutBtn) {
                    logoutBtn.style.display = "inline-block";
                    logoutBtn.addEventListener("click", async () => {
                        await fetch("/api/v1/auth/logout", { method: "POST", credentials: "include" });
                        window.location.href = "/login";
                    });
                }
                if (me.is_superuser) {
                    const adminLink = document.getElementById('nav-admin');
                    if (adminLink) adminLink.style.display = 'inline-block';
                }
            } else {
                // Not logged in — show login button
                if (loginBtn) loginBtn.style.display = "inline-block";
                if (logoutBtn) logoutBtn.style.display = "none";
            }
        } catch (_) {}
    })();

    // --- LOGIN FORM ---
    const loginForm = document.getElementById("loginForm");
    if (loginForm) {
        loginForm.addEventListener("submit", async (e) => {
            e.preventDefault();
            const errorDiv = document.getElementById("error-msg");
            errorDiv.style.display = "none";

            const username = document.getElementById("username").value;
            const password = document.getElementById("password").value;

            // OAuth2 requires form-data
            const formData = new URLSearchParams();
            formData.append('username', username);
            formData.append('password', password);

            try {
                const response = await fetch("/api/v1/auth/token", {
                    method: "POST",
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: formData
                });

                if (response.ok) {
                    // Server sets the HttpOnly cookie; no need to store the token in JS
                    window.location.href = "/";
                } else {
                    let errorText = "Invalid credentials";
                    try {
                        const errData = await response.json();
                        if (errData.detail) errorText = errData.detail;
                    } catch (e) {
                        errorText = `Error: ${response.status} ${response.statusText}`;
                    }
                    errorDiv.textContent = errorText;
                    errorDiv.style.display = "block";
                }
            } catch (err) {
                errorDiv.textContent = "Server connection failure";
                errorDiv.style.display = "block";
            }
        });
    }

    // --- REGISTER FORM ---
    const registerForm = document.getElementById("registerForm");
    if (registerForm) {
        // Pre-fill invite code from URL param and show the field
        const urlCode = new URLSearchParams(window.location.search).get('code');
        const inviteGroup = document.getElementById('invite-group');
        const inviteInput = document.getElementById('invite_code');
        if (urlCode && inviteInput) {
            inviteInput.value = urlCode;
            if (inviteGroup) inviteGroup.style.display = 'block';
        }

        registerForm.addEventListener("submit", async (e) => {
            e.preventDefault();
            const msgBox = document.getElementById("msg-box");
            msgBox.style.display = "none";
            msgBox.style.color = "#ef4444";

            const username = document.getElementById("username").value;
            const password = document.getElementById("password").value;
            const inviteCode = inviteInput ? inviteInput.value.trim() : '';

            const registerPayload = { username, password };
            if (inviteCode) registerPayload.invite_code = inviteCode;

            try {
                const response = await fetch("/api/v1/auth/register", {
                    method: "POST",
                    credentials: "include",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(registerPayload),
                });

                if (response.ok) {
                    msgBox.style.color = "#22c55e";
                    msgBox.innerHTML = 'Account created! Redirecting to login...';
                    msgBox.style.display = "block";
                    setTimeout(() => window.location.href = "/login", 2000);
                } else {
                    const data = await response.json();
                    const detail = data.detail || "Registration failed";
                    msgBox.innerText = detail;
                    msgBox.style.display = "block";
                    // Show invite field if server says it's required
                    if (detail.toLowerCase().includes('invite') && inviteGroup) {
                        inviteGroup.style.display = 'block';
                    }
                }
            } catch (err) {
                msgBox.innerText = "Server connection failure";
                msgBox.style.display = "block";
            }
        });
    }
});
