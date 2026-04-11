sub init()
    m.poster        = m.top.findNode("poster")
    m.focusBorder   = m.top.findNode("focusBorder")
    m.titleBg       = m.top.findNode("titleBg")
    m.titleLabel    = m.top.findNode("titleLabel")
    m.progressBg    = m.top.findNode("progressBg")
    m.progressFill  = m.top.findNode("progressFill")
    m.epBadgeBg     = m.top.findNode("epBadgeBg")
    m.epBadge       = m.top.findNode("epBadge")
    m.top.scaleRotateCenter = [91, 135]
    m.top.observeField("itemContent",  "onContent")
    m.top.observeField("focusPercent", "onFocus")
end sub

sub onContent(event as object)
    content = event.getData()
    if content = invalid then return

    uri = content.hdPosterUrl
    if uri = invalid then uri = ""
    m.poster.uri      = uri
    m.titleLabel.text = content.title

    ' Progress bar
    pct = content["progressPct"]
    if pct <> invalid and pct > 0 then
        fillW = Int(pct / 100.0 * 182)
        if fillW < 3 then fillW = 3
        m.progressFill.width   = fillW
        m.progressBg.opacity   = 1.0
        m.progressFill.opacity = 1.0
    else
        m.progressBg.opacity   = 0.0
        m.progressFill.opacity = 0.0
    end if

    ' Episode badge
    epLbl = content["episodeLabel"]
    if epLbl <> invalid and epLbl <> "" then
        m.epBadge.text      = epLbl
        m.epBadgeBg.opacity = 1.0
        m.epBadge.opacity   = 1.0
    else
        m.epBadgeBg.opacity = 0.0
        m.epBadge.opacity   = 0.0
    end if
end sub

sub onFocus(event as object)
    pct = event.getData()
    m.focusBorder.opacity = pct * 0.9
    m.titleBg.opacity     = pct
    m.titleLabel.opacity  = pct
    scale = 1.0 + (pct * 0.05)
    m.top.scale = [scale, scale]
end sub
