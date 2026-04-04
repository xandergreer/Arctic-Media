sub init()
    m.video          = m.top.findNode("video")
    m.osd            = m.top.findNode("osd")
    m.osdTitle       = m.top.findNode("osdTitle")
    m.osdState       = m.top.findNode("osdState")
    m.seekFill       = m.top.findNode("seekFill")
    m.seekDot        = m.top.findNode("seekDot")
    m.osdCurrentTime = m.top.findNode("osdCurrentTime")
    m.osdTotalTime   = m.top.findNode("osdTotalTime")
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

    m.episodeList  = invalid
    m.episodeIdx   = -1
    m.autoplayIdx  = -1
    m.autoplaySecs = 0
    m.autoplaying  = false

    ' OSD auto-hide timer (5 seconds of inactivity)
    m.hideTimer = CreateObject("roSGNode", "Timer")
    m.hideTimer.duration = 5
    m.hideTimer.repeat   = false
    m.hideTimer.observeField("fire", "onHideTimer")

    ' OSD progress update timer (every 1 second)
    m.osdTimer = CreateObject("roSGNode", "Timer")
    m.osdTimer.duration = 1
    m.osdTimer.repeat   = true
    m.osdTimer.observeField("fire", "onOsdTimer")
    m.osdTimer.control = "start"

    ' Autoplay countdown timer (every 1 second)
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

    ' Store episode list for autoplay
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

    ' Keep focus on VideoPage so onKeyEvent receives all key presses.
    ' The Video node plays fine without focus.
    m.top.setFocus(true)

    ' Progress save timer (every 15 seconds)
    m.saveTimer = CreateObject("roSGNode", "Timer")
    m.saveTimer.duration = 15
    m.saveTimer.repeat   = true
    m.saveTimer.observeField("fire", "onSaveTimer")
    m.saveTimer.control = "start"
end sub

sub applySubtitlePref()
    subPref = GetReg("subtitles")
    if subPref = "On"
        m.video.captionMode = "On"
    else
        m.video.captionMode = "Off"
    end if
end sub

sub onStateChange(event as object)
    s = event.getData()
    if s = "finished"
        doSaveProgress()
        checkAutoplay()
        return
    end if
    if s = "error" then exitPlayer()
    updateOsd()
    ' Keep OSD visible indefinitely while paused
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
    m.seekDot.translation = [52, 975]

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
        m.seekDot.translation = [52 + fillW, 975]
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

    ' OK/play during autoplay countdown = play immediately
    if (key = "OK" or key = "play") and m.autoplaying
        m.autoplayTimer.control = "stop"
        playNext()
        return true
    end if

    ' Show OSD on any key press
    showOsd()

    if key = "OK" or key = "play"
        if m.video.state = "paused"
            m.video.control = "resume"
        else
            m.video.control = "pause"
        end if
        updateOsd()
        return true
    end if

    if key = "left"
        newPos = Int(m.lastPos) - 10
        if newPos < 0 then newPos = 0
        m.video.seek = newPos
        m.lastPos    = newPos
        updateOsd()
        return true
    end if

    if key = "right"
        newPos = Int(m.lastPos) + 30
        if m.totalDur > 0 and newPos > m.totalDur then newPos = Int(m.totalDur)
        m.video.seek = newPos
        m.lastPos    = newPos
        updateOsd()
        return true
    end if

    ' Physical rewind / fast-forward buttons: seek ±60s
    if key = "rev"
        newPos = Int(m.lastPos) - 60
        if newPos < 0 then newPos = 0
        m.video.seek = newPos
        m.lastPos    = newPos
        updateOsd()
        return true
    end if

    if key = "fwd"
        newPos = Int(m.lastPos) + 60
        if m.totalDur > 0 and newPos > m.totalDur then newPos = Int(m.totalDur)
        m.video.seek = newPos
        m.lastPos    = newPos
        updateOsd()
        return true
    end if

    return false
end function
