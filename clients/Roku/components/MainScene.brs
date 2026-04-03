sub init()
    m.pageStack = []
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

' -------------------------------------------------------
' Navigation
' -------------------------------------------------------

sub pushPage(pageName as string, params as dynamic)
    page = CreateObject("roSGNode", pageName)
    if page = invalid then return

    if params <> invalid
        page.params = params
    end if

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
        m.pageStack[m.pageStack.count() - 1].setFocus(true)
    end if
end sub

sub clearAndPush(pageName as string, params as dynamic)
    while m.pageStack.count() > 0
        page = m.pageStack.pop()
        m.top.removeChild(page)
    end while
    pushPage(pageName, params)
end sub

' -------------------------------------------------------
' Handle nav requests from child pages
' -------------------------------------------------------

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
        pushPage("VideoPage", req)

    else if action = "back"
        if m.pageStack.count() <= 1
            ' At root — do nothing (let user use Roku home button)
        else
            popPage()
        end if

    else if action = "signout"
        ClearAuth()
        serverUrl = GetReg("server_url")
        clearAndPush("PairingPage", {serverUrl: serverUrl})

    end if
end sub

' -------------------------------------------------------
' ECP deep-link (cast from iOS)
' -------------------------------------------------------

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

    hlsUrl = BuildHlsUrl(serverUrl, token, mediaId)
    req = {
        action:   "play"
        mediaId:  mediaId
        title:    "Loading…"
        url:      hlsUrl
        position: 0.0
    }
    pushPage("VideoPage", req)
end sub
