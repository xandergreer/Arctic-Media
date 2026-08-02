sub init()
    m.serverUrl  = ""
    m.deviceCode = ""
    m.pollTimer  = invalid
    m.serverDialog = invalid

    m.setupView    = m.top.findNode("setupView")
    m.loadingView  = m.top.findNode("loadingView")
    m.pairingView  = m.top.findNode("pairingView")

    m.connectCard  = m.top.findNode("connectCard")
    m.connectLabel = m.top.findNode("connectLabel")
    m.credsCard    = m.top.findNode("credsCard")
    m.credsLabel   = m.top.findNode("credsLabel")
    m.savedUrl     = m.top.findNode("savedUrl")
    m.setupHint    = m.top.findNode("setupHint")
    m.setupError   = m.top.findNode("setupError")

    ' Setup screen selection: 0 = browser pairing, 1 = username/password.
    m.setupIdx = 0
    ' Where the server-address dialog should hand off once a URL is entered:
    ' "pair" resumes the device-code flow, "creds" continues to the login form.
    m.urlNextAction = "pair"
    m.credUser      = ""

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
    ' Sets the hint to match whichever option is selected.
    updateSetupFocus()
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
            if m.urlNextAction = "creds"
                openUsernameDialog()
            else
                showLoading()
                startPairRequest()
            end if
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
' Credential sign-in (alternative to browser pairing)
'
' Posts to the same /api/v1/auth/token the web player uses and stores the
' token pairing would have produced, so everything downstream is identical.
' This path exists because a D-pad script can drive it end to end: browser
' pairing cannot be automated, which blocks Roku's App Behavior Analysis.
' -------------------------------------------------------

sub updateSetupFocus()
    if m.setupIdx = 0
        m.connectCard.uri   = "pkg:/images/surface_focus_r14.9.png"
        m.connectLabel.color = "0xEAF3FFFF"
        m.credsCard.uri     = "pkg:/images/surface_r14.9.png"
        m.credsLabel.color  = "0x93A0B8FF"
        m.setupHint.text    = "Press OK to enter your server address"
    else
        m.connectCard.uri   = "pkg:/images/surface_r14.9.png"
        m.connectLabel.color = "0x93A0B8FF"
        m.credsCard.uri     = "pkg:/images/surface_focus_r14.9.png"
        m.credsLabel.color  = "0xEAF3FFFF"
        m.setupHint.text    = "Press OK to sign in with your server username"
    end if
end sub

sub openUsernameDialog()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Username"
    dlg.message = ["Your username on " + m.serverUrl]
    dlg.text = m.credUser
    dlg.buttons = ["Next", "Cancel"]
    dlg.observeField("buttonSelected", "onUsernameDialogButton")
    m.serverDialog = dlg
    m.top.getScene().dialog = dlg
end sub

sub onUsernameDialogButton(event as object)
    idx = event.getData()
    dlg = m.serverDialog
    if dlg = invalid then return

    if idx = 0
        m.credUser = dlg.text.Trim()
        dismissServerDialog()
        if m.credUser = ""
            showSetup()
            m.setupError.text = "Enter a username."
            return
        end if
        openPasswordDialog()
    else
        dismissServerDialog()
        showSetup()
    end if
end sub

sub openPasswordDialog()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Password"
    dlg.message = ["Signing in as " + m.credUser]
    dlg.text = ""
    ' Mask the entry where the firmware supports it. hasField guards against
    ' the "Tried to set nonexistent field" warning on older builds.
    if dlg.hasField("secureMode") then dlg.secureMode = true
    dlg.buttons = ["Sign In", "Cancel"]
    dlg.observeField("buttonSelected", "onPasswordDialogButton")
    m.serverDialog = dlg
    m.top.getScene().dialog = dlg
end sub

sub onPasswordDialogButton(event as object)
    idx = event.getData()
    dlg = m.serverDialog
    if dlg = invalid then return

    if idx = 0
        pw = dlg.text
        dismissServerDialog()
        startCredentialLogin(m.credUser, pw)
    else
        dismissServerDialog()
        showSetup()
    end if
end sub

sub startCredentialLogin(user as string, pw as string)
    showLoading()
    m.loadingLabel.text = "Signing in…"

    ' FastAPI's OAuth2PasswordRequestForm only reads form-encoded bodies, so
    ' this cannot go as JSON like the rest of the API. ApiTask does the
    ' encoding: roUrlTransfer cannot be created on the render thread, so
    ' Escape() is unavailable here.
    task = CreateObject("roSGNode", "ApiTask")
    task.url        = m.serverUrl + "/api/v1/auth/token"
    task.method     = "POST"
    task.formFields = { username: user, password: pw }
    task.observeField("result",   "onCredLoginResult")
    task.observeField("apiError", "onCredLoginError")
    task.control = "run"
    m.credTask = task
end sub

sub onCredLoginResult(event as object)
    data = event.getData()
    ' alwaysNotify fires once with an empty AA when the observer attaches, so
    ' an empty result is not necessarily a failure — only treat a populated
    ' response with no token as one, and never leave the spinner up silently.
    if data = invalid then return
    if data.Count() = 0 then return
    if data.access_token = invalid
        showSetup()
        m.setupIdx = 1
        updateSetupFocus()
        m.setupError.text = "The server did not return a sign-in token."
        return
    end if

    SetReg("access_token", data.access_token)
    if data.refresh_token <> invalid then SetReg("refresh_token", data.refresh_token)
    m.top.signalBeacon("AppDialogComplete")
    m.top.navRequest = {action: "home"}
end sub

sub onCredLoginError(event as object)
    err = event.getData()
    showSetup()
    m.setupIdx = 1
    updateSetupFocus()
    if err = "Unauthorized"
        m.setupError.text = "That username or password was not accepted."
    else
        m.setupError.text = "Could not reach the server. Check the address and try again."
    end if
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

    if m.setupView.visible
        if key = "up" or key = "down"
            if m.setupIdx = 0 then
                m.setupIdx = 1
            else
                m.setupIdx = 0
            end if
            updateSetupFocus()
            return true
        end if
        if key = "OK"
            if m.setupIdx = 0
                m.urlNextAction = "pair"
                openServerDialog()
            else
                ' Credential sign-in still needs to know which server to talk
                ' to, so ask for the address first when we do not have one.
                if m.serverUrl = ""
                    m.urlNextAction = "creds"
                    openServerDialog()
                else
                    openUsernameDialog()
                end if
            end if
            return true
        end if
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
