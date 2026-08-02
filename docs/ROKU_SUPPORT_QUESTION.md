# Message to Roku developer support

Send via https://developer.roku.com/contact before building anything against
RP 2.1 — the answer decides whether `getUserData` needs implementing at all.

---

**Subject:** RP 2.1 / getUserData applicability for a self-hosted personal media
server client (Channel 876256, Arctic Media)

Hello,

Static analysis on channel 876256 (Arctic Media, unpublished) returns an error
I would like guidance on before I implement against it:

> All authenticated channels must use the Request for Information (getUserData)
> API call to obtain a user's email address during the sign-up or sign-in flow.
> (RP 2.1, RP 4.1)

I believe this may not apply to my channel's architecture, and I would rather
confirm than guess.

**What the channel is.** Arctic Media is a client for a personal media server
that the viewer runs on their own hardware — the same category as a Plex or
Jellyfin client. I do not operate a service, host any content, or hold any user
accounts. There is no sign-up, no subscription, and no payment of any kind.

**What the "sign-in" actually is.** The channel offers two ways in, and neither
involves an account I hold:

1. *Device-code pairing (default).* The viewer enters the address of their own
   server; the channel shows an 8-character code; the viewer approves it in a
   browser while signed in to their own server, and that server returns a token.
2. *Username and password (added so certification can automate it).* The viewer
   types the credentials for their own server, which the channel exchanges for a
   token against that server's own auth endpoint.

In both cases the credentials belong to the viewer's own machine. I never see
them, never store them, and hold no account database of any kind.

**Why `getUserData` does not help here.** It returns the viewer's *Roku account*
email. That has no relationship to the account on their self-hosted server, and
the channel has nothing it could do with it — it cannot be used to authenticate
against a server I do not operate. Prompting for it would ask viewers to share
personal data with a channel that has no use for it, which seems like the
opposite of what the requirement intends.

**My questions:**

1. Does RP 2.1 / RP 4.1 apply to a channel that authenticates against the
   viewer's own self-hosted server, where the developer holds no accounts and
   the Roku account email cannot be used for authentication?
2. If it does not, what is the correct way to declare this? I currently have
   "Can users sign in to your app?" set to Yes, because the channel does have an
   authentication step and because that setting is what exposes the Test
   Credentials page a reviewer needs. Setting it to No clears the error but also
   removes my ability to give reviewers working credentials.
3. Related: static analysis also warns that I have a Customer Account
   Requirement but am not enrolled in the Roku Partner Payouts Program. As a
   free channel with no monetization of any kind, is that enrollment genuinely
   expected, or is it a consequence of the same declaration?

A test account and full pairing instructions are ready in the reviewer notes,
and the server is reachable for review.

Thank you,
Xander Greer
Channel 876256

---

## If Roku says the requirement does apply

Implementing it is small — a `ChannelStore` node in the pairing flow:

```brightscript
m.store = CreateObject("roSGNode", "ChannelStore")
m.store.observeField("userData", "onUserData")
m.store.command = "getUserData"
```

`userData` comes back with the viewer's Roku account email/name once they
approve the system prompt. It would sit alongside the existing pairing step
rather than replacing it, since the server still needs its own token.

## If Roku says it does not

Ask them to note the exemption on the channel record before submitting, so the
reviewer is not surprised by the same static-analysis error.
