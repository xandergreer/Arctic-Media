// Arctic Media – Make a Request modal

(function () {
    function getCookieRM(name) {
        var v = '; ' + document.cookie;
        var p = v.split('; ' + name + '=');
        if (p.length === 2) return p.pop().split(';').shift();
    }

    function openRequestModal() {
        var libType = window.LIBRARY_TYPE || '';
        var label = libType === 'movies' ? 'movie' : 'TV show';
        document.getElementById('req-kind-label').textContent = label;
        document.getElementById('request-message').value = '';
        document.getElementById('request-error').style.display = 'none';
        var modal = document.getElementById('request-modal');
        modal.style.display = 'flex';
        setTimeout(function () {
            var ta = document.getElementById('request-message');
            if (ta) ta.focus();
        }, 50);
    }

    function closeRequestModal() {
        document.getElementById('request-modal').style.display = 'none';
    }

    async function submitRequest() {
        var msg = document.getElementById('request-message').value.trim();
        var errEl = document.getElementById('request-error');
        if (!msg) {
            errEl.textContent = "Please describe what you'd like.";
            errEl.style.display = 'block';
            return;
        }
        var btn = document.getElementById('request-send-btn');
        btn.disabled = true;
        btn.textContent = 'Sending\u2026';
        errEl.style.display = 'none';
        try {
            var token = getCookieRM('access_token');
            var headers = { 'Content-Type': 'application/json' };
            if (token) headers['Authorization'] = 'Bearer ' + token;
            var res = await fetch('/api/v1/requests', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({ message: msg })
            });
            if (!res.ok) {
                var data = await res.json();
                throw new Error(data.detail || 'Failed');
            }
            closeRequestModal();
            var toast = document.getElementById('request-toast');
            toast.style.display = 'block';
            setTimeout(function () { toast.style.display = 'none'; }, 3000);
        } catch (e) {
            errEl.textContent = e.message || 'Something went wrong.';
            errEl.style.display = 'block';
        }
        btn.disabled = false;
        btn.textContent = 'Send';
    }

    // Expose to global scope for onclick attributes
    window.openRequestModal = openRequestModal;
    window.closeRequestModal = closeRequestModal;
    window.submitRequest = submitRequest;

    // Close on backdrop click
    document.addEventListener('DOMContentLoaded', function () {
        var modal = document.getElementById('request-modal');
        if (modal) {
            modal.addEventListener('click', function (e) {
                if (e.target === modal) closeRequestModal();
            });
        }
    });
})();
