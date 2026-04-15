sub init()
    m.video          = m.top.findNode("video")
    m.osd            = m.top.findNode("osd")
    m.osdEpLabel     = m.top.findNode("osdEpLabel")
    m.osdTitle       = m.top.findNode("osdTitle")
    m.osdState       = m.top.findNode("osdState")
    m.seekFill       = m.top.findNode("seekFill")
    m.seekDot        = m.top.findNode("seekDot")
    m.osdCurrentTime = m.top.findNode("osdCurrentTime")
    m.osdTotalTime   = m.top.findNode("osdTotalTime")
    m.subtitlePanel  = m.top.findNode("subtitlePanel")
    m.subItems       = [m.top.findNode("subItem0"), m.top.findNode("subItem1")]
    m.subLabels      = [m.top.findNode("subLabel0"), m.top.findNode("subLabel1")]
    m.autoplayPanel        = m.top.findNode("autoplayPanel")
    m.autoplayTitle        = m.top.findNode("autoplayTitle")
    m.autoplayLabel        = m.top.findNode("autoplayLabel")
    m.autoplayCountdownBar = m.top.findNode("autoplayCountdownBar")
    m.seekOverlay      = m.top.findNode("seekOverlay")
    m.seekDeltaLabel   = m.top.findNode("seekDeltaLabel")
    m.seekPosLabel     = m.top.findNode("seekPosLabel")

    m.serverUrl  = GetReg("server_url")
    m.token      = GetReg("access_token")
    m.mediaId    = 0
    m.lastPos    = 0.0
    m.totalDur   = 0.0
    m.osdVisible = false
    m.videoSetup = false

    m.episodeList  = invalid
    m.episodeIdx   = -1
    m.autoplayIdx  = -1
    m.autoplaySecs = 0
    m.autoplaying  = false
    m.upNextShown  = false
    m.seekAccum    = 0
    m.seekPresses  = 0   ' consecutive seek presses for acceleration
    m.showId       = 0
    m.cwSeasonNum  = 0
    m.cwEpisodeNum = 0
    m.episodeLabel = ""

    m.ccEnabled        = (GetReg("subtitles") = "On")
    m.subtitleMenuOpen = false
    m.subFocusIdx      = 0

    m.hideTimer = CreateObject("roSGNode", "Timer")
    m.hideTimer.duration = 5
    m.hideTimer.repeat   = false
    m.hideTimer.observeField("fire", "onHideTimer")

    m.osdTimer = CreateObject("roSGNode", "Timer")
    m.osdTimer.duration = 1
    m.osdTimer.repeat   = true
    m.osdTimer.observeField("fire", "onOsdTimer")
    m.osdTimer.control = "start"

    m.autoplayTimer = CreateObject("roSGNode", "Timer")
    m.autoplayTimer.duration = 1
    m.autoplayTimer.repeat   = true
    m.autoplayTimer.observeField("fire", "onAutoplayTimer")

    m.seekHideTimer = CreateObject("roSGNode", "Timer")
    m.seekHideTimer.duration = 2
    m.seekHideTimer.repeat   = false
    m.seekHideTimer.observeField("fire", "onSeekHideTimer")

    m.seekResetTimer = CreateObject("roSGNode", "Timer")
    m.seekResetTimer.duration = 1.5
    m.seekResetTimer.repeat   = false
    m.seekResetTimer.observeField("fire", "onSeekResetTimer")

    m.top.observeField("params", "onParams")
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return
    m.mediaId = p.mediaId
    m.upNextShown = false

    ' Episode label (e.g. "S1 E3") — shown left of title in OSD
    m.episodeLabel = ""
    el = p.episodeLabel
    if el <> invalid and el <> "" then m.episodeLabel = el
    updateOsdHeader(p.title)

    if p.episodeList <> invalid then m.episodeList = p.episodeList
    if p.episodeIdx  <> invalid then m.episodeIdx  = p.episodeIdx

    ' CW play: no episodeList yet — fetch it in background so autoplay works
    if m.episodeList = invalid and p.showId <> invalid and p.showId > 0 then
        m.showId      = p.showId
        m.cwSeasonNum = 0
        m.cwEpisodeNum = 0
        if p.seasonNumber <> invalid then m.cwSeasonNum  = p.seasonNumber
        if p.episodeNumber <> invalid then m.cwEpisodeNum = p.episodeNumber
        fetchEpisodeListBg()
    end if

    ' Seed total duration from params so the seek bar is correct from frame 1
    durParam = p.durationSeconds
    if durParam <> invalid and durParam > 0 then m.totalDur = durParam

    cn = CreateObject("roSGNode", "ContentNode")
    cn.url          = p.url
    cn.title        = p.title
    cn.streamFormat = "hls"
    m.video.content = cn

    if not m.videoSetup
        m.video.observeField("state",    "onStateChange")
        m.video.observeField("position", "onPositionChange")
        m.video.observeField("duration", "onDurationChange")
        m.videoSetup = true
    end if

    startPos = p["position"]
    if startPos = invalid then startPos = 0.0
    if startPos > 30 then m.video.seek = Int(startPos)

    applySubtitlePref()
    m.video.control = "play"
    m.top.setFocus(true)

    m.saveTimer = CreateObject("roSGNode", "Timer")
    m.saveTimer.duration = 15
    m.saveTimer.repeat   = true
    m.saveTimer.observeField("fire", "onSaveTimer")
    m.saveTimer.control = "start"
end sub

' -------------------------------------------------------
' Background episode-list fetch (for CW plays)
' -------------------------------------------------------

sub fetchEpisodeListBg()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/shows/" + m.showId.ToStr() + "/seasons"
    task.token = m.token
    task.observeField("resultArr", "onBgSeasonsResult")
    task.control = "run"
    m.bgSeasonsTask = task
end sub

sub onBgSeasonsResult(event as object)
    data = event.getData()
    if data = invalid or data.count() = 0 then return

    ' Find season matching m.cwSeasonNum; fall back to first season
    seasonId = data[0].id
    for each s in data
        if s.season_number = m.cwSeasonNum then
            seasonId = s.id
            exit for
        end if
    end for

    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/seasons/" + seasonId.ToStr() + "/episodes"
    task.token = m.token
    task.observeField("resultArr", "onBgEpisodesResult")
    task.control = "run"
    m.bgEpisodesTask = task
end sub

sub onBgEpisodesResult(event as object)
    data = event.getData()
    if data = invalid or data.count() = 0 then return
    m.episodeList = data

    ' Find our current episode index by id
    for i = 0 to data.count() - 1
        ep = data[i]
        if ep.id = m.mediaId then
            m.episodeIdx = i
            exit for
        end if
    end for
end sub

sub updateOsdHeader(title as string)
    if m.episodeLabel <> "" then
        m.osdEpLabel.text = m.episodeLabel
        m.osdEpLabel.width = 150
        m.osdTitle.text = title
        m.osdTitle.translation = [200, 22]
        m.osdTitle.width = 1140
    else
        m.osdEpLabel.text = ""
        m.osdTitle.text = title
        m.osdTitle.translation = [40, 22]
        m.osdTitle.width = 1300
    end if
end sub

sub applySubtitlePref()
    if m.ccEnabled
        m.video.captionMode = "On"
    else
        m.video.captionMode = "Off"
    end if
end sub

' -------------------------------------------------------
' Subtitle panel
' -------------------------------------------------------

sub openSubtitleMenu()
    m.subtitleMenuOpen = true
    m.subFocusIdx = 0
    if m.ccEnabled then m.subFocusIdx = 1
    updateSubtitleMenu()
    m.subtitlePanel.visible = true
    m.hideTimer.control = "stop"
end sub

sub closeSubtitleMenu()
    m.subtitleMenuOpen      = false
    m.subtitlePanel.visible = false
    if m.osdVisible
        m.hideTimer.control = "stop"
        m.hideTimer.control = "start"
    end if
end sub

sub updateSubtitleMenu()
    for i = 0 to 1
        if i = m.subFocusIdx
            m.subItems[i].color  = "0x152840FF"
            m.subLabels[i].color = "0xFFFFFFFF"
        else
            m.subItems[i].color  = "0x0A0A20FF"
            m.subLabels[i].color = "0xCCCCCCFF"
        end if
    end for
end sub

sub applySubtitleSelection()
    m.ccEnabled = (m.subFocusIdx = 1)
    if m.ccEnabled
        SetReg("subtitles", "On")
    else
        SetReg("subtitles", "Off")
    end if
    applySubtitlePref()
end sub

' -------------------------------------------------------
' Seek overlay
' -------------------------------------------------------

sub showSeekOverlay(delta as integer)
    m.seekAccum = m.seekAccum + delta

    absDelta = m.seekAccum
    if absDelta < 0 then absDelta = -absDelta

    if m.seekAccum < 0 then
        m.seekDeltaLabel.text = "<< " + FormatSeekDelta(absDelta)
    else
        m.seekDeltaLabel.text = ">>" + " " + FormatSeekDelta(absDelta)
    end if

    posStr = FormatVideoTime(Int(m.lastPos))
    if m.totalDur > 0 then
        m.seekPosLabel.text = posStr + "  /  " + FormatVideoTime(Int(m.totalDur))
    else
        m.seekPosLabel.text = posStr
    end if

    m.seekOverlay.visible = true
    m.seekHideTimer.control = "stop"
    m.seekHideTimer.control = "start"
end sub

sub onSeekHideTimer(event as object)
    m.seekOverlay.visible = false
    m.seekAccum = 0
end sub

function FormatSeekDelta(secs as integer) as string
    if secs < 60 then return secs.ToStr() + "s"
    mins = secs \ 60
    s    = secs mod 60
    if s < 10 then return mins.ToStr() + ":0" + s.ToStr()
    return mins.ToStr() + ":" + s.ToStr()
end function

' -------------------------------------------------------
' Seek helper
' -------------------------------------------------------

' Accelerating seek: 1-2 presses=10s, 3-5=30s, 6-9=60s, 10+=120s
function seekAmount() as integer
    p = m.seekPresses
    if p <= 2  then return 10
    if p <= 5  then return 30
    if p <= 9  then return 60
    return 120
end function

function seekBy(direction as integer) as integer
    ' direction is +1 or -1
    m.seekPresses = m.seekPresses + 1
    m.seekResetTimer.control = "stop"
    m.seekResetTimer.control = "start"

    amount   = seekAmount() * direction
    newPos   = Int(m.lastPos) + amount
    if newPos < 0 then newPos = 0
    if m.totalDur > 0 and newPos > m.totalDur then newPos = Int(m.totalDur)
    m.video.seek = newPos
    m.lastPos    = newPos
    updateOsd()
    return amount
end function

sub onSeekResetTimer(event as object)
    m.seekPresses = 0
end sub

' -------------------------------------------------------
' State / position
' -------------------------------------------------------

sub onStateChange(event as object)
    s = event.getData()
    if s = "playing" then m.top.setFocus(true)
    if s = "finished"
        doSaveProgress()
        if m.autoplaying
            ' Toast already showing — let the countdown timer call playNext() naturally.
            ' Stopping the timer here would kill the countdown the user is watching.
        else
            checkAutoplay()
        end if
        return
    end if
    if s = "error" then exitPlayer()
    updateOsd()
    if s = "paused" and m.osdVisible
        m.hideTimer.control = "stop"
    end if
end sub

sub checkAutoplay()
    if m.episodeList = invalid
        exitPlayer()
        return
    end if
    nextIdx = m.episodeIdx + 1
    if nextIdx >= m.episodeList.count()
        exitPlayer()
        return
    end if
    startAutoplayCountdown(nextIdx)
end sub

sub startAutoplayCountdown(nextIdx as integer)
    m.autoplayIdx  = nextIdx
    m.autoplaySecs = 5
    m.autoplaying  = true
    nextEp = m.episodeList[nextIdx]
    m.autoplayTitle.text = nextEp.title
    updateAutoplayLabel()
    m.autoplayPanel.visible = true
    m.autoplayTimer.control = "start"
end sub

sub onAutoplayTimer(event as object)
    m.autoplaySecs = m.autoplaySecs - 1
    if m.autoplaySecs <= 0
        m.autoplayTimer.control = "stop"
        playNext()
        return
    end if
    updateAutoplayLabel()
end sub

sub updateAutoplayLabel()
    m.autoplayLabel.text = "Playing in " + m.autoplaySecs.ToStr() + "s..."
    barW = Int(m.autoplaySecs / 5.0 * 556)
    if barW < 0 then barW = 0
    m.autoplayCountdownBar.width = barW
end sub

sub playNext()
    m.autoplaying = false
    m.upNextShown = false
    m.autoplayPanel.visible = false
    nextEp       = m.episodeList[m.autoplayIdx]
    m.episodeIdx = m.autoplayIdx
    m.mediaId    = nextEp.id
    m.lastPos    = 0.0
    m.totalDur   = 0.0
    if nextEp.duration_seconds <> invalid and nextEp.duration_seconds > 0 then
        m.totalDur = nextEp.duration_seconds
    end if
    ' Build episode label for the next episode
    m.episodeLabel = ""
    epNum = nextEp.episode_number
    snNum = nextEp.season_number
    if epNum <> invalid and snNum <> invalid then
        m.episodeLabel = "S" + snNum.ToStr() + " E" + epNum.ToStr()
    else if epNum <> invalid then
        m.episodeLabel = "E" + epNum.ToStr()
    end if
    updateOsdHeader(nextEp.title)
    m.osdCurrentTime.text = "0:00"
    m.osdTotalTime.text   = ""
    m.seekFill.width      = 0
    m.seekDot.translation = [53, 914]
    hlsUrl = BuildHlsUrl(m.serverUrl, m.token, m.mediaId)
    cn = CreateObject("roSGNode", "ContentNode")
    cn.url          = hlsUrl
    cn.title        = nextEp.title
    cn.streamFormat = "hls"
    m.video.control = "stop"
    m.video.content = cn
    applySubtitlePref()
    m.video.control = "play"
    m.top.setFocus(true)
end sub

sub cancelAutoplay()
    m.autoplaying = false
    m.upNextShown = false
    m.autoplayTimer.control = "stop"
    m.autoplayPanel.visible = false
    exitPlayer()
end sub

sub onDurationChange(event as object)
    dur = event.getData()
    if dur = invalid then return
    if dur > m.totalDur then m.totalDur = dur
end sub

sub onPositionChange(event as object)
    m.lastPos = event.getData()

    ' Show Up Next toast when ≤30s remain — plays next after 5s countdown
    if not m.autoplaying and not m.upNextShown and m.totalDur > 60 then
        remaining = m.totalDur - m.lastPos
        if remaining > 0 and remaining <= 30 then
            if m.episodeList <> invalid then
                nextIdx = m.episodeIdx + 1
                if nextIdx < m.episodeList.count() then
                    m.upNextShown = true
                    startAutoplayCountdown(nextIdx)
                end if
            end if
        end if
    end if
end sub

sub onSaveTimer(event as object)
    doSaveProgress()
end sub

sub exitPlayer()
    if m.saveTimer     <> invalid then m.saveTimer.control     = "stop"
    if m.osdTimer      <> invalid then m.osdTimer.control      = "stop"
    if m.hideTimer     <> invalid then m.hideTimer.control     = "stop"
    if m.autoplayTimer <> invalid then m.autoplayTimer.control = "stop"
    if m.seekHideTimer <> invalid then m.seekHideTimer.control = "stop"
    doSaveProgress()
    m.top.navRequest = {action: "back"}
end sub

sub doSaveProgress()
    if m.mediaId = 0 then return
    if m.lastPos <= 0 then return
    posInt = Int(m.lastPos)
    durInt = Int(m.totalDur)
    q = Chr(34)
    body = "{" + q + "position_seconds" + q + ":" + posInt.ToStr() + "," + q + "duration_seconds" + q + ":" + durInt.ToStr() + "}"
    task = CreateObject("roSGNode", "ApiTask")
    task.url     = m.serverUrl + "/api/v1/history/" + m.mediaId.ToStr()
    task.method  = "POST"
    task.token   = m.token
    task.reqBody = body
    task.control = "run"
end sub

' -------------------------------------------------------
' OSD show / hide / update
' -------------------------------------------------------

sub showOsd()
    m.osdVisible  = true
    m.osd.visible = true
    updateOsd()
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub hideOsd()
    m.osdVisible  = false
    m.osd.visible = false
    m.hideTimer.control = "stop"
end sub

sub onHideTimer(event as object)
    if m.video.state = "paused"
        m.hideTimer.control = "start"
        return
    end if
    hideOsd()
end sub

sub onOsdTimer(event as object)
    updateOsd()
end sub

sub updateOsd()
    if not m.osdVisible then return

    curPos = m.lastPos
    dur    = m.totalDur

    m.osdCurrentTime.text = FormatVideoTime(Int(curPos))
    if dur > 0
        m.osdTotalTime.text = FormatVideoTime(Int(dur))
        pct = curPos / dur
        if pct < 0.0 then pct = 0.0
        if pct > 1.0 then pct = 1.0
        fillW = Int(pct * 1800)
        m.seekFill.width      = fillW
        m.seekDot.translation = [53 + fillW, 914]
    end if

    state = m.video.state
    if state = "paused"
        m.osdState.text  = "PAUSED"
        m.osdState.color = "0x4A9FFFFF"
    else if state = "buffering" or state = "connecting"
        m.osdState.text  = "BUFFERING"
        m.osdState.color = "0xFFAA00FF"
    else
        m.osdState.text = ""
    end if
end sub

' -------------------------------------------------------
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' ── Subtitle panel captures all keys ──────────────────
    if m.subtitleMenuOpen
        if key = "back"
            closeSubtitleMenu()
        else if key = "up"
            if m.subFocusIdx > 0
                m.subFocusIdx = m.subFocusIdx - 1
                updateSubtitleMenu()
            end if
        else if key = "down"
            if m.subFocusIdx < 1
                m.subFocusIdx = m.subFocusIdx + 1
                updateSubtitleMenu()
            end if
        else if key = "OK"
            applySubtitleSelection()
            closeSubtitleMenu()
        end if
        return true
    end if

    ' ── Back ──────────────────────────────────────────────
    if key = "back"
        if m.autoplaying
            cancelAutoplay()
            return true
        end if
        if m.osdVisible
            hideOsd()
        else
            m.video.control = "stop"
            exitPlayer()
        end if
        return true
    end if

    ' ── Autoplay: OK plays next immediately ───────────────
    if (key = "OK" or key = "play") and m.autoplaying
        m.autoplayTimer.control = "stop"
        playNext()
        return true
    end if

    ' ── Options: open subtitle panel ──────────────────────
    if key = "options"
        showOsd()
        openSubtitleMenu()
        return true
    end if

    ' ── Left: seek backward (accelerating) ───────────────
    if key = "left"
        delta = seekBy(-1)
        showSeekOverlay(delta)
        showOsd()
        return true
    end if

    ' ── Right: seek forward (accelerating) ────────────────
    if key = "right"
        delta = seekBy(1)
        showSeekOverlay(delta)
        showOsd()
        return true
    end if

    ' ── OK / Play: toggle play/pause ──────────────────────
    if key = "OK" or key = "play"
        if m.video.state = "paused"
            m.video.control = "resume"
        else
            m.video.control = "pause"
        end if
        showOsd()
        updateOsd()
        return true
    end if

    ' ── Up / Down: show OSD ───────────────────────────────
    if key = "up" or key = "down"
        showOsd()
        return true
    end if

    ' ── Physical FF / RW: seek (accelerating) ────────────
    if key = "rev"
        delta = seekBy(-1)
        showSeekOverlay(delta)
        showOsd()
        return true
    end if

    if key = "fwd"
        delta = seekBy(1)
        showSeekOverlay(delta)
        showOsd()
        return true
    end if

    ' ── Down: skip to next episode ────────────────────────
    if key = "down"
        if m.episodeList <> invalid then
            nextIdx = m.episodeIdx + 1
            if nextIdx < m.episodeList.count() then
                doSaveProgress()
                m.autoplayIdx = nextIdx
                m.autoplayTimer.control = "stop"
                m.autoplaying = true
                playNext()
                return true
            end if
        end if
        showOsd()
        return true
    end if

    showOsd()
    return false
end function
