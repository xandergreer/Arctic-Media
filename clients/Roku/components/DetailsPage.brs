sub init()
    m.selectedBtn   = 0
    m.numBtns       = 1
    m.savedPosition = 0.0
    m.mediaId       = 0
    m.kind          = ""
    m.title         = ""
    m.hlsUrl        = ""
    m.posterUri     = ""

    m.poster         = m.top.findNode("poster")
    m.backdrop       = m.top.findNode("backdrop")
    m.titleLabel     = m.top.findNode("titleLabel")
    m.metaLabel      = m.top.findNode("metaLabel")
    m.overviewLabel  = m.top.findNode("overviewLabel")
    m.playBtn        = m.top.findNode("playBtn")
    m.playBtnLabel   = m.top.findNode("playBtnLabel")
    m.episodesBtn    = m.top.findNode("episodesBtn")
    m.episodesBtnLbl = m.top.findNode("episodesBtnLabel")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.top.observeField("params", "onParams")
    m.top.setFocus(true)
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return

    m.mediaId = p.mediaId
    m.kind    = p.kind
    m.title   = p.title
    m.titleLabel.text = m.title

    meta = ""
    yr = p.year
    if yr <> invalid then
        if yr <> "" then meta = yr
    end if
    if m.kind = "show" then
        if meta <> "" then meta = meta + "  -  "
        meta = meta + "TV Show"
    end if
    m.metaLabel.text = meta

    ov = p.overview
    if ov <> invalid then m.overviewLabel.text = ov

    pu = p.posterUrl
    if pu <> invalid then
        if pu <> "" then
            m.poster.uri   = pu
            m.backdrop.uri = pu
            m.posterUri    = pu
        end if
    end if

    m.hlsUrl = BuildHlsUrl(m.serverUrl, m.token, m.mediaId)

    if m.kind = "show" then
        m.episodesBtn.visible    = true
        m.episodesBtnLbl.visible = true
        m.numBtns = 2
    else
        m.numBtns = 1
    end if

    highlightBtn(0)
end sub

sub highlightBtn(idx as integer)
    m.selectedBtn = idx
    if idx = 0 then
        m.playBtn.color     = "0xFF4A9FFF"
        m.episodesBtn.color = "0xFF1A2A4A"
    else
        m.playBtn.color     = "0xFF1A2A4A"
        m.episodesBtn.color = "0xFF4A9FFF"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back" then
        m.top.navRequest = {action: "back"}
        return true
    end if

    if key = "OK" then
        req = {}
        req.action   = "play"
        req.mediaId  = m.mediaId
        req.title    = m.title
        req.url      = m.hlsUrl
        req.position = m.savedPosition
        m.top.navRequest = req
        return true
    end if

    if key = "options" then
        m.top.navRequest = {action: "signout"}
        return true
    end if

    return false
end function
