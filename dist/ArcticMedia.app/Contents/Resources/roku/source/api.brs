function HttpJson(url as string, method as string, body = invalid as dynamic) as object
  print "HttpJson: " + method + " " + url
  req = CreateObject("roUrlTransfer")
  req.SetUrl(url)
  req.setCertificatesFile("common:/certs/ca-bundle.crt")
  req.InitClientCertificates()
  req.AddHeader("Accept", "application/json")
  req.SetTimeout(10) ' 10 second timeout
  
  json_str = ""
  if body <> invalid and type(body) = "roAssociativeArray" then
    if method = "POST" then req.AddHeader("Content-Type", "application/json")
    json_str = FormatJson(body)
    print "Request body: " + json_str
  else
    json_str = "{}"
  end if

  rsp = invalid
  error_msg = ""
  if method = "POST" then
    success = req.PostFromString(json_str)
    if success then
      rsp = req.GetToString()
      print "Response received: " + Left(rsp, 200)
    else
      error_msg = "POST failed"
      print "ERROR: POST failed"
    end if
  else
    rsp = req.GetToString()
    print "Response received: " + Left(rsp, 200)
  end if

  if rsp = invalid or rsp = "" then 
    print "ERROR: Empty response or invalid. Error: " + error_msg
    return invalid
  end if
  
  parser = CreateObject("roJsonParser")
  result = parser.Parse(rsp)
  if result = invalid then
    print "ERROR: Failed to parse JSON. Response: " + Left(rsp, 200)
  end if
  return result
end function

function FormatJson(obj as dynamic) as string
  ' Simple JSON encoding for Roku (limited support)
  if type(obj) = "roAssociativeArray" then
    parts = []
    for each key in obj
      val = obj[key]
      if type(val) = "String" then
        parts.push(Chr(34) + key + Chr(34) + ": " + Chr(34) + val + Chr(34))
      else if type(val) = "Integer" or type(val) = "LongInteger" then
        parts.push(Chr(34) + key + Chr(34) + ": " + val.ToStr())
      else if type(val) = "Boolean" then
        parts.push(Chr(34) + key + Chr(34) + ": " + iif(val, "true", "false"))
      end if
    end for
    result = ""
    for i = 0 to parts.count() - 1
      if result <> "" then result = result + ","
      result = result + parts[i]
    end for
    return "{" + result + "}"
  end if
  return "{}"
end function
