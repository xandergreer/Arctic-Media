sub init()
    m.keyboard       = m.top.findNode("keyboard")
    m.hintLabel      = m.top.findNode("hintLabel")
    m.noResultsLabel = m.top.findNode("noResultsLabel")
    m.labelMovies    = m.top.findNode("labelMovies")
    m.movieRow       = m.top.findNode("movieRow")
    m.labelShows     = m.top.findNode("labelShows")
    m.showRow        = m.top.findNode("showRow")
    m.kbHint         = m.top.findNode("kbHint")
    m.resHint        = m.top.findNode("resHint")

    m.serverUrl = GetReg("server_url").Trim()
    m.token     = GetReg("access_token")

    m.movieResults = []
    m.showResults  = []
    m.inResults    = false
    m.resultRow    = 0       ' 0 = movies, 1 = shows
    m.resultColIdx = [0, 0]

    ' Debounce: fire search 600ms after last keystroke
    m.searchTimer = CreateObject("roSGNode", "Timer")
    m.searchTimer.duration = 0.6
    m.searchTimer.repeat   = false
    m.searchTimer.observeField("fire", "doSearch")

    m.keyboard.observeField("text", "onKeyboardText")

    ' setFocus on keyboard must happen AFTER pushPage appends us to the scene
    ' and calls page.setFocus(true). A short timer fires after that completes.
    m.focusTimer = CreateObject("roSGNode", "Timer")
    m.focusTimer.duration = 0.1
    m.focusTimer.repeat   = false
    m.focusTimer.observeField("fire", "onFocusTimer")
    m.focusTimer.control  = "start"
end sub

sub onFocusTimer()
    if not m.inResults
        m.keyboard.setFocus(true)
    end if
end sub

' ── Keyboard input ────────────────────────────────────────────────

sub onKeyboardText(event as object)
    txt = event.getData()
    if Len(txt) < 2
        clearResults()
        m.hintLabel.visible      = true
        m.noResultsLabel.visible = false
        m.searchTimer.control    = "stop"
        return
    end if
    m.searchTimer.control = "stop"
    m.searchTimer.control = "start"
end sub

sub doSearch(event as object)
    txt = m.keyboard.text
    if Len(txt) < 2 then return
    xfer    = CreateObject("roUrlTransfer")
    encoded = xfer.Escape(txt)
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/search?q=" + encoded
    task.token = m.token
    task.observeField("result",   "onSearchResult")
    task.observeField("apiError", "onSearchError")
    task.control = "run"
    m.searchTask = task
end sub

' ── Results ──────────────────────────────────────────────────────

sub onSearchResult(event as object)
    data = event.getData()
    if data = invalid then return

    movies = data.movies
    shows  = data.shows
    if movies = invalid then movies = []
    if shows  = invalid then shows  = []

    m.movieResults = movies
    m.showResults  = shows

    clearResultNodes()

    hasMovies = movies.count() > 0
    hasShows  = shows.count() > 0

    if not hasMovies and not hasShows
        m.hintLabel.visible      = false
        m.noResultsLabel.visible = true
        return
    end if

    m.hintLabel.visible      = false
    m.noResultsLabel.visible = false

    if hasMovies
        m.labelMovies.visible = true
        m.movieRow.visible    = true
        buildResultRow(m.movieRow, movies)
    end if
    if hasShows
        m.labelShows.visible = true
        m.showRow.visible    = true
        buildResultRow(m.showRow, shows)
    end if
end sub

sub onSearchError(event as object)
    clearResultNodes()
    m.hintLabel.visible = true
end sub

sub clearResults()
    clearResultNodes()
    m.movieResults = []
    m.showResults  = []
    m.resultColIdx = [0, 0]
    if m.inResults then setResultsMode(false)
end sub

sub clearResultNodes()
    m.labelMovies.visible = false
    m.movieRow.visible    = false
    m.labelShows.visible  = false
    m.showRow.visible     = false
    while m.movieRow.getChildCount() > 0
        m.movieRow.removeChildIndex(0)
    end while
    while m.showRow.getChildCount() > 0
        m.showRow.removeChildIndex(0)
    end while
end sub

sub buildResultRow(rowGroup as object, items as object)
    maxItems = 4
    stride   = 218
    i = 0
    for each media in items
        if i >= maxItems then exit for
        item = CreateObject("roSGNode", "PosterItem")
        item.translation = [i * stride, 0]
        cn = CreateObject("roSGNode", "ContentNode")
        cn.title = media.title
        posterUrl = ""
        if media.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, media.poster_url)
        cn.hdPosterUrl = posterUrl
        cn.addFields({
            mediaId:  media.id
            kind:     media.kind
            overview: iif(media.overview <> invalid, media.overview, "")
            year:     ""
        })
        if media.release_date <> invalid and Len(media.release_date) >= 4
            cn.year = Left(media.release_date, 4)
        end if
        item.itemContent  = cn
        item.focusPercent = 0.0
        rowGroup.appendChild(item)
        i = i + 1
    end for
end sub

' ── Focus mode ───────────────────────────────────────────────────

sub setResultsMode(enable as boolean)
    m.inResults = enable
    if enable
        m.top.setFocus(true)
        m.kbHint.visible  = false
        m.resHint.visible = true
        ' Default to movies row if available, else shows
        if m.movieResults.count() > 0
            m.resultRow = 0
        else
            m.resultRow = 1
        end if
        setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
    else
        clearAllResultFocus()
        m.resHint.visible = false
        m.kbHint.visible  = true
        m.keyboard.setFocus(true)
    end if
end sub

sub setResultItemFocus(rowIdx as integer, colIdx as integer)
    rowGroup = rowGroupForIdx(rowIdx)
    if rowGroup = invalid then return
    for i = 0 to rowGroup.getChildCount() - 1
        ch = rowGroup.getChild(i)
        if ch <> invalid then ch.focusPercent = 0.0
    end for
    ch = rowGroup.getChild(colIdx)
    if ch <> invalid then ch.focusPercent = 1.0
end sub

sub clearAllResultFocus()
    for i = 0 to m.movieRow.getChildCount() - 1
        ch = m.movieRow.getChild(i)
        if ch <> invalid then ch.focusPercent = 0.0
    end for
    for i = 0 to m.showRow.getChildCount() - 1
        ch = m.showRow.getChild(i)
        if ch <> invalid then ch.focusPercent = 0.0
    end for
end sub

function rowGroupForIdx(rowIdx as integer) as dynamic
    if rowIdx = 0 then return m.movieRow
    if rowIdx = 1 then return m.showRow
    return invalid
end function

' ── Key handling ─────────────────────────────────────────────────

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        if m.inResults
            setResultsMode(false)
            return true
        end if
        m.searchTimer.control = "stop"
        m.top.navRequest = {action: "back"}
        return true
    end if

    if key = "options"
        if m.inResults
            setResultsMode(false)
        else if m.movieResults.count() > 0 or m.showResults.count() > 0
            setResultsMode(true)
        end if
        return true
    end if

    if m.inResults then return handleResultsKey(key)

    return false
end function

function handleResultsKey(key as string) as boolean
    rowGroup = rowGroupForIdx(m.resultRow)
    if rowGroup = invalid then return true

    if key = "up"
        if m.resultRow = 1 and m.movieResults.count() > 0
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
            m.resultRow = 0
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
        end if
        return true
    end if

    if key = "down"
        if m.resultRow = 0 and m.showResults.count() > 0
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
            m.resultRow = 1
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
        end if
        return true
    end if

    if key = "left"
        idx = m.resultColIdx[m.resultRow]
        if idx > 0
            m.resultColIdx[m.resultRow] = idx - 1
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
        end if
        return true
    end if

    if key = "right"
        idx    = m.resultColIdx[m.resultRow]
        maxIdx = rowGroup.getChildCount() - 1
        if idx < maxIdx
            m.resultColIdx[m.resultRow] = idx + 1
            setResultItemFocus(m.resultRow, m.resultColIdx[m.resultRow])
        end if
        return true
    end if

    if key = "OK"
        idx  = m.resultColIdx[m.resultRow]
        item = rowGroup.getChild(idx)
        if item = invalid then return true
        cn = item.itemContent
        if cn = invalid then return true
        kind = cn.kind
        nav = {action: "details", mediaId: cn.mediaId, title: cn.title, kind: kind, posterUrl: cn.hdPosterUrl, overview: cn.overview, year: cn.year}
        m.top.navRequest = nav
        return true
    end if

    return false
end function
