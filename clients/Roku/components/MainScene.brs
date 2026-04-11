sub init()
    m.pageStack  = []
    m.videoTask  = invalid

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
        ' VideoPage uses SceneGraph Video node (guaranteed to work).
        ' Swap for runVideoTask(req) to test native roVideoScreen OSD instead.
        pushPage("VideoPage", req)

    else if action = "back"
        if m.pageStack.count() > 1 then popPage()

    else if action = "search"
        pushPage("SearchPage", invalid)

    else if action = "signout"
        ClearAuth()
        clearAndPush("PairingPage", {serverUrl: GetReg("server_url")})

    end if
end sub

' ── Video Task (roVideoScreen with native OSD) ────────────────────────────

sub runVideoTask(req as object)
    ' Stop any existing task
    if m.videoTask <> invalid
        m.videoTask.control = "stop"
        m.videoTask = invalid
    end if

    task = CreateObject("roSGNode", "VideoTask")
    task.mediaId    = req.mediaId
    task.title      = req.title
    task.hlsUrl     = req.url
    task.startSec   = req.position
    if req.episodeList <> invalid then task.episodes   = req.episodeList
    if req.episodeIdx  <> invalid then task.episodeIdx = req.episodeIdx
    task.observeField("done",    "onVideoTaskDone")
    task.observeField("nextIdx", "onVideoTaskNext")
    task.control = "run"
    m.videoTask = task
end sub

sub onVideoTaskDone(event as object)
    if event.getData() = true
        m.videoTask = invalid
        ' Restore focus to the top page in our stack
        if m.pageStack.count() > 0
            m.pageStack[m.pageStack.count() - 1].setFocus(true)
        end if
    end if
end sub

sub onVideoTaskNext(event as object)
    nextIdx = event.getData()
    if nextIdx < 0 then return
    ' The task already has the episode list — just restart with new index
    if m.videoTask = invalid then return
    episodes = m.videoTask.episodes
    if episodes = invalid then return
    if nextIdx >= episodes.count() then return

    ep = episodes[nextIdx]
    serverUrl = GetReg("server_url")
    token     = GetReg("access_token")
    req = {
        action:      "play"
        mediaId:     ep.id
        title:       ep.title
        url:         BuildHlsUrl(serverUrl, token, ep.id)
        position:    0.0
        episodeList: episodes
        episodeIdx:  nextIdx
    }
    runVideoTask(req)
end sub

' ── ECP deep-link (cast from iOS) ─────────────────────────────────────────

sub onLaunchContent(event as object)
    content = event.getData()
    if content = invalid then return
    token     = GetReg("access_token")
    serverUrl = GetReg("server_url")
    if token = "" or serverUrl = "" then return

    mediaId = 0
    if type(content.contentId) = "String"
        mediaId = content.contentId.ToInt()
    else if type(content.contentId) = "Integer"
        mediaId = content.contentId
    end if
    if mediaId = 0 then return

    runVideoTask({
        mediaId:  mediaId
        title:    "Loading…"
        url:      BuildHlsUrl(serverUrl, token, mediaId)
        position: 0.0
    })
end sub
