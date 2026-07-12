sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    url     = m.top.url
    method  = m.top.method
    token   = m.top.token
    reqBody = m.top.reqBody
    if method = invalid or method = "" then method = "GET"

    req = CreateObject("roUrlTransfer")
    req.SetUrl(url)
    req.setCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    req.AddHeader("Accept", "application/json")
    if token <> invalid and token <> ""
        req.AddHeader("Authorization", "Bearer " + token)
    end if

    port = CreateObject("roMessagePort")
    req.SetMessagePort(port)

    if method = "POST" or method = "PATCH" or method = "DELETE"
        body = ""
        if reqBody <> invalid and reqBody <> "" then body = reqBody
        if body <> ""
            req.AddHeader("Content-Type", "application/json")
        end if
        req.AsyncPostFromString(body)
    else
        req.AsyncGetToString()
    end if

    msg = wait(15000, port)
    if msg = invalid
        m.top.apiError = "Timeout"
        return
    end if

    if type(msg) <> "roUrlEvent"
        m.top.apiError = "Network error"
        return
    end if

    code = msg.GetResponseCode()
    rsp  = msg.GetString()

    if code = 401
        m.top.apiError = "Unauthorized"
        return
    end if
    if code >= 400
        m.top.apiError = "HTTP " + code.ToStr()
        return
    end if
    if rsp = invalid or rsp = ""
        ' Some endpoints return no body on success (204 etc.)
        m.top.result = {}
        return
    end if

    parsed = ParseJson(rsp)
    if parsed = invalid
        m.top.apiError = "JSON parse error"
        return
    end if

    if type(parsed) = "roArray"
        m.top.resultArr = parsed
    else
        m.top.result = parsed
    end if
end sub
