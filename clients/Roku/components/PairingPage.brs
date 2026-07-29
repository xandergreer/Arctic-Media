sub init()
    m.serverUrl  = ""
    m.deviceCode = ""
    m.pollTimer  = invalid
    m.serverDialog = invalid

    m.setupView    = m.top.findNode("setupView")
    m.loadingView  = m.top.findNode("loadingView")
    m.pairingView  = m.top.findNode("pairingView")

    m.connectLabel = m.top.findNode("connectLabel")
    m.savedUrl     = m.top.findNode("savedUrl")
    m.setupHint    = m.top.findNode("setupHint")
    m.setupError   = m.top.findNode("setupError")

    m.loadingLabel = m.top.findNode("loadingLabel")
    m.codeLabel    = m.top.findNode("codeLabel")
    m.loginUrl     = m.top.findNode("loginUrl")
    m.pairUrl      = m.top.findNode("pairUrl")
    m.statusLabel  = m.top.findNode("statusLabel")
    m.errorLabel   = m.top.findNode("errorLabel")

    ' This auth screen is a dialog shown before the home page — bracket it with
    ' AppDialog beacons so its time is excluded from the launch metric (cert 3.2).
    m.top.signalBeacon("AppDialogInitiate")

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
    m.loadingView.visible = false
    m.pairingView.visible = false

    if m.serverUrl <> ""
        m.savedUrl.text = "Last used:  " + m.serverUrl
    else
        m.savedUrl.text = ""
    end if
    m.setupHint.text  = "Press OK to enter your server address"
    m.top.setFocus(true)
end sub

sub showLoading()
    m.setupView.visible   = false
    m.pairingView.visible = false
    m.loadingView.visible = true
end sub

sub showPairing(userCode as string, serverUrl as string)
    m.setupView.visible   = false
    m.loadingView.visible = false
    m.pairingView.visible = true
    m.codeLabel.text   = userCode
    m.loginUrl.text    = serverUrl
    m.pairUrl.text     = serverUrl + "/pair"
    m.statusLabel.text = "Waiting for authorization…"
    m.errorLabel.text  = ""
end sub

' -------------------------------------------------------
' Server-address entry (on-screen keyboard with a Connect button)
' -------------------------------------------------------

sub openServerDialog()
    ' StandardKeyboardDialog is Roku's recommended text/voice entry node (cert
    ' 4.12). It shares the Dialog base class, so buttons / buttonSelected / text
    ' behave the same (per Roku's standard-dialog-framework sample).
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Server Address"
    dlg.message = ["Enter your media server — e.g.  192.168.1.50:8085"]
    if m.serverUrl <> "" then
        dlg.text = m.serverUrl
    else
        dlg.text = "https://"
    end if
    dlg.buttons = ["Connect", "Cancel"]
    dlg.observeField("buttonSelected", "onServerDialogButton")
    m.serverDialog = dlg
    m.top.getScene().dialog = dlg
end sub

sub onServerDialogButton(event as object)
    idx = event.getData()
    dlg = m.serverDialog
    if dlg = invalid then return

    if idx = 0    ' Connect
        url = dlg.text.Trim()
        dismissServerDialog()
        if Len(url) > 10 and Left(url, 4) = "http"
            m.serverUrl = url
            SetReg("server_url", url)
            m.setupError.text = ""
            showLoading()
            startPairRequest()
        else
            showSetup()
            m.setupError.text = "That doesn't look like a valid address. Try again."
        end if
    else          ' Cancel
        dismissServerDialog()
        showSetup()
    end if
end sub

sub dismissServerDialog()
    if m.serverDialog <> invalid
        m.top.getScene().dialog = invalid
        m.serverDialog = invalid
    end if
    m.top.setFocus(true)
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
    showSetup()
    m.savedUrl.text  = "Last used:  " + m.serverUrl
    m.setupError.text = "Couldn't reach server: " + errMsg
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
        if data.access_token <> invalid then SetReg("access_token", data.access_token)
        if data.refresh_token <> invalid then SetReg("refresh_token", data.refresh_token)
        ' User finished the pre-home dialog — close the AppDialog beacon window.
        m.top.signalBeacon("AppDialogComplete")
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
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "OK" and m.setupView.visible
        openServerDialog()
        return true
    end if

    if key = "options"
        ' Force re-enter server address
        stopPoll()
        m.deviceCode = ""
        showSetup()
        return true
    end if

    return false
end function
