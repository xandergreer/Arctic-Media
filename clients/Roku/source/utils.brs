' Registry helpers
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
    token = GetReg("access_token")
    return token <> "" and token <> invalid
end function

' Formatting
function FormatDuration(seconds as integer) as string
    if seconds <= 0 then return ""
    h = int(seconds / 3600)
    mn = int((seconds mod 3600) / 60)
    if h > 0
        return h.ToStr() + "h " + mn.ToStr() + "m"
    end if
    return mn.ToStr() + "m"
end function

' Build playback URL
function BuildHlsUrl(serverUrl as string, token as string, mediaId as integer) as string
    return serverUrl + "/api/v1/stream/" + mediaId.ToStr() + "/master.m3u8?token=" + token
end function

' Build image URL — poster_url from API is already absolute
function ResolveUrl(serverUrl as string, rawUrl as string) as string
    if rawUrl = invalid or rawUrl = "" then return ""
    if Left(rawUrl, 4) = "http" then return rawUrl
    return serverUrl + rawUrl
end function
