# Roku Channel Store — listing copy and reviewer notes

Draft for the public channel submission. Anything in `〔brackets〕` needs a real
value before submitting.

---

## Channel name

Arctic Media

## Short / tagline

Your library. Every screen.

## Category

**Movies & TV** (secondary: **Tools & Utilities** if a second slot is offered).

Not "Streaming Channels — Free", which implies a catalog we provide. This is a
client for a server the viewer already runs.

## Description

> Arctic Media is a player for your own media server.
>
> Point it at the Arctic Media server running on your own machine, pair the
> device once, and your movies and TV shows appear on the big screen — with
> artwork, descriptions, cast, and the episode you were halfway through waiting
> where you left it.
>
> **What you get**
>
> - Browse your movies and TV shows with posters, synopses, and cast
> - Continue Watching picks up mid-episode, on any device signed in to the same server
> - Season and episode browsing with thumbnails, runtimes, and per-episode progress
> - Search your whole library from the remote
> - Subtitles, when your files have them
> - Autoplay the next episode
> - Seek that accelerates when you hold the arrow, so you can move through a long film quickly
>
> **You need your own server.** Arctic Media does not host, provide, sell, or
> index any video. It plays only the files on the server you run and connect it
> to. Without your own Arctic Media server there is nothing for this channel to
> show.
>
> Setup takes about a minute: choose Connect to Server, type your server
> address, then approve the on-screen code from a browser.

## Privacy policy URL

https://github.com/xandergreer/Arctic-Media/blob/main/docs/PRIVACY.md

## Terms of use URL

https://github.com/xandergreer/Arctic-Media/blob/main/docs/TERMS.md

*(Both verified reachable, HTTP 200.)*

## Screenshots

**The dashboard asks for up to six 1920x1080 JPEG or PNG files** — not the
1280x720 the Utilities page mentions. This device captures a 720p UI plane (as
every non-4K Roku does), so the FHD set is necessarily an upscale: LANCZOS to
1920x1080 then `UnsharpMask(radius=1.2, percent=60, threshold=3)`, saved at
quality 95, subsampling 0.

Ready to upload, captured from build 46:
`~/Desktop/ArcticMedia-Store-Assets/screenshots-fhd-build46/`

1. `st01-home` — shelves with artwork and Continue Watching
2. `st02-movies` — movies grid
3. `st03-tvshows` — shows grid
4. `st04-details` — poster, synopsis, cast, Play/Browse Episodes
5. `st05-episodes` — season rail and episode cards
6. `st06-search` — keyboard with live results

**Do not use `screenshots-fhd-build37/` or `screenshots-hd-build37/`.** Those
predate the UI overhaul and show square-cornered cards, the old flat surfaces
and the outline focus state — they no longer resemble the app.

App poster: `~/Desktop/ArcticMedia-Store-Assets/poster_540x405.png`, already the
required 540x405.

---

# Notes to the reviewer

Paste this into the submission's reviewer-notes field. **Fill the bracketed
values first** — the test account is the single most common reason a channel
like this fails review, because without it the reviewer sees only a pairing
screen and cannot proceed.

> **What this channel is**
>
> Arctic Media is a client for a self-hosted personal media server, in the same
> category as a Plex or Jellyfin client. It streams a viewer's own media files
> from a server that viewer runs. The channel hosts no content, provides no
> catalog, and ships no media of its own. Every title you will see during review
> is a file on our own test server, placed there by us.
>
> We have deliberately not registered a search feed, because doing so would
> publish a private library into Roku universal search.
>
> **Test server and account**
>
> A server has been left running and reachable for the review period:
>
> - Server address: `arcticmedia.space`
> - Username: `〔test account username〕`
> - Password: `〔test account password〕`
>
> **How to sign in** (about a minute)
>
> 1. Launch the channel. On the welcome screen choose **Connect to Server**.
> 2. Enter the server address above and confirm.
> 3. The screen shows an 8-character pairing code.
> 4. In any browser, go to `https://arcticmedia.space/pair`, sign in with the
>    account above, and enter that code.
> 5. The channel picks up the authorization within a few seconds and opens to
>    the home screen.
>
> Pressing `*` (Options) on the pairing screen lets you re-enter the server
> address if it is mistyped.
>
> **Deep linking**
>
> Test values are configured on the public app's Deep Linking tab. Deep links
> resolve for the entire library at runtime, not just the registered samples —
> both a cold launch and a launch into a running channel are handled, and a
> deep-linked title resumes at the viewer's saved position.
>
> **Things worth knowing**
>
> - The server sleeps its drives when idle, so the very first request after a
>   quiet period can take a few seconds. Subsequent playback is immediate.
> - Playback quality adapts to the device. Sources the device cannot decode
>   natively are transcoded server-side, so playback should start on any Roku
>   model.
> - Signing out from Settings returns the device to the pairing screen, which is
>   the quickest way to re-test first-run setup.

---

## Pre-submission checklist

Verified in the build:

- [x] Icons 290x218 and 246x140 — **246 is correct**; the dashboard rejects 248x140
- [x] Splash 1920x1080 and 1280x720
- [x] All text and controls inside the 1080p title-safe box (x 96–1824, y 54–1026)
- [x] Deep linking on cold start and warm launch, with resume
- [x] Trick play: accelerating seek, pause, on-screen position
- [x] Playback verified end to end on a Roku Express 3930RW
- [x] Privacy and Terms URLs reachable

Still to do in the dashboard:

- [ ] Create the test account and put the credentials in the reviewer notes
- [ ] Point an uptime monitor at `https://arcticmedia.space/health` so the machine
      is warm when the reviewer opens the channel (`?warm=disks` also spins the
      media drives up)
- [ ] Re-enter deep-link test values — the public app is a separate entry from
      the beta app and does not inherit them
- [ ] Upload screenshots, description, category
