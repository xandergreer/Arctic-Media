sub init()
    m.poster      = m.top.findNode("poster")
    m.focusBorder = m.top.findNode("focusBorder")
    m.titleBg     = m.top.findNode("titleBg")
    m.titleLabel  = m.top.findNode("titleLabel")
    m.top.scaleRotateCenter = [140, 79]
    m.top.observeField("itemContent",  "onContent")
    m.top.observeField("focusPercent", "onFocus")
end sub

sub onContent(event as object)
    content = event.getData()
    if content = invalid then return
    m.titleLabel.text = content.title
    uri = content.hdPosterUrl
    if uri = invalid then uri = ""
    m.poster.uri = uri
end sub

sub onFocus(event as object)
    pct = event.getData()
    m.focusBorder.opacity = pct * 0.9
    m.titleBg.opacity     = pct
    m.titleLabel.opacity  = pct
    scale = 1.0 + (pct * 0.05)
    m.top.scale = [scale, scale]
end sub
