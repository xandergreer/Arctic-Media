sub init()
    m.poster      = m.top.findNode("poster")
    m.focusBorder = m.top.findNode("focusBorder")
    m.titleBg     = m.top.findNode("titleBg")
    m.titleLabel  = m.top.findNode("titleLabel")
    m.top.observeField("itemContent",  "onContent")
    m.top.observeField("focusPercent", "onFocus")
end sub

sub onContent(event as object)
    content = event.getData()
    if content = invalid then return
    uri = content.hdPosterUrl
    if uri = invalid then uri = ""
    m.poster.uri  = uri
    m.titleLabel.text = content.title
end sub

sub onFocus(event as object)
    pct = event.getData()
    m.focusBorder.opacity = pct * 0.8
    m.titleBg.opacity     = pct * 1.0
    m.titleLabel.opacity  = pct * 1.0
end sub
