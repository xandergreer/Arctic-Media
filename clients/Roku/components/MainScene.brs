sub init()
    m.pageStack  = []

    m.top.observeField("navRequest",    "onNavRequest")
    m.top.observeField("launchContent", "onLaunchContent")
    m.top.backgroundColor = "0x0A0A1AFF"
    m.top.backgroundUri   = ""

    if IsAuthenticated()
        pushPage("HomePage", invalid)
    else
        serverUrl = GetReg("server_url")
        pushPage("PairingPage", {serverUrl: serverUrl})
    end if
end sub

' ── Navigation ────────────────────────────────────────────────────────────

sub pushPage(pageName as string, params as dynamic)
    page = CreateObject("roSGNode", pageName)
    if page = invalid then return
    if params <> invalid then page.params = params
    page.observeField("navRequest", "onNavRequest")
    m.top.appendChild(page)
    page.setFocus(true)
    m.pageStack.push(page)
end sub

sub popPage()
    if m.pageStack.count() <= 1 then return
    top = m.pageStack.pop()
    m.top.removeChild(top)
    if m.pageStack.count() > 0
        prevPage = m.pageStack[m.pageStack.count() - 1]
        prevPage.setFocus(true)
        ' Pages with internal focusable lists (SeasonPage, SearchPage) need to
        ' re-focus the right child — page-level focus alone leaves their lists
        ' deaf to up/down.
        if prevPage.hasField("restoreFocus")
            prevPage.restoreFocus = true
        end if
        ' Notify HomePage to refresh Continue Watching row
        if prevPage.hasField("onReturnedToHome")
            prevPage.onReturnedToHome = true
        end if
    end if
end sub

sub clearAndPush(pageName as string, params as dynamic)
    while m.pageStack.count() > 0
        page = m.pageStack.pop()
        m.top.removeChild(page)
    end while
    pushPage(pageName, params)
end sub

' ── Nav request dispatcher ────────────────────────────────────────────────

sub onNavRequest(event as object)
    req = event.getData()
    if req = invalid then return

    action = req.action

    if action = "home"
        clearAndPush("HomePage", invalid)

    else if action = "details"
        pushPage("DetailsPage", req)

    else if action = "episodes"
        pushPage("SeasonPage", req)

    else if action = "play"
        ' VideoPage is the SceneGraph Video-node player (OSD, subtitles, autoplay).
        pushPage("VideoPage", req)

    else if action = "back"
        if m.pageStack.count() > 1 then popPage()

    else if action = "search"
        pushPage("SearchPage", invalid)

    else if action = "signout"
        ' Tell server to delete the session row before clearing local credentials
        token     = GetReg("access_token")
        serverUrl = GetReg("server_url")
        if token <> "" and serverUrl <> ""
            q    = Chr(34)
            body = "{" + q + "access_token" + q + ":" + q + token + q + "}"
            ' Must go through a Task — roUrlTransfer is unavailable on the
            ' render thread. Fire-and-forget; we don't wait for the response.
            signoutTask = CreateObject("roSGNode", "ApiTask")
            signoutTask.url     = serverUrl + "/pair/signout"
            signoutTask.method  = "POST"
            signoutTask.reqBody = body
            signoutTask.control = "run"
            m.signoutTask = signoutTask
        end if
        ClearAuth()
        clearAndPush("PairingPage", {serverUrl: GetReg("server_url")})

    end if
end sub

' ── Deep-link (cast from iOS / voice launch) ──────────────────────────────

sub onLaunchContent(event as object)
    content = event.getData()
    if content = invalid then return
    token     = GetReg("access_token")
    serverUrl = GetReg("server_url")
    if token = "" or serverUrl = "" then return

    ' contentId arrives boxed from the node field (roString/roInt), so check
    ' interfaces rather than type() names.
    mediaId = 0
    cid = content.contentId
    if cid <> invalid
        if GetInterface(cid, "ifString") <> invalid
            mediaId = cid.ToInt()
        else if GetInterface(cid, "ifInt") <> invalid
            mediaId = cid
        end if
    end if
    if mediaId = 0 then return

    ' Before playing, look up this title's saved resume position so a deep link
    ' picks up where the user left off (e.g. started on the iOS app). The
    ' history fetch has to run on a Task thread — roUrlTransfer is unavailable
    ' on the render thread — so playback continues in onDeepLinkHistory once the
    ' position is known.
    m.pendingDeepLink = {mediaId: mediaId, serverUrl: serverUrl, token: token}
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = serverUrl + "/api/v1/history"
    task.token = token
    task.observeField("resultArr", "onDeepLinkHistory")
    task.observeField("apiError",  "onDeepLinkHistoryError")
    task.observeField("state",     "onDeepLinkTaskState")
    task.control = "run"
    m.deepLinkTask = task
end sub

sub onDeepLinkHistory(event as object)
    rows = event.getData()
    if rows = invalid then return
    ' alwaysNotify fields can fire once with an empty payload the moment the
    ' observer attaches; a genuinely empty history still plays — from 0:00 —
    ' via onDeepLinkTaskState when the task finishes.
    if rows.count() = 0 then return
    if m.pendingDeepLink = invalid then return
    posSec = 0.0
    for each row in rows
        rowId = row.media_id
        if rowId <> invalid and rowId = m.pendingDeepLink.mediaId
            if row.position_seconds <> invalid then posSec = row.position_seconds
            exit for
        end if
    end for
    playDeepLink(posSec)
end sub

sub onDeepLinkTaskState(event as object)
    ' Fallback: task finished but no usable history row consumed the pending
    ' deep link (empty history, or resultArr never fired). Play from the start.
    st = event.getData()
    if (st = "done" or st = "stop") and m.pendingDeepLink <> invalid
        playDeepLink(0.0)
    end if
end sub

sub onDeepLinkHistoryError(event as object)
    ' History unavailable — play from the start rather than not at all.
    playDeepLink(0.0)
end sub

' Push the VideoPage for a resolved deep link. Same SceneGraph player as normal
' playback, so it keeps the OSD, subtitles and next-episode autoplay.
sub playDeepLink(position as dynamic)
    if m.pendingDeepLink = invalid then return
    dl = m.pendingDeepLink
    m.pendingDeepLink = invalid

    ' Warm deep link while something is already playing: tear the old player
    ' down first so we don't stack two Video nodes (double audio + bandwidth).
    if m.pageStack.count() > 0
        topPage = m.pageStack[m.pageStack.count() - 1]
        if topPage.subtype() = "VideoPage"
            m.pageStack.pop()
            m.top.removeChild(topPage)
        end if
    end if

    #if DEBUG_ENABLED
        print "[deeplink] mediaId="; dl.mediaId; " resume position="; position
    #end if

    pushPage("VideoPage", {
        action:   "play"
        mediaId:  dl.mediaId
        title:    "Loading…"
        url:      BuildHlsUrl(dl.serverUrl, dl.token, dl.mediaId)
        position: position
    })
end sub
