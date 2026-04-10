sub init()
    m.video          = m.top.findNode("video")
    m.osd            = m.top.findNode("osd")
    m.osdTitle       = m.top.findNode("osdTitle")
    m.osdState       = m.top.findNode("osdState")
    m.osdBtn0Bg      = m.top.findNode("osdBtn0Bg")
    m.osdBtn0Lbl     = m.top.findNode("osdBtn0Lbl")
    m.osdPlayBg      = m.top.findNode("osdPlayBg")
    m.osdPlayIcon    = m.top.findNode("osdPlayIcon")
    m.osdBtn2Bg      = m.top.findNode("osdBtn2Bg")
    m.osdBtn2Lbl     = m.top.findNode("osdBtn2Lbl")
    m.osdBtn3Bg      = m.top.findNode("osdBtn3Bg")
    m.osdBtn3Lbl     = m.top.findNode("osdBtn3Lbl")
    m.seekFill       = m.top.findNode("seekFill")
    m.seekDot        = m.top.findNode("seekDot")
    m.osdCurrentTime = m.top.findNode("osdCurrentTime")
    m.osdTotalTime   = m.top.findNode("osdTotalTime")
    m.subtitlePanel  = m.top.findNode("subtitlePanel")
    m.subItems       = [m.top.findNode("subItem0"), m.top.findNode("subItem1")]
    m.subLabels      = [m.top.findNode("subLabel0"), m.top.findNode("subLabel1")]
    m.autoplayPanel  = m.top.findNode("autoplayPanel")
    m.autoplayTitle  = m.top.findNode("autoplayTitle")
    m.autoplayLabel  = m.top.findNode("autoplayLabel")

    m.serverUrl  = GetReg("server_url")
    m.token      = GetReg("access_token")
    m.mediaId    = 0
    m.lastPos    = 0.0
    m.totalDur   = 0.0
    m.osdVisible = false
    m.videoSetup = false

    m.episodeList      = invalid
    m.episodeIdx       = -1
    m.autoplayIdx      = -1
    m.autoplaySecs     = 0
    m.autoplaying      = false
    m.ccEnabled        = (GetReg("subtitles") = "On")
    m.subtitleMenuOpen = false
    m.subFocusIdx      = 0
    m.btnFocus         = 1   ' 0=-10s, 1=play/pause, 2=+30s, 3=CC

    updateCCDisplay()

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

    m.top.observeField("params", "onParams")
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return
    m.mediaId = p.mediaId
    m.osdTitle.text = p.title

    if p.episodeList <> invalid then m.episodeList = p.episodeList
    if p.episodeIdx  <> invalid then m.episodeIdx  = p.episodeIdx

    cn = CreateObject("roSGNode", "ContentNode")
    cn.url          = p.url
    cn.title        = p.title
    cn.streamFormat = "hls"
    m.video.content = cn

    if not m.videoSetup
        m.video.observeField("state",    "onStateChange")
        m.video.observeField("position", "onPositionChange")
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

sub applySubtitlePref()
    if m.ccEnabled
        m.video.captionMode = "On"
    else
        m.video.captionMode = "Off"
    end if
end sub

sub updateCCDisplay()
    if m.ccEnabled
        m.osdBtn3Lbl.text = "CC: On"
    else
        m.osdBtn3Lbl.text = "CC: Off"
    end if
end sub

' -------------------------------------------------------
' Transport button focus (4 buttons: 0=-10s 1=play 2=+30s 3=CC)
' -------------------------------------------------------

sub updateBtnFocus()
    A_BG  = "0x4A9FFFFF"
    I_BG  = "0x1E2E4EFF"
    A_TXT = "0x000000FF"
    I_TXT = "0xBBBBBBFF"

    m.osdBtn0Bg.color  = I_BG  : m.osdBtn0Lbl.color  = I_TXT
    m.osdPlayBg.color  = I_BG  : m.osdPlayIcon.color  = I_TXT
    m.osdBtn2Bg.color  = I_BG  : m.osdBtn2Lbl.color   = I_TXT
    m.osdBtn3Bg.color  = I_BG  : m.osdBtn3Lbl.color   = I_TXT

    if m.btnFocus = 0
        m.osdBtn0Bg.color = A_BG : m.osdBtn0Lbl.color = A_TXT
    else if m.btnFocus = 1
        m.osdPlayBg.color = A_BG : m.osdPlayIcon.color = A_TXT
    else if m.btnFocus = 2
        m.osdBtn2Bg.color = A_BG : m.osdBtn2Lbl.color = A_TXT
    else
        m.osdBtn3Bg.color = A_BG : m.osdBtn3Lbl.color = A_TXT
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
    updateCCDisplay()
    updateBtnFocus()
end sub

sub toggleCC()
    m.ccEnabled = not m.ccEnabled
    if m.ccEnabled
        SetReg("subtitles", "On")
    else
        SetReg("subtitles", "Off")
    end if
    applySubtitlePref()
    updateCCDisplay()
    updateBtnFocus()
end sub

' -------------------------------------------------------
' Seek helper
' -------------------------------------------------------

sub seekBy(deltaSecs as integer)
    newPos = Int(m.lastPos) + deltaSecs
    if newPos < 0 then newPos = 0
    if m.totalDur > 0 and newPos > m.totalDur then newPos = Int(m.totalDur)
    m.video.seek = newPos
    m.lastPos    = newPos
    updateOsd()
end sub

' -------------------------------------------------------
' State / position
' -------------------------------------------------------

sub onStateChange(event as object)
    s = event.getData()
    if s = "playing" then m.top.setFocus(true)
    if s = "finished"
        doSaveProgress()
        checkAutoplay()
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
    m.autoplayLabel.text = "Playing in " + m.autoplaySecs.ToStr() + "..."
end sub

sub playNext()
    m.autoplaying = false
    m.autoplayPanel.visible = false
    nextEp       = m.episodeList[m.autoplayIdx]
    m.episodeIdx = m.autoplayIdx
    m.mediaId    = nextEp.id
    m.lastPos    = 0.0
    m.totalDur   = 0.0
    m.osdTitle.text       = nextEp.title
    m.osdCurrentTime.text = "0:00"
    m.osdTotalTime.text   = ""
    m.seekFill.width      = 0
    m.seekDot.translation = [52, 929]
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
    m.autoplayTimer.control = "stop"
    m.autoplayPanel.visible = false
    exitPlayer()
end sub

sub onPositionChange(event as object)
    m.lastPos = event.getData()
    dur = m.video.duration
    if dur = invalid then return
    if dur > 0 then m.totalDur = dur
end sub

sub onSaveTimer(event as object)
    doSaveProgress()
end sub

sub exitPlayer()
    if m.saveTimer     <> invalid then m.saveTimer.control     = "stop"
    if m.osdTimer      <> invalid then m.osdTimer.control      = "stop"
    if m.hideTimer     <> invalid then m.hideTimer.control     = "stop"
    if m.autoplayTimer <> invalid then m.autoplayTimer.control = "stop"
    doSaveProgress()
    m.top.navRequest = {action: "back"}
end sub

sub doSaveProgress()
    if m.mediaId = 0 then return
    if m.lastPos <= 0 then return
    posInt = Int(m.lastPos * 10)
    durInt = Int(m.totalDur * 10)
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
    updateBtnFocus()
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

sub hideOsd()
    m.osdVisible  = false
    m.osd.visible = false
    m.hideTimer.control = "stop"
    m.btnFocus = 1
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
        m.seekDot.translation = [52 + fillW, 929]
    end if

    state = m.video.state
    if state = "paused"
        m.osdState.text    = "PAUSED"
        m.osdState.color   = "0x4A9FFFFF"
        m.osdPlayIcon.text = "PLAY"
    else if state = "buffering" or state = "connecting"
        m.osdState.text    = "BUFFERING"
        m.osdState.color   = "0xFFAA00FF"
        m.osdPlayIcon.text = "..."
    else
        m.osdState.text    = ""
        m.osdPlayIcon.text = "PAUSE"
    end if
end sub

' -------------------------------------------------------
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' ── Subtitle panel captures all keys ──
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

    ' ── Back ──
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

    ' ── Autoplay countdown ──
    if (key = "OK" or key = "play") and m.autoplaying
        m.autoplayTimer.control = "stop"
        playNext()
        return true
    end if

    ' ── Options (*): full subtitle panel ──
    if key = "options"
        showOsd()
        openSubtitleMenu()
        return true
    end if

    ' ── Left: navigate buttons left, or seek if OSD hidden ──
    if key = "left"
        if not m.osdVisible
            showOsd()
            m.btnFocus = 0
            updateBtnFocus()
        else if m.btnFocus > 0
            m.btnFocus = m.btnFocus - 1
            updateBtnFocus()
            m.hideTimer.control = "stop"
            m.hideTimer.control = "start"
        else
            seekBy(-10)
            m.hideTimer.control = "stop"
            m.hideTimer.control = "start"
        end if
        return true
    end if

    ' ── Right: navigate buttons right, or seek if OSD hidden ──
    if key = "right"
        if not m.osdVisible
            showOsd()
            m.btnFocus = 2
            updateBtnFocus()
        else if m.btnFocus < 3
            m.btnFocus = m.btnFocus + 1
            updateBtnFocus()
            m.hideTimer.control = "stop"
            m.hideTimer.control = "start"
        else
            seekBy(30)
            m.hideTimer.control = "stop"
            m.hideTimer.control = "start"
        end if
        return true
    end if

    ' ── OK: activate focused button ──
    if key = "OK" or key = "play"
        if not m.osdVisible
            showOsd()
            return true
        end if
        if m.btnFocus = 0
            seekBy(-10)
        else if m.btnFocus = 2
            seekBy(30)
        else if m.btnFocus = 3
            toggleCC()
        else
            if m.video.state = "paused"
                m.video.control = "resume"
            else
                m.video.control = "pause"
            end if
            updateOsd()
        end if
        m.hideTimer.control = "stop"
        m.hideTimer.control = "start"
        return true
    end if

    ' ── Up/Down: show OSD, reset focus to play button ──
    if key = "up" or key = "down"
        if not m.osdVisible
            showOsd()
        else
            m.btnFocus = 1
            updateBtnFocus()
            m.hideTimer.control = "stop"
            m.hideTimer.control = "start"
        end if
        return true
    end if

    ' ── Physical FF/RW: seek 60s ──
    if key = "rev"
        seekBy(-60)
        if not m.osdVisible then showOsd()
        return true
    end if

    if key = "fwd"
        seekBy(60)
        if not m.osdVisible then showOsd()
        return true
    end if

    showOsd()
    return false
end function
