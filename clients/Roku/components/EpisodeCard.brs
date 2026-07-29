sub init()
    m.bg        = m.top.findNode("bg")
    m.accent    = m.top.findNode("accent")
    m.thumb     = m.top.findNode("thumb")
    m.progTrack = m.top.findNode("progTrack")
    m.progFill  = m.top.findNode("progFill")
    m.titleLbl  = m.top.findNode("titleLbl")
    m.metaLbl   = m.top.findNode("metaLbl")
    m.ovLbl     = m.top.findNode("ovLbl")
end sub

sub onContentChanged()
    c = m.top.itemContent
    if c = invalid then return

    m.titleLbl.text = c.title
    if c.thumbUri <> invalid and c.thumbUri <> "" then m.thumb.uri = c.thumbUri
    if c.metaText <> invalid then m.metaLbl.text = c.metaText
    if c.overview <> invalid then m.ovLbl.text = c.overview

    pct = 0
    if c.progressPct <> invalid then pct = c.progressPct
    if pct > 0 then
        if pct > 100 then pct = 100
        m.progTrack.visible = true
        m.progFill.visible  = true
        m.progFill.width    = Int(288 * pct / 100)
    else
        m.progTrack.visible = false
        m.progFill.visible  = false
    end if
end sub

sub onFocusChanged()
    if m.top.itemHasFocus then
        m.bg.color       = "0x1D3156FF"
        m.accent.opacity = 1.0
        m.titleLbl.color = "0xFFFFFFFF"
    else
        m.bg.color       = "0x0E1526F2"
        m.accent.opacity = 0.0
        m.titleLbl.color = "0xE6EDF7FF"
    end if
end sub
