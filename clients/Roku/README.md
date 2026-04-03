# Arctic Media Roku App (MVP)

This is a minimal Roku SceneGraph client for Arctic Media.

## Project layout

- `manifest` (required at package root) — NOTE: if a folder named `manifest` exists, rename/remove it and create a text file named `manifest` per the example in this README.
- `source/` — BrightScript code
- `components/` — SceneGraph XML components
- `images/` — icons/art (PNG)

## Testing Without a Roku Device

Roku doesn't provide an official emulator, but you can test the backend pairing flow:

1. **Test pairing endpoints** (Python script):
   ```bash
   # Start your server first
   python roku/test_pairing.py http://127.0.0.1:8085
   # Then activate from another terminal:
   python roku/test_pairing_activate.py ABCD-1234
   ```

2. **VS Code Extension** (for syntax checking):
   - Install "BrightScript" extension by RokuCommunity
   - Provides syntax highlighting and basic error checking

## Sideload (Developer Mode)

1. Enable developer mode on your Roku (press Home x3, Up x2, Right, Left, Right, Left, Right).
2. Visit `http://ROKU_IP` in a browser, sign in to the developer web UI.
3. Zip the app folder contents (manifest at root, plus components/, source/, images/).
4. Upload the zip via the web UI and click Install.

## Pairing flow (device code)

- App calls your server `POST /pair/request` to get `{ user_code, device_code, expires_in }`.
- Displays the `user_code` and asks user to go to `http://SERVER/pair` on their phone to authorize.
- The app polls `POST /pair/poll` with `device_code` until authorized, then stores tokens.

## Server endpoints (implemented)

- `POST /pair/request` → `{ device_code, user_code, expires_in, interval }`
- `POST /pair/activate` (web, logged-in) `{ user_code }` → authorize device
- `POST /pair/poll` `{ device_code }` → pending/authorized + tokens when ready
- `GET /pair` → simple HTML page to enter the code

## Build notes

- Icons: Convert `app/static/img/logo-mark-icecap-cutout.svg` to PNG:
  - `images/app_icon_hd.png` (1920x1080)
  - `images/app_icon_sd.png` (1240x720)
- Edit `manifest` with your app name/version.

## TODO MVP

- ✅ Pairing screen (implemented)
- Library list → Items grid
- Details → Play (HLS master.m3u8)
- Resume progress and mark watched
