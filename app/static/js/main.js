// Arctic Media 2.0 - Main Logic

// Helper: Get Cookie
function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
}

// Helper: Set Cookie
function setCookie(name, value, days) {
    let expires = "";
    if (days) {
        const date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + (value || "") + expires + "; path=/; SameSite=Strict";
}

// Helper: Get Auth Headers
function getAuthHeaders() {
    const token = getCookie("access_token");
    if (token) {
        return { 'Authorization': `Bearer ${token}` };
    }
    return {};
}

document.addEventListener("DOMContentLoaded", () => {

    // --- AUTHENTICATION CHECK ---
    const token = getCookie("access_token");
    const loginBtn = document.getElementById("loginBtn");
    const logoutBtn = document.getElementById("logoutBtn");

    if (token) {
        if (loginBtn) loginBtn.style.display = "none";
        if (logoutBtn) {
            logoutBtn.style.display = "inline-block";
            logoutBtn.addEventListener("click", () => {
                setCookie("access_token", "", -1); // Delete cookie
                window.location.href = "/login";
            });
        }

        // Show Live View link for admins
        try {
            let b64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
            b64 += '='.repeat((4 - b64.length % 4) % 4);
            const payload = JSON.parse(decodeURIComponent(
                atob(b64).split('').map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join('')
            ));
            if (payload.is_superuser) {
                const adminLink = document.getElementById('nav-admin');
                if (adminLink) adminLink.style.display = 'inline-block';
            }
        } catch (_) {}
    } else {
        // Redirect logic if on protected pages could go here
        // For now, we just rely on API 401s
    }

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
                    const data = await response.json();
                    setCookie("access_token", data.access_token, 7); // 7 days
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

            let url = `/api/v1/auth/register?username=${encodeURIComponent(username)}&password=${encodeURIComponent(password)}`;
            if (inviteCode) url += `&invite_code=${encodeURIComponent(inviteCode)}`;

            try {
                const response = await fetch(url, { method: "POST" });

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
