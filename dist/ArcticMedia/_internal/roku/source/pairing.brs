sub init()
  print "PairingScene: init() called"
  
  ' Set background color on the scene itself
  m.top.backgroundColor = "0x000000FF"
  m.top.backgroundUri = ""
  
  ' Ensure labels exist before accessing them
  title = m.top.findNode("title")
  message = m.top.findNode("message")
  code = m.top.findNode("code")
  hint = m.top.findNode("hint")
  
  if title = invalid then
    print "ERROR: Title node invalid"
  else
    title.visible = true
    title.text = "Arctic Media"
    print "Title set successfully"
  end if
  
  if message = invalid then
    print "ERROR: Message node invalid"
  else
    message.visible = true
    message.text = "Getting code..."
    print "Message set successfully"
  end if
  
  if code = invalid then
    print "ERROR: Code node invalid"
  else
    code.visible = true
    code.text = "---- ----"
    print "Code set successfully"
  end if
  
  if hint = invalid then
    print "ERROR: Hint node invalid"
  else
    hint.visible = true
    hint.text = "Go to http://your-server/pair and enter the code"
    print "Hint set successfully"
  end if
  
  print "All labels initialized"
  
  ' Don't make HTTP request immediately - delay it
  m.server_url = LoadServerUrl()
  m.device_code = invalid
  m.poll_timer = invalid
  
  ' Use a timer to delay the HTTP request
  m.initTimer = CreateObject("roSGNode", "Timer")
  m.initTimer.duration = 1.0
  m.initTimer.repeat = false
  m.initTimer.observeField("fire", "OnInitTimer")
  m.initTimer.control = "start"
end sub

sub OnInitTimer(event)
  print "Init timer fired, starting pairing request"
  if m.initTimer <> invalid then
    m.initTimer.control = "stop"
    m.initTimer = invalid
  end if
  
  ' If no server URL configured, we should have gotten it from ServerConfigScene
  ' But if somehow we don't have it, show error
  if m.server_url = invalid or m.server_url = "" then
    print "ERROR: No server URL configured!"
    if message <> invalid then message.text = "Server URL not configured"
    if hint <> invalid then hint.text = "Restart app to configure server address"
    if code <> invalid then code.text = "ERROR"
    return
  end if
  
  RequestPairing()
end sub

function LoadServerUrl() as string
  ' Load from registry (persistent storage)
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  url = sec.Read("server_url")
  if url = invalid then url = ""
  return url
end function

sub SaveServerUrl(url as string)
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  sec.Write("server_url", url)
  sec.Flush()
end sub

sub RequestPairing()
  print "RequestPairing() called, server_url=" + m.server_url
  
  message = m.top.findNode("message")
  code = m.top.findNode("code")
  hint = m.top.findNode("hint")
  
  if message <> invalid then message.text = "Requesting pairing code..."
  if code <> invalid then code.text = "---- ----"
  if hint <> invalid then hint.text = "Connecting to server..."

  ' Ensure we have a server URL
  if m.server_url = invalid or m.server_url = "" then
    m.server_url = LoadServerUrl()
    if m.server_url = invalid or m.server_url = "" then
      ' Last resort: try localhost (won't work for remote Roku, but for testing)
      m.server_url = "http://127.0.0.1:8085"
    end if
  end if

  print "Attempting to connect to: " + m.server_url + "/pair/request"
  url = m.server_url + "/pair/request"
  body = {}
  json = HttpJson(url, "POST", body)
  
  if json = invalid then
    print "ERROR: HttpJson returned invalid (connection failed)"
    if message <> invalid then message.text = "Connection failed!"
    if hint <> invalid then hint.text = "Cannot reach server at: " + m.server_url + " - Need server IP/port"
    if code <> invalid then code.text = "ERROR"
    print "Displayed error message to user"
    return
  end if
  
  print "Response received, checking for device_code..."
  if json.device_code = invalid then
    print "ERROR: No device_code in response. Response keys:"
    if json <> invalid then
      for each key in json
        print "  " + key + " = " + type(json[key])
      end for
    end if
    if message <> invalid then message.text = "Invalid server response"
    if hint <> invalid then hint.text = "Server: " + m.server_url + " - Wrong endpoint?"
    if code <> invalid then code.text = "ERROR"
    return
  end if
  
  print "Success! Got device_code: " + Left(json.device_code, 20) + "..."

  m.device_code = json.device_code
  user_code = json.user_code
  m.expires_in = json.expires_in
  m.poll_interval = json.interval
  
  ' CRITICAL: Always use and save the server_url from the server's response
  ' This ensures we use the correct dynamic URL (IP, domain, port) configured by admin
  if json.server_url <> invalid and json.server_url <> "" then
    new_url = json.server_url
    ' Always save the server-provided URL, even if it matches
    ' This ensures we have the correct URL for future requests
    SaveServerUrl(new_url)
    m.server_url = new_url
  end if

  ' Display user code
  if message <> invalid then message.text = "Enter this code on your server:"
  if code <> invalid then code.text = user_code
  if hint <> invalid then hint.text = "Go to " + m.server_url + "/pair"

  ' Start polling
  m.poll_timer = CreateObject("roSGNode", "Timer")
  m.poll_timer.repeat = true
  m.poll_timer.duration = m.poll_interval
  m.poll_timer.observeField("fire", "OnPollTimer")
  m.poll_timer.control = "start"
end sub

sub OnPollTimer(event)
  if m.device_code = invalid then return
  
  ' Always use the saved server URL from registry (should be set from pairing response)
  if m.server_url = invalid or m.server_url = "" then
    m.server_url = LoadServerUrl()
    if m.server_url = invalid or m.server_url = "" then
      ' This shouldn't happen if pairing was successful, but fallback
      m.top.findNode("message").text = "Server URL lost. Restart app."
      if m.poll_timer <> invalid then m.poll_timer.control = "stop"
      return
    end if
  end if

  url = m.server_url + "/pair/poll"
  body = { device_code: m.device_code }
  json = HttpJson(url, "POST", body)

  if json = invalid then return

  if json.status = "authorized" then
    ' Save tokens
    SaveTokens(json.access_token, json.refresh_token)
    ' Navigate to home (TODO: implement HomeScene)
    m.top.findNode("message").text = "Authorized! Loading..."
    if m.poll_timer <> invalid then m.poll_timer.control = "stop"
    ' TODO: m.top.setScene("HomeScene")
  else if json.status = "pending" then
    ' Keep waiting
  else
    m.top.findNode("message").text = "Pairing failed or expired"
    if m.poll_timer <> invalid then m.poll_timer.control = "stop"
  end if
end sub

sub SaveTokens(access_token as string, refresh_token as string)
  sec = CreateObject("roRegistrySection", "ArcticMedia")
  sec.Write("access_token", access_token)
  sec.Write("refresh_token", refresh_token)
  sec.Flush()
end sub
