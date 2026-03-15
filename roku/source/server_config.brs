sub init()
  print "ServerConfigScene: init() called"
  
  ' Set background color
  m.top.backgroundColor = "0x000000FF"
  m.top.backgroundUri = ""
  
  ' Get UI elements
  m.title = m.top.findNode("title")
  m.prompt = m.top.findNode("prompt")
  m.inputDisplay = m.top.findNode("input_display")
  m.hint = m.top.findNode("hint")
  m.status = m.top.findNode("status")
  m.keyboard = m.top.findNode("keyboard")
  
  ' Check if server URL already exists
  savedUrl = LoadServerUrlConfig()
  if savedUrl <> "" and savedUrl <> invalid then
    ' Server URL exists, go directly to pairing
    print "Server URL already configured: " + savedUrl
    m.server_url = savedUrl
    StartPairing()
    return
  end if
  
  ' No server URL, show input screen
  print "No server URL configured, showing input screen"
  
  ' Initialize with default
  m.inputDisplay.text = "http://"
  m.keyboard.text = "http://"
  m.status.text = "Press OK to open keyboard, then enter server address"
  
  ' Set up keyboard event handler
  m.keyboard.observeField("text", "OnKeyboardText")
  
  ' Set scene to receive key events
  m.top.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
  if not press then return false
  
  print "onKeyEvent: " + key
  
  ' If keyboard is visible, let it handle keys
  if m.keyboard <> invalid and m.keyboard.visible then
    if key = "OK" then
      ' Save and proceed
      url = m.keyboard.text
      if url <> "" and url <> "http://" then
        print "Saving server URL: " + url
        SaveServerUrlConfig(url)
        m.keyboard.visible = false
        m.keyboard.setFocus(false)
        m.top.setFocus(true)
        ' Start pairing directly in this scene
        StartPairing()
        return true
      else
        m.status.text = "Please enter a valid server address"
        return true
      end if
    else if key = "back" then
      ' Hide keyboard
      m.keyboard.visible = false
      m.keyboard.setFocus(false)
      m.top.setFocus(true)
      m.status.text = "Press OK to open keyboard"
      return true
    end if
    ' Let keyboard handle other keys
    return false
  end if
  
  ' Scene key handling
  if key = "OK" then
    ' Show keyboard
    if m.keyboard <> invalid then
      m.keyboard.visible = true
      m.keyboard.text = "http://"
      m.keyboard.setFocus(true)
      m.status.text = "Enter server address (e.g., http://192.168.1.100:8085)"
    end if
    return true
  else if key = "back" then
    ' Exit app
    m.top.getScene().close()
    return true
  end if
  
  return false
end function

sub OnKeyboardText(event as object)
  text = event.getData()
  print "Keyboard text changed: " + text
  if m.inputDisplay <> invalid then
    m.inputDisplay.text = text
  end if
end sub

sub StartPairing()
  print "Starting pairing process"
  
  ' Hide input elements, show pairing UI
  if m.title <> invalid then m.title.text = "Arctic Media"
  if m.prompt <> invalid then m.prompt.text = "Requesting pairing code..."
  if m.inputDisplay <> invalid then m.inputDisplay.text = "---- ----"
  if m.hint <> invalid then m.hint.text = "Connecting to server..."
  if m.status <> invalid then m.status.text = "Please wait..."
  
  ' Load the pairing logic (we'll import it)
  ' Actually, we need to load the pairing.brs functions
  ' For MVP, let's duplicate the pairing logic here
  m.server_url = LoadServerUrlConfig()
  
  ' Delay HTTP request
  m.pairTimer = CreateObject("roSGNode", "Timer")
  m.pairTimer.duration = 1.0
  m.pairTimer.repeat = false
  m.pairTimer.observeField("fire", "OnPairTimer")
  m.pairTimer.control = "start"
end sub

sub OnPairTimer(event)
  RequestPairingConfig()
  if m.pairTimer <> invalid then
    m.pairTimer.control = "stop"
    m.pairTimer = invalid
  end if
end sub

sub RequestPairingConfig()
  print "RequestPairingConfig() called, server_url=" + m.server_url
  
  if m.prompt <> invalid then m.prompt.text = "Requesting pairing code..."
  if m.inputDisplay <> invalid then m.inputDisplay.text = "---- ----"
  if m.hint <> invalid then m.hint.text = "Connecting to server..."

  url = m.server_url + "/pair/request"
  body = {}
  json = HttpJson(url, "POST", body)
  
  if json = invalid then
    print "ERROR: HttpJson returned invalid (connection failed)"
    if m.prompt <> invalid then m.prompt.text = "Connection failed!"
    if m.hint <> invalid then m.hint.text = "Cannot reach: " + m.server_url + " - Check server IP/port"
    if m.inputDisplay <> invalid then m.inputDisplay.text = "ERROR"
    return
  end if
  
  if json.device_code = invalid then
    print "ERROR: No device_code in response"
    if m.prompt <> invalid then m.prompt.text = "Invalid server response"
    if m.hint <> invalid then m.hint.text = "Server: " + m.server_url + " - Wrong endpoint?"
    if m.inputDisplay <> invalid then m.inputDisplay.text = "ERROR"
    return
  end if
  
  m.device_code = json.device_code
  user_code = json.user_code
  m.expires_in = json.expires_in
  m.poll_interval = json.interval
  
  ' Update server URL from response if provided
  if json.server_url <> invalid and json.server_url <> "" then
    SaveServerUrlConfig(json.server_url)
    m.server_url = json.server_url
  end if

  ' Display user code
  if m.prompt <> invalid then m.prompt.text = "Enter this code on your server:"
  if m.inputDisplay <> invalid then m.inputDisplay.text = user_code
  if m.hint <> invalid then m.hint.text = "Go to " + m.server_url + "/pair"
  if m.status <> invalid then m.status.text = "Waiting for authorization..."

  ' Start polling
  m.poll_timer = CreateObject("roSGNode", "Timer")
  m.poll_timer.repeat = true
  m.poll_timer.duration = m.poll_interval
  m.poll_timer.observeField("fire", "OnPollTimerConfig")
  m.poll_timer.control = "start"
end sub

sub OnPollTimerConfig(event)
  if m.device_code = invalid then return
  
  url = m.server_url + "/pair/poll"
  body = { device_code: m.device_code }
  json = HttpJson(url, "POST", body)

  if json = invalid then return

  if json.status = "authorized" then
    ' Save tokens
    SaveTokensConfig(json.access_token, json.refresh_token)
    ' Show success
    if m.prompt <> invalid then m.prompt.text = "Authorized!"
    if m.status <> invalid then m.status.text = "Loading..."
    if m.poll_timer <> invalid then m.poll_timer.control = "stop"
    ' TODO: Navigate to home
  else if json.status = "pending" then
    ' Keep waiting
  else
    if m.prompt <> invalid then m.prompt.text = "Pairing failed or expired"
    if m.poll_timer <> invalid then m.poll_timer.control = "stop"
  end if
end sub

sub SaveTokensConfig(access_token as string, refresh_token as string)
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  sec.Write("access_token", access_token)
  sec.Write("refresh_token", refresh_token)
  sec.Flush()
end sub

function LoadServerUrlConfig() as string
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  url = sec.Read("server_url")
  if url = invalid then url = ""
  return url
end function

sub SaveServerUrlConfig(url as string)
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  sec.Write("server_url", url)
  sec.Flush()
  print "Saved server URL: " + url
end sub

