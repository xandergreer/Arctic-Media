sub init()
    m.video     = m.top.findNode("video")
    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")
    m.mediaId   = 0
    m.lastPos   = 0.0
    m.totalDur  = 0.0
    m.top.observeField("params", "onParams")
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return
    m.mediaId = p.mediaId

    cn = CreateObject("roSGNode", "ContentNode")
    cn.url          = p.url
    cn.title        = p.title
    cn.streamFormat = "hls"
    m.video.content = cn
    m.video.observeField("state",    "onStateChange")
    m.video.observeField("position", "onPositionChange")

    startPos = p["position"]
    if startPos = invalid then startPos = 0.0
    if startPos > 30 then m.video.seek = Int(startPos)
    m.video.control = "play"
    m.video.setFocus(true)

    m.saveTimer = CreateObject("roSGNode", "Timer")
    m.saveTimer.duration = 15
    m.saveTimer.repeat   = true
    m.saveTimer.observeField("fire", "onSaveTimer")
    m.saveTimer.control = "start"
end sub

sub onStateChange(event as object)
    s = event.getData()
    if s = "finished" then exitPlayer()
    if s = "error"    then exitPlayer()
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
    if m.saveTimer <> invalid then m.saveTimer.control = "stop"
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

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        m.video.control = "stop"
        exitPlayer()
        return true
    end if
    return false
end function
