sub init()
    m.serverUrl  = ""
    m.deviceCode = ""
    m.pollTimer  = invalid
    m.pollTask   = invalid

    m.setupView   = m.top.findNode("setupView")
    m.pairingView = m.top.findNode("pairingView")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.codeLabel   = m.top.findNode("codeLabel")
    m.loginUrl    = m.top.findNode("loginUrl")
    m.pairUrl     = m.top.findNode("pairUrl")
    m.statusLabel = m.top.findNode("statusLabel")
    m.errorLabel  = m.top.findNode("errorLabel")
    m.urlDisplay  = m.top.findNode("urlDisplay")
    m.setupPrompt = m.top.findNode("setupPrompt")
    m.urlKeyboard = m.top.findNode("urlKeyboard")

    ' Slight delay before starting (let scene settle)
    m.startTimer = CreateObject("roSGNode", "Timer")
    m.startTimer.duration = 0.5
    m.startTimer.repeat   = false
    m.startTimer.observeField("fire", "onStartTimer")
    m.startTimer.control = "start"
end sub

sub onStartTimer(event as object)
    m.startTimer.control = "stop"
    m.startTimer = invalid

    savedUrl = GetReg("server_url")
    if savedUrl <> "" and savedUrl <> invalid
        m.serverUrl = savedUrl.Trim()
        showLoading()
        startPairRequest()
    else
        showSetup()
    end if
end sub

' -------------------------------------------------------
' View states
' -------------------------------------------------------

sub showSetup()
    m.setupView.visible   = true
    m.pairingView.visible = false
    m.loadingLabel.visible = false
    m.urlKeyboard.visible  = false
    m.urlDisplay.text = "http://"
    m.setupPrompt.text = "Press OK to open keyboard, then Back to connect"
    m.top.setFocus(true)
end sub

sub showLoading()
    m.setupView.visible    = false
    m.pairingView.visible  = false
    m.loadingLabel.visible = true
end sub

sub showPairing(userCode as string, serverUrl as string)
    m.setupView.visible    = false
    m.loadingLabel.visible = false
    m.pairingView.visible  = true
    m.codeLabel.text   = userCode
    m.loginUrl.text    = serverUrl
    m.pairUrl.text     = serverUrl + "/pair"
    m.statusLabel.text = "Waiting for authorization…"
    m.errorLabel.text  = ""
end sub

' -------------------------------------------------------
' Pairing API calls
' -------------------------------------------------------

sub startPairRequest()

    task = CreateObject("roSGNode", "ApiTask")
    task.url    = m.serverUrl + "/pair/request"
    task.method = "POST"
    task.reqBody = "{}"
    task.observeField("result",   "onPairRequestResult")
    task.observeField("apiError", "onPairRequestError")
    task.control = "run"
    m.pairTask = task
end sub

sub onPairRequestResult(event as object)
    data = event.getData()
    if data = invalid then return
    if data.user_code = invalid then return

    m.deviceCode = data.device_code
    userCode = data.user_code

    ' Update server URL from response if provided
    if data.server_url <> invalid and data.server_url <> ""
        m.serverUrl = data.server_url
        SetReg("server_url", m.serverUrl)
    end if

    showPairing(userCode, m.serverUrl)
    startPollTimer()
end sub

sub onPairRequestError(event as object)
    errMsg = event.getData()
    m.loadingLabel.visible = false
    m.setupView.visible    = true
    m.urlDisplay.text = m.serverUrl
    m.setupPrompt.text = "Error: " + errMsg + " — Press OK to change server"
end sub

sub startPollTimer()
    if m.pollTimer <> invalid
        m.pollTimer.control = "stop"
        m.pollTimer = invalid
    end if
    m.pollTimer = CreateObject("roSGNode", "Timer")
    m.pollTimer.duration = 5
    m.pollTimer.repeat   = true
    m.pollTimer.observeField("fire", "onPollTimer")
    m.pollTimer.control = "start"
end sub

sub onPollTimer(event as object)
    if m.deviceCode = "" then return
    task = CreateObject("roSGNode", "ApiTask")
    task.url    = m.serverUrl + "/pair/poll"
    task.method = "POST"
    task.reqBody = FormatJson({device_code: m.deviceCode})
    task.observeField("result",   "onPollResult")
    task.observeField("apiError", "onPollError")
    task.control = "run"
    m.pollTask = task
end sub

sub onPollResult(event as object)
    data = event.getData()
    if data = invalid then return
    if data.status = invalid then return

    status = data.status
    if status = "authorized"
        stopPoll()
        SetReg("access_token",  data.access_token)
        SetReg("refresh_token", data.refresh_token)
        m.top.navRequest = {action: "home"}

    else if status = "expired"
        stopPoll()
        m.errorLabel.text = "Code expired. Requesting a new one…"
        m.deviceCode = ""
        m.startTimer2 = CreateObject("roSGNode", "Timer")
        m.startTimer2.duration = 2
        m.startTimer2.repeat = false
        m.startTimer2.observeField("fire", "onRetryTimer")
        m.startTimer2.control = "start"
    end if
end sub

sub onRetryTimer(event as object)
    m.startTimer2.control = "stop"
    showLoading()
    startPairRequest()
end sub

sub onPollError(event as object)
    ' Ignore transient errors during polling
end sub

sub stopPoll()
    if m.pollTimer <> invalid
        m.pollTimer.control = "stop"
        m.pollTimer = invalid
    end if
end sub

' -------------------------------------------------------
' Key handling (setup mode + options)
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.urlKeyboard <> invalid and m.urlKeyboard.visible
        if key = "back"
            url = m.urlKeyboard.text.Trim()
            if Len(url) > 10 and Left(url, 4) = "http"
                m.urlKeyboard.visible = false
                m.top.setFocus(true)
                m.serverUrl = url
                SetReg("server_url", url)
                showLoading()
                startPairRequest()
            else
                m.urlKeyboard.visible = false
                m.top.setFocus(true)
            end if
            return true
        end if
        return false
    end if

    if key = "OK" and m.setupView.visible
        m.urlKeyboard.text = "http://"
        m.urlKeyboard.visible = true
        m.urlKeyboard.setFocus(true)
        m.setupPrompt.text = "Type your server URL, then press Back to connect"
        return true
    end if

    if key = "options"
        ' Force re-enter server URL
        stopPoll()
        m.deviceCode = ""
        showSetup()
        return true
    end if

    return false
end function
