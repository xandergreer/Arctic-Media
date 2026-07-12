' ── Registry ─────────────────────────────────────────────────────────────

function GetReg(key as string) as string
    sec = CreateObject("roRegistrySection", "ArcticMedia")
    val = sec.Read(key)
    if val = invalid then return ""
    return val
end function

sub SetReg(key as string, value as string)
    sec = CreateObject("roRegistrySection", "ArcticMedia")
    sec.Write(key, value)
    sec.Flush()
end sub

sub ClearAuth()
    sec = CreateObject("roRegistrySection", "ArcticMedia")
    sec.Delete("access_token")
    sec.Delete("refresh_token")
    sec.Flush()
end sub

function IsAuthenticated() as boolean
    t = GetReg("access_token")
    return t <> "" and t <> invalid
end function

' ── HTTP ──────────────────────────────────────────────────────────────────

function HttpGet(url as string, token as string) as dynamic
    h = CreateObject("roUrlTransfer")
    h.SetUrl(url)
    h.SetCertificatesFile("common:/certs/ca-bundle.crt")
    h.InitClientCertificates()
    if token <> "" then h.AddHeader("Authorization", "Bearer " + token)
    resp = h.GetToString()
    if resp = "" or resp = invalid then return invalid
    return ParseJson(resp)
end function

function HttpPost(url as string, token as string, body as string) as dynamic
    h = CreateObject("roUrlTransfer")
    h.SetUrl(url)
    h.SetCertificatesFile("common:/certs/ca-bundle.crt")
    h.InitClientCertificates()
    h.SetRequest("POST")
    if token <> "" then h.AddHeader("Authorization", "Bearer " + token)
    h.AddHeader("Content-Type", "application/json")
    resp = h.PostFromString(body)
    if resp = "" or resp = invalid then return invalid
    return ParseJson(resp)
end function

' ── URL helpers ───────────────────────────────────────────────────────────

function ResolveUrl(serverUrl as string, rawUrl as string) as string
    if rawUrl = invalid or rawUrl = "" then return ""
    if Left(rawUrl, 4) = "http" then return rawUrl
    return serverUrl + rawUrl
end function

function BuildHlsUrl(serverUrl as string, token as string, mediaId as integer) as string
    return serverUrl + "/api/v1/stream/" + mediaId.ToStr() + "/master.m3u8?token=" + token
end function

' ── Progress ──────────────────────────────────────────────────────────────

sub SaveProgress(mediaId as integer, posSec as float, durSec as float)
    if mediaId <= 0 or posSec <= 0 then return
    serverUrl = GetReg("server_url")
    token     = GetReg("access_token")
    q = Chr(34)
    posInt = Int(posSec)
    durInt = Int(durSec)
    body = "{" + q + "position_seconds" + q + ":" + posInt.ToStr() + "," + q + "duration_seconds" + q + ":" + durInt.ToStr() + "}"
    HttpPost(serverUrl + "/api/v1/history/" + mediaId.ToStr(), token, body)
end sub

' ── Format ────────────────────────────────────────────────────────────────

function FormatDuration(seconds as integer) as string
    if seconds <= 0 then return ""
    h  = int(seconds / 3600)
    mn = int((seconds mod 3600) / 60)
    if h > 0 then return h.ToStr() + "h " + mn.ToStr() + "m"
    return mn.ToStr() + "m"
end function

function FormatVideoTime(seconds as integer) as string
    if seconds < 0 then seconds = 0
    h  = Int(seconds / 3600)
    mn = Int((seconds mod 3600) / 60)
    s  = seconds mod 60
    if h > 0
        return h.ToStr() + ":" + Right("0" + mn.ToStr(), 2) + ":" + Right("0" + s.ToStr(), 2)
    end if
    return mn.ToStr() + ":" + Right("0" + s.ToStr(), 2)
end function

function YearFromDate(d as dynamic) as string
    if d = invalid or Len(d) < 4 then return ""
    return Left(d, 4)
end function

' ── Error dialog ──────────────────────────────────────────────────────────

function StrVal(v as dynamic) as string
    if v = invalid then return ""
    return v.ToStr()
end function

function iif(cond as boolean, a as string, b as string) as string
    if cond then return a
    return b
end function

sub ShowError(msg as string)
    ' roParagraphScreen deprecated — errors surfaced via OSD or debug log
end sub
