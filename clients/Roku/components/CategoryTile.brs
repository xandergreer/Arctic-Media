sub init()
    m.bg          = m.top.findNode("bg")
    m.poster      = m.top.findNode("poster")
    m.focusRing   = m.top.findNode("focusRing")
    m.focusGlow   = m.top.findNode("focusGlow")
    m.titleLabel  = m.top.findNode("titleLabel")
    m.top.scaleRotateCenter = [200, 112]
    m.top.observeField("itemContent",  "onContent")
    m.top.observeField("focusPercent", "onFocus")
end sub

sub onContent(event as object)
    content = event.getData()
    if content = invalid then return
    m.titleLabel.text = content.title
    uri = content.hdPosterUrl
    if uri = invalid or uri = "" then return
    m.poster.uri = uri
end sub

sub onFocus(event as object)
    pct = event.getData()
    ' Ring + bloom + scale, matching PosterItem, so focus feels the same
    ' wherever it lands. The old flat 2px border read as outlined, not picked.
    m.focusRing.opacity = pct
    m.focusGlow.opacity = pct * 0.85
    ' Brighten the artwork as it comes forward, 0.62 -> 0.85
    m.poster.opacity = 0.62 + (pct * 0.23)
    scale = 1.0 + (pct * 0.05)
    m.top.scale = [scale, scale]
end sub
