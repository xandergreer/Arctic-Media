sub init()
    m.bg          = m.top.findNode("bg")
    m.poster      = m.top.findNode("poster")
    m.focusBorder = m.top.findNode("focusBorder")
    m.titleLabel  = m.top.findNode("titleLabel")
    m.top.scaleRotateCenter = [160, 90]
    m.top.observeField("itemContent",  "onContent")
    m.top.observeField("focusPercent", "onFocus")
end sub

sub onContent(event as object)
    content = event.getData()
    if content = invalid then return
    m.titleLabel.text = content.title
    if content.bgColor <> invalid then m.bg.color = content.bgColor
    uri = content.hdPosterUrl
    if uri = invalid or uri = "" then return
    m.poster.uri = uri
end sub

sub onFocus(event as object)
    pct = event.getData()
    m.focusBorder.opacity = pct * 0.9
    scale = 1.0 + (pct * 0.05)
    m.top.scale = [scale, scale]
end sub
