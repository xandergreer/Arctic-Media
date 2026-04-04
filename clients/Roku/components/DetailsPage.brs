sub init()
    m.selectedBtn   = 0
    m.numBtns       = 1
    m.savedPosition = 0.0
    m.mediaId       = 0
    m.kind          = ""
    m.title         = ""
    m.hlsUrl        = ""

    m.poster          = m.top.findNode("poster")
    m.backdrop        = m.top.findNode("backdrop")
    m.titleLabel      = m.top.findNode("titleLabel")
    m.metaLabel       = m.top.findNode("metaLabel")
    m.overviewLabel   = m.top.findNode("overviewLabel")
    m.playBtn         = m.top.findNode("playBtn")
    m.playBtnLabel    = m.top.findNode("playBtnLabel")
    m.episodesBtn     = m.top.findNode("episodesBtn")
    m.episodesBtnLbl  = m.top.findNode("episodesBtnLabel")

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

    ' Meta line: "2024  ·  Movie" or "TV Show" etc.
    meta = ""
    yr = p.year
    if yr <> invalid and yr <> "" then meta = yr
    if m.kind = "show"
        if meta <> "" then meta = meta + "  ·  "
        meta = meta + "TV Show"
    else if m.kind = "movie"
        if meta <> "" then meta = meta + "  ·  "
        meta = meta + "Movie"
    end if
    m.metaLabel.text = meta

    ov = p.overview
    if ov <> invalid then m.overviewLabel.text = ov

    m.posterUri = ""
    pu = p.posterUrl
    if pu <> invalid and pu <> ""
        m.poster.uri   = pu
        m.backdrop.uri = pu
        m.posterUri    = pu
    end if

    m.hlsUrl = BuildHlsUrl(m.serverUrl, m.token, m.mediaId)

    if m.kind = "show"
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
    if idx = 0
        m.playBtn.color     = "0x4A9FFFFF"
        m.episodesBtn.color = "0x1A2A4AFF"
        m.playBtnLabel.color     = "0xFFFFFFFF"
        m.episodesBtnLbl.color   = "0xCCCCCCFF"
    else
        m.playBtn.color     = "0x1A2A4AFF"
        m.episodesBtn.color = "0x4A9FFFFF"
        m.playBtnLabel.color     = "0xCCCCCCFF"
        m.episodesBtnLbl.color   = "0xFFFFFFFF"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        m.top.navRequest = {action: "back"}
        return true
    end if

    if key = "left" and m.selectedBtn = 1
        highlightBtn(0)
        return true
    end if

    if key = "right" and m.selectedBtn = 0 and m.numBtns > 1
        highlightBtn(1)
        return true
    end if

    if key = "OK"
        if m.selectedBtn = 1
            m.top.navRequest = {action: "episodes", showId: m.mediaId, title: m.title, posterUrl: m.posterUri}
        else
            m.top.navRequest = {
                action:   "play"
                mediaId:  m.mediaId
                title:    m.title
                url:      m.hlsUrl
                position: m.savedPosition
            }
        end if
        return true
    end if

    if key = "options"
        m.top.navRequest = {action: "signout"}
        return true
    end if

    return false
end function
