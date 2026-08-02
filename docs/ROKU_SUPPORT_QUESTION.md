# Roku Partner Success request — RP 2.1 / getUserData

**Where to send it:** <https://developer.roku.com/contact> (Partner Success
Contact Form). Roku says they follow up within two business days.

Both text fields are capped at **1000 characters**, so the copy below is written
to fit. Character counts are noted; do not pad them.

## Form fields

| Field | Value |
|---|---|
| **Topic** | `App` → **`Certification`** |
| **Email Address** | xandergreer03@gmail.com |
| **App Name** | Arctic Media |
| **Email CC** | *(leave blank, or add a second address you check)* |

---

### App Details  — 964 / 1000

```
Channel ID 876256 (Arctic Media, unpublished public app). Beta channel is
875693.

Arctic Media is a client for a personal media server that the viewer runs on
their own hardware - the same category as a Plex or Jellyfin client. It hosts
no content, ships no catalog, and I operate no service of any kind.

Authentication is always against the viewer's own server, by one of two paths:

1. Device-code pairing. The channel displays a code; the viewer approves it at
   /pair in a browser while signed in to their own server, which returns a
   token.
2. Username and password for that same server, exchanged for a token by that
   server's own auth endpoint.

I hold no user accounts and never receive those credentials. There is no
sign-up, no subscription, and no payment. Monetization is set to "I will not be
monetizing my app".

A test account and step-by-step sign-in instructions are in the reviewer notes,
and the server is reachable for the review period.
```

### Description  — 968 / 1000

```
Static analysis returns:

"All authenticated channels must use the Request for Information (getUserData)
API call to obtain a user's email address during the sign-up or sign-in flow."
(RP 2.1, RP 4.1)

getUserData returns the viewer's Roku account email, which has no relationship
to their account on their own self-hosted server and cannot authenticate
against a server I do not operate. The channel has nothing it could do with it.

Questions:

1. Does RP 2.1 / 4.1 apply to a channel that authenticates only against the
viewer's own server, where the developer holds no accounts?

2. If not, how should I declare that? "Can users sign in to your app?" is Yes,
because that setting exposes the Test Credentials page reviewers need. Setting
it to No clears the error but removes reviewer access.

3. Static analysis also warns I have a Customer Account Requirement but am not
enrolled in Roku Partner Payouts. Is that expected for a free channel with no
monetization?
```

---

## Before you send

- **Topic matters.** `Certification` routes to the team that owns RP 2.1.
  `Technical Issues → Other` will bounce around.
- Question 3 is worth keeping in. Partner Payouts means tax and banking details
  for a channel that moves no money — if that requirement is also a side effect
  of the account-requirement flag, one answer resolves both warnings.
- Do not soften question 2. The bind is real: the setting that clears the error
  is the same one that gives reviewers a way in, and they should be the ones to
  say which they want.

## If they say the requirement applies

It is a small change — a `ChannelStore` node in the pairing flow:

```brightscript
m.store = CreateObject("roSGNode", "ChannelStore")
m.store.observeField("userData", "onUserData")
m.store.command = "getUserData"
```

`userData` returns the viewer's Roku account email/name once they approve the
system prompt. It would sit alongside the existing sign-in rather than replace
it, since the server still needs its own token.

## If they say it does not

Ask them to note the exemption on the channel record before you submit, so the
reviewer is not surprised by the same static-analysis error you were told to
ignore.
