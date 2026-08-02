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
        ct   = m.top.contentType
        if ct = invalid or ct = "" then ct = "application/json"

        ' Form POST: build the body here so Escape() is available. Creating an
        ' roUrlTransfer on the render thread returns Invalid, so the caller
        ' cannot encode this itself.
        fields = m.top.formFields
        if fields <> invalid and fields.Count() > 0
            first = true
            for each k in fields
                v = fields[k]
                if v = invalid then v = ""
                ' Stringify without calling ToStr() on a string: roString has no
                ' such member, and the resulting error kills this task thread
                ' silently — no fields get set, so the caller's observers never
                ' fire and the UI hangs on its loading state.
                t = type(v)
                if t = "String" or t = "roString"
                    sv = v
                else
                    sv = Str(v).Trim()
                end if
                pair = req.Escape(k) + "=" + req.Escape(sv)
                if first
                    body  = pair
                    first = false
                else
                    body = body + "&" + pair
                end if
            end for
            ct = "application/x-www-form-urlencoded"
        else if reqBody <> invalid and reqBody <> ""
            body = reqBody
        end if

        if body <> ""
            req.AddHeader("Content-Type", ct)
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

    ' A transport failure (DNS, refused, TLS) reports a NEGATIVE code, which is
    ' not >= 400, so it used to fall through to the empty-body branch below and
    ' return result = {} — indistinguishable from a successful 204. Callers
    ' waiting on apiError then never heard anything and sat on their loading
    ' state forever.
    if code <= 0
        m.top.apiError = "Network error"
        return
    end if
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
