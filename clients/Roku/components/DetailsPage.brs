sub init()
    m.focusSection  = 0        ' 0=buttons  1=cast  2=similar
    m.selectedBtn   = 0
    m.numBtns       = 1
    m.savedPosition = 0.0
    m.mediaId       = 0
    m.kind          = ""
    m.title         = ""
    m.hlsUrl        = ""
    m.posterUri     = ""
    m.castIdx       = 0
    m.similarIdx    = 0
    m.numCast       = 0
    m.numSimilar    = 0
    m.castData        = []
    m.similarData     = []
    m.durationSeconds = 0.0

    m.scrollGroup         = m.top.findNode("scrollGroup")
    m.poster              = m.top.findNode("poster")
    m.backdrop            = m.top.findNode("backdrop")
    m.titleLabel          = m.top.findNode("titleLabel")
    m.metaLabel           = m.top.findNode("metaLabel")
    m.overviewLabel       = m.top.findNode("overviewLabel")
    m.genresLabel         = m.top.findNode("genresLabel")
    m.playBtn             = m.top.findNode("playBtn")
    m.playBtnLabel        = m.top.findNode("playBtnLabel")
    m.episodesBtn         = m.top.findNode("episodesBtn")
    m.episodesBtnLbl      = m.top.findNode("episodesBtnLabel")
    m.castSectionLabel    = m.top.findNode("castSectionLabel")
    m.castRow             = m.top.findNode("castRow")
    m.similarSectionLabel = m.top.findNode("similarSectionLabel")
    m.similarRow          = m.top.findNode("similarRow")
    m.hintLabel           = m.top.findNode("hintLabel")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.top.observeField("params", "onParams")
    m.top.setFocus(true)
end sub

' ── Params handler ─────────────────────────────────────────────────────────

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return

    m.mediaId = p.mediaId
    m.kind    = p.kind
    m.title   = p.title
    m.titleLabel.text = m.title

    ' Meta line: "2024  ·  Movie" or "TV Show"
    meta = ""
    yr = p.year
    if yr <> invalid and yr <> "" then meta = yr
    if m.kind = "show" then
        if meta <> "" then meta = meta + "  ·  "
        meta = meta + "TV Show"
    else if m.kind = "movie" then
        if meta <> "" then meta = meta + "  ·  "
        meta = meta + "Movie"
    end if
    m.metaLabel.text = meta

    ov = p.overview
    if ov <> invalid then m.overviewLabel.text = ov

    m.posterUri = ""
    pu = p.posterUrl
    if pu <> invalid and pu <> "" then
        m.poster.uri   = pu
        m.backdrop.uri = pu
        m.posterUri    = pu
    end if

    m.hlsUrl = BuildHlsUrl(m.serverUrl, m.token, m.mediaId)

    if m.kind = "show" then
        m.episodesBtn.visible    = true
        m.episodesBtnLbl.visible = true
        m.numBtns = 2
    else
        m.numBtns = 1
    end if

    highlightBtn(0)
    fetchMediaDetail()
    fetchSimilar()
    fetchHistory()
end sub

' ── API fetches ────────────────────────────────────────────────────────────

sub fetchMediaDetail()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/" + m.mediaId.ToStr()
    task.token = m.token
    task.observeField("result",   "onDetailResult")
    task.observeField("apiError", "onDetailError")
    task.control = "run"
    m.detailTask = task
end sub

sub fetchSimilar()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/" + m.mediaId.ToStr() + "/similar"
    task.token = m.token
    task.observeField("resultArr", "onSimilarResult")
    task.control = "run"
    m.similarTask = task
end sub

sub fetchHistory()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/history/" + m.mediaId.ToStr()
    task.token = m.token
    task.observeField("result", "onHistoryResult")
    task.control = "run"
    m.historyTask = task
end sub

' ── Result handlers ────────────────────────────────────────────────────────

sub onDetailResult(event as object)
    data = event.getData()
    if data = invalid then return

    ' Back-fill poster / overview / year for items reached via similar row
    if m.posterUri = "" then
        pu = data.poster_url
        if pu <> invalid and pu <> "" then
            resolved = ResolveUrl(m.serverUrl, pu)
            m.poster.uri   = resolved
            m.backdrop.uri = resolved
            m.posterUri    = resolved
        end if
    end if
    if m.overviewLabel.text = "" then
        ov = data.overview
        if ov <> invalid then m.overviewLabel.text = ov
    end if
    rd = data.release_date
    if rd <> invalid and Len(rd) >= 4 then
        yr = Left(rd, 4)
        if Instr(1, m.metaLabel.text, yr) = 0 then
            if m.metaLabel.text <> "" then
                m.metaLabel.text = yr + "  ·  " + m.metaLabel.text
            else
                m.metaLabel.text = yr
            end if
        end if
    end if

    durSec = data.duration_seconds
    if durSec <> invalid and durSec > 0 then m.durationSeconds = durSec

    extra = data.extra_json
    if extra = invalid then return

    ' Genres
    genres = extra.genres
    if genres <> invalid and genres.count() > 0 then
        genreStr = ""
        for i = 0 to genres.count() - 1
            if i > 0 then genreStr = genreStr + "  ·  "
            g = genres[i]
            if g <> invalid then genreStr = genreStr + g
        end for
        m.genresLabel.text = genreStr
    end if

    ' Cast
    cast = extra.cast
    if cast <> invalid and cast.count() > 0 then
        m.castData = cast
        buildCastRow(cast)
    end if
end sub

sub onDetailError(event as object)
end sub

sub onSimilarResult(event as object)
    data = event.getData()
    if data = invalid then return
    if data.count() = 0 then return
    m.similarData = data
    buildSimilarRow(data)
end sub

sub onHistoryResult(event as object)
    data = event.getData()
    if data = invalid then return
    posSec = data["position_seconds"]
    if posSec <> invalid and posSec > 5 then
        m.savedPosition = posSec
    end if
end sub

' ── Cast row builder ───────────────────────────────────────────────────────

sub buildCastRow(castArr as object)
    CARD_W   = 190
    CARD_H   = 250
    STRIDE   = 220      ' card width + 30px gap
    BDR      = 10       ' border thickness — thick enough to see around photos
    MAX_CAST = 12

    limit = castArr.count()
    if limit > MAX_CAST then limit = MAX_CAST

    for i = 0 to limit - 1
        actor = castArr[i]
        if actor = invalid then exit for

        card             = CreateObject("roSGNode", "Group")
        card.id          = "castCard_" + i.ToStr()
        card.translation = [i * STRIDE, 0]

        ' Border rectangle — 4px larger on all sides, sits behind the photo
        ' Default dark, highlighted = bright blue
        bg              = CreateObject("roSGNode", "Rectangle")
        bg.id           = "castBg_" + i.ToStr()
        bg.translation  = [-BDR, -BDR]
        bg.width        = CARD_W + BDR * 2
        bg.height       = CARD_H + BDR * 2
        bg.color        = "0x0D1A2EFF"
        card.appendChild(bg)

        ' Profile photo — sits on top of bg, exposing 4px border around edges
        prof                 = CreateObject("roSGNode", "Poster")
        prof.width           = CARD_W
        prof.height          = CARD_H
        prof.loadDisplayMode = "scaleToZoom"
        photoUrl = actor.photo
        if photoUrl <> invalid and photoUrl <> "" then
            prof.uri = photoUrl
        end if
        card.appendChild(prof)

        ' Actor name (2 lines)
        nameLabel             = CreateObject("roSGNode", "Label")
        nameLabel.id          = "castName_" + i.ToStr()
        nameLabel.translation = [0, CARD_H + 10]
        nameLabel.width       = CARD_W
        nameLabel.numLines    = 2
        nameLabel.wrap        = true
        nameLabel.font        = "font:SmallBoldSystemFont"
        nameLabel.color       = "0xBBBBBBFF"
        actorName = actor.name
        if actorName <> invalid then nameLabel.text = actorName
        card.appendChild(nameLabel)

        ' Role / character
        roleLabel             = CreateObject("roSGNode", "Label")
        roleLabel.translation = [0, CARD_H + 58]
        roleLabel.width       = CARD_W
        roleLabel.numLines    = 1
        roleLabel.font        = "font:SmallSystemFont"
        roleLabel.color       = "0x888888FF"
        actorRole = actor.role
        if actorRole <> invalid then roleLabel.text = actorRole
        card.appendChild(roleLabel)

        m.castRow.appendChild(card)
    end for

    m.numCast = limit
    if limit > 0 then
        m.castSectionLabel.opacity = 1.0
        m.castIdx = 0
    end if

    updateHint()
end sub

' ── Similar row builder ────────────────────────────────────────────────────

sub buildSimilarRow(items as object)
    CARD_W  = 200
    CARD_H  = 300       ' proper 2:3 poster ratio
    STRIDE  = 232       ' card width + 32px gap
    BDR     = 10        ' border thickness
    MAX_SIM = 11

    limit = items.count()
    if limit > MAX_SIM then limit = MAX_SIM

    for i = 0 to limit - 1
        item = items[i]
        if item = invalid then exit for

        card             = CreateObject("roSGNode", "Group")
        card.id          = "simCard_" + i.ToStr()
        card.translation = [i * STRIDE, 0]

        ' Border rectangle — 4px around card, hidden by default
        simBdr              = CreateObject("roSGNode", "Rectangle")
        simBdr.id           = "simBorder_" + i.ToStr()
        simBdr.translation  = [-BDR, -BDR]
        simBdr.width        = CARD_W + BDR * 2
        simBdr.height       = CARD_H + BDR * 2
        simBdr.color        = "0x0D1A2EFF"
        card.appendChild(simBdr)

        ' Poster image — sits on top of border
        p                    = CreateObject("roSGNode", "Poster")
        p.width              = CARD_W
        p.height             = CARD_H
        p.loadDisplayMode    = "scaleToZoom"
        posterUrl = item.poster_url
        if posterUrl <> invalid and posterUrl <> "" then
            p.uri = ResolveUrl(m.serverUrl, posterUrl)
        end if
        card.appendChild(p)

        ' Title label (2 lines)
        titleLbl             = CreateObject("roSGNode", "Label")
        titleLbl.translation = [0, CARD_H + 10]
        titleLbl.width       = CARD_W
        titleLbl.numLines    = 2
        titleLbl.wrap        = true
        titleLbl.font        = "font:SmallSystemFont"
        titleLbl.color       = "0xCCCCCCFF"
        itemTitle = item.title
        if itemTitle <> invalid then titleLbl.text = itemTitle
        card.appendChild(titleLbl)

        m.similarRow.appendChild(card)
    end for

    m.numSimilar = limit
    if limit > 0 then
        m.similarSectionLabel.opacity = 1.0
        m.similarIdx = 0
    end if
end sub

' ── Scroll helper ──────────────────────────────────────────────────────────
'
'  Section Y positions in scrollGroup (matches XML):
'    0 = buttons    → scroll to 0   (info panel fully visible)
'    1 = cast       → castSectionLabel Y=638  → scroll 478 so label sits at Y=160
'    2 = similar    → similarSectionLabel Y=2200 → scroll 2040 so label sits at Y=160

sub scrollToSection(section as integer)
    LABEL_TARGET_Y = 160
    scrollY = 0
    if section = 1 then
        scrollY = 638 - LABEL_TARGET_Y    ' = 478
    else if section = 2 then
        scrollY = 2200 - LABEL_TARGET_Y   ' = 2040
    end if
    m.scrollGroup.translation = [0, -scrollY]
end sub

' ── Highlight helpers ──────────────────────────────────────────────────────

sub highlightBtn(idx as integer)
    m.selectedBtn = idx
    if idx = 0 then
        m.playBtn.color        = "0x4A9FFFFF"
        m.episodesBtn.color    = "0x1A2A4AFF"
        m.playBtnLabel.color   = "0xFFFFFFFF"
        m.episodesBtnLbl.color = "0xCCCCCCFF"
    else
        m.playBtn.color        = "0x1A2A4AFF"
        m.episodesBtn.color    = "0x4A9FFFFF"
        m.playBtnLabel.color   = "0xCCCCCCFF"
        m.episodesBtnLbl.color = "0xFFFFFFFF"
    end if
end sub

sub highlightCast(idx as integer)
    clearCastHighlight()
    m.castIdx = idx
    bg = m.top.findNode("castBg_" + idx.ToStr())
    if bg <> invalid then bg.color = "0x4A9FFFFF"
    nm = m.top.findNode("castName_" + idx.ToStr())
    if nm <> invalid then nm.color = "0x4A9FFFFF"
end sub

sub clearCastHighlight()
    bg = m.top.findNode("castBg_" + m.castIdx.ToStr())
    if bg <> invalid then bg.color = "0x0D1A2EFF"
    nm = m.top.findNode("castName_" + m.castIdx.ToStr())
    if nm <> invalid then nm.color = "0xBBBBBBFF"
end sub

sub highlightSimilar(idx as integer)
    clearSimilarHighlight()
    m.similarIdx = idx
    simBdr = m.top.findNode("simBorder_" + idx.ToStr())
    if simBdr <> invalid then simBdr.color = "0x4A9FFFFF"
end sub

sub clearSimilarHighlight()
    simBdr = m.top.findNode("simBorder_" + m.similarIdx.ToStr())
    if simBdr <> invalid then simBdr.color = "0x0D1A2EFF"
end sub

sub focusSection(section as integer)
    m.focusSection = section
    if section = 0 then
        clearCastHighlight()
        clearSimilarHighlight()
        highlightBtn(m.selectedBtn)
    else if section = 1 then
        highlightCast(m.castIdx)
    else if section = 2 then
        highlightSimilar(m.similarIdx)
    end if
    scrollToSection(section)
    updateHint()
end sub

sub updateHint()
    if m.numCast > 0 or m.numSimilar > 0 then
        m.hintLabel.text = "Back=return   Up/Down=sections   Left/Right=scroll   OK=select"
    else
        m.hintLabel.text = "Back=return   Left/Right=switch   OK=select"
    end if
end sub

' ── Key handler ────────────────────────────────────────────────────────────

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back" then
        m.top.navRequest = {action: "back"}
        return true
    end if

    if key = "options" then
        m.top.navRequest = {action: "signout"}
        return true
    end if

    ' ── Vertical section navigation ───────────────────────────────────────

    if key = "up" then
        if m.focusSection = 1 then
            focusSection(0)
            return true
        else if m.focusSection = 2 then
            if m.numCast > 0 then
                focusSection(1)
            else
                focusSection(0)
            end if
            return true
        end if
        return false
    end if

    if key = "down" then
        if m.focusSection = 0 then
            if m.numCast > 0 then
                focusSection(1)
                return true
            else if m.numSimilar > 0 then
                focusSection(2)
                return true
            end if
        else if m.focusSection = 1 then
            if m.numSimilar > 0 then
                focusSection(2)
                return true
            end if
        end if
        return false
    end if

    ' ── Horizontal navigation within focused section ───────────────────────

    if m.focusSection = 0 then
        if key = "left" and m.selectedBtn = 1 then
            highlightBtn(0)
            return true
        end if
        if key = "right" and m.selectedBtn = 0 and m.numBtns > 1 then
            highlightBtn(1)
            return true
        end if
        if key = "OK" then
            if m.selectedBtn = 1 then
                req = {action: "episodes", showId: m.mediaId, title: m.title, posterUrl: m.posterUri}
                m.top.navRequest = req
            else
                req = {action: "play", mediaId: m.mediaId, title: m.title, url: m.hlsUrl, durationSeconds: m.durationSeconds}
                req["position"] = m.savedPosition
                m.top.navRequest = req
            end if
            return true
        end if

    else if m.focusSection = 1 then
        if key = "left" and m.castIdx > 0 then
            highlightCast(m.castIdx - 1)
            return true
        end if
        if key = "right" and m.castIdx < m.numCast - 1 then
            highlightCast(m.castIdx + 1)
            return true
        end if
        if key = "OK" then return true

    else if m.focusSection = 2 then
        if key = "left" and m.similarIdx > 0 then
            highlightSimilar(m.similarIdx - 1)
            return true
        end if
        if key = "right" and m.similarIdx < m.numSimilar - 1 then
            highlightSimilar(m.similarIdx + 1)
            return true
        end if
        if key = "OK" then
            sim = m.similarData[m.similarIdx]
            if sim <> invalid then
                req = {action: "details", mediaId: sim.id, title: sim.title, kind: m.kind, posterUrl: sim.poster_url}
                m.top.navRequest = req
            end if
            return true
        end if
    end if

    return false
end function
