# Arctic Media

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS-blue?style=flat-square)
![Python](https://img.shields.io/badge/python-3.11%2B-blue?style=flat-square)
![FastAPI](https://img.shields.io/badge/FastAPI-0.128-009688?style=flat-square&logo=fastapi)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![iOS](https://img.shields.io/badge/iOS-app%20available-black?style=flat-square&logo=apple)
![Roku](https://img.shields.io/badge/Roku-coming%20soon-6f1ab1?style=flat-square)

> *Your personal streaming server. Host your own movies and TV shows and watch them from anywhere.*


## 🌟 Highlights

- Stream your local movie and TV show library from any browser on any device
- Automatic metadata fetching from TMDB — posters, overviews, ratings, and episode titles
- Fast library scanning with smart title cleaning and TMDB canonical title correction
- Continue watching — progress is saved automatically and syncs across devices
- Per-episode progress bars and resume support on iOS
- Auto-play next episode with a toggleable setting
- Admin panel with live viewer monitoring, server metrics, user management, and watch history
- Media request system — users can request content, admins can acknowledge and fulfill requests
- Invite-only or open registration — you control who gets access
- HLS adaptive streaming via FFmpeg for broad device compatibility
- Native iOS app with liquid glass navigation (iOS 26) for watching on the go
- Roku app in development
- Self-contained executable for Windows and macOS — no Python or dependencies required on the host machine


## ℹ️ Overview

Arctic Media is a self-hosted media server built with FastAPI, SQLite, and vanilla JavaScript. Point it at your movie and TV show folders, and it will scan, clean, and enrich your library with metadata from TMDB. You and your users can then stream directly from a browser — no app installs, no subscriptions, no cloud.

It was built as a personal alternative to Plex and Jellyfin with a focus on simplicity: a single executable, a single SQLite database, a clean modern UI that works on any device. And most importantly, it's completely free.


### ✍️ Authors

Built by [arctic](https://github.com/arctic) — inspired by Plex, Jellyfin, and Emby.


## 📱 Client Apps

| Platform | Status | Notes |
|----------|--------|-------|
| Browser (any) | ✅ Available | Primary interface, works on all devices |
| iOS | ✅ Available | Native app — must sideload ipa |
| Roku | 🚧 In progress | Coming soon |
| Android | 🔜 Planned | — |


## 🚀 Usage

Once running, open your browser to `http://localhost:8000`.

1. **Register** an account — the first account is automatically an admin
2. Go to **Settings → Library Management** and add your movie or TV show folders
3. Hit **Scan All** — Arctic Media will find your files, clean their titles, and fetch posters and metadata from TMDB
4. Browse your library, click anything, and start watching

**Admin panel** (`/admin`) gives you:
- **Live View** — see who is watching what in real time, with device and progress info
- **Server** — live CPU, RAM, and network usage plus disk space per library
- **Users** — promote, demote, or delete accounts
- **Invites** — generate invite codes or toggle open registration
- **History** — total watch time, most-watched titles, and per-user playback history
- **Requests** — view, acknowledge, and fulfill content requests submitted by users


## ⬇️ Installation

### Windows — Pre-built Executable

Download the latest `ArcticMedia.exe` from the [Releases](../../releases) page, put it in a desired folder, and double-click to run. No Python or dependencies required.

Arctic Media will start a local web server on port `8000` and appear in the system tray.

### macOS — Pre-built App

Download the latest `ArcticMedia.dmg` from the [Releases](../../releases) page, open it, and drag Arctic Media to your Applications folder.

Arctic Media will start a local web server on port `8000` and appear in the menu bar.

> **Note:** On first launch macOS may show a security prompt. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Run from Source (Windows & macOS)

**Requirements:** Python 3.11+, FFmpeg available in your `PATH`

```bash
git clone https://github.com/arctic/arctic-media.git
cd arctic-media
pip install -r requirements.txt
```

Create a `.env` file with your keys:

```env
TMDB_API_KEY=your_tmdb_api_key_here
SECRET_KEY=your_secret_key_here
```

Then start the server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

### Build the Executable Yourself

FFmpeg and FFprobe binaries must be placed in the `bin/` folder first.

**Windows:**
```bash
pip install -r requirements.txt
pip install pyinstaller
pyinstaller ArcticMedia.spec
```
Output: `dist/ArcticMedia.exe`

**macOS:**
```bash
pip install -r requirements.txt
pip install pyinstaller
pyinstaller ArcticMedia-macOS.spec
```
Output: `dist/ArcticMedia.app`


IOS INSTALL INSTRUCTIONS COMING SOON



## 💭 Feedback and Contributing

Found a bug or have a feature request? [Open an issue](../../issues) — all feedback is welcome.

To contribute, fork the repo and open a pull request. The codebase is intentionally straightforward:
- FastAPI routes → `app/api/v1/`
- SQLAlchemy models → `app/models/`
- Jinja2 templates → `app/templates/`
- Frontend JS → `app/static/js/`
