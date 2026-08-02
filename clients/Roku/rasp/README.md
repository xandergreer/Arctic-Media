# RASP scripts for App Behavior Analysis

Roku's App Behavior Analysis needs a sign-in and a sign-out script so its
automated run can reach the parts of the channel that sit behind authentication.

| Script | State |
|---|---|
| `signout.rasp` | Works against the shipping build |
| `signin.rasp` | **Cannot complete** — see below |

## Why sign-in cannot be scripted today

The channel authenticates with a device-code pairing handshake:

1. Enter the server address on the device.
2. The channel shows an 8-character code and polls the server.
3. **The viewer signs in at `https://<server>/pair` in a browser and enters
   that code.**
4. The server returns a token and the channel proceeds.

Step 3 happens on a different machine. A remote-control script drives the Roku
and nothing else, so certification's automated run gets as far as the code
screen and stops. Supplying test credentials does not help — there is no field
on the device to type them into.

This is the same architectural mismatch behind the RP 2.1 static-analysis
error: the channel is treated as an authenticated service, but its
authentication is deliberately not on-device.

## The fix: an on-device credential sign-in

`app/api/v1/auth.py:60` already exposes `POST /api/v1/auth/token`, taking
`username` and `password` as form data and returning an `access_token` — the
same endpoint the web player uses. Nothing new is needed server-side.

Adding a second option on the pairing screen — "Sign in with username and
password" — that posts to it and stores the returned token would:

- make sign-in fully scriptable, unblocking App Behavior Analysis
- give reviewers a path that does not depend on a browser on another machine
- likely simplify the RP 2.1 conversation, since sign-in becomes a normal
  on-device credential flow

The browser pairing stays as the default; this is an alternative path, and it
is what `signin-credentials.rasp` below assumes.

Once that exists, the sign-in script becomes roughly:

```yaml
params:
    rasp_version: 1
    default_keypress_wait: 2

steps:
    - launch: dev
    - pause: 8
    - press: down          # move from "Connect to Server" to "Sign in"
    - press: ok
    - pause: 3
    - text: RokuTest       # username field
    - press: down
    - text: RokuTest       # password field
    - press: down
    - press: ok            # Sign in
    - pause: 12
```

## Before uploading

Record or replay both scripts in the Roku Remote tool
(<https://devtools.web.roku.com/RokuRemote/>) against the dev channel on a real
device. The dashboard links to it for exactly this reason, and a script that
desyncs by one keypress fails the analysis for reasons that look nothing like
the real cause.
