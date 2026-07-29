sub init()
    m.keyboard       = m.top.findNode("keyboard")
    m.hintLabel      = m.top.findNode("hintLabel")
    m.noResultsLabel = m.top.findNode("noResultsLabel")
    m.resultsHeader  = m.top.findNode("resultsHeader")
    m.resultsGrid    = m.top.findNode("resultsGrid")
    m.kbHint         = m.top.findNode("kbHint")
    m.resHint        = m.top.findNode("resHint")

    m.serverUrl = GetReg("server_url").Trim()
    m.token     = GetReg("access_token")

    m.results   = []
    m.inResults = false

    ' Debounce: fire search 600ms after last keystroke
    m.searchTimer = CreateObject("roSGNode", "Timer")
    m.searchTimer.duration = 0.6
    m.searchTimer.repeat   = false
    m.searchTimer.observeField("fire", "doSearch")

    m.keyboard.observeField("text", "onKeyboardText")
    m.resultsGrid.observeField("itemSelected", "onResultSelected")
    m.top.observeField("restoreFocus", "onRestoreFocus")

    ' setFocus on keyboard must happen AFTER pushPage appends us to the scene.
    m.focusTimer = CreateObject("roSGNode", "Timer")
    m.focusTimer.duration = 0.1
    m.focusTimer.repeat   = false
    m.focusTimer.observeField("fire", "onFocusTimer")
    m.focusTimer.control  = "start"
end sub

sub onFocusTimer()
    if not m.inResults then m.keyboard.setFocus(true)
end sub

' Called by MainScene after popping back to this page — refocus whichever
' control the user was on so input works immediately.
sub onRestoreFocus(event as object)
    if not event.getData() then return
    if m.inResults
        m.resultsGrid.setFocus(true)
    else
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
    encoded = UrlEncode(txt)
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

    ' Flat list, movies first then shows
    m.results = []
    for each mv in movies
        m.results.push(mv)
    end for
    for each sh in shows
        m.results.push(sh)
    end for

    if m.results.count() = 0
        m.resultsGrid.visible   = false
        m.resultsHeader.visible = false
        m.hintLabel.visible     = false
        m.noResultsLabel.visible = true
        return
    end if

    m.hintLabel.visible      = false
    m.noResultsLabel.visible = false
    m.resultsHeader.visible  = true

    root = CreateObject("roSGNode", "ContentNode")
    for each media in m.results
        it = root.createChild("ContentNode")
        it.title = media.title
        posterUrl = ""
        if media.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, media.poster_url)
        it.hdPosterUrl = posterUrl
    end for
    m.resultsGrid.content = root
    m.resultsGrid.visible = true
end sub

sub onSearchError(event as object)
    clearResults()
    m.hintLabel.visible = true
end sub

sub clearResults()
    m.results = []
    m.resultsGrid.content   = invalid
    m.resultsGrid.visible   = false
    m.resultsHeader.visible = false
    m.noResultsLabel.visible = false
    if m.inResults then setResultsMode(false)
end sub

' ── Focus mode ───────────────────────────────────────────────────

sub setResultsMode(enable as boolean)
    m.inResults = enable
    if enable
        m.kbHint.visible  = false
        m.resHint.visible = true
        m.resultsGrid.jumpToItem = 0
        m.resultsGrid.setFocus(true)
    else
        m.resHint.visible = false
        m.kbHint.visible  = true
        m.keyboard.setFocus(true)
    end if
end sub

sub onResultSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.results.count() then return
    media = m.results[idx]

    kind = ""
    if media.kind <> invalid then kind = media.kind
    posterUrl = ""
    if media.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, media.poster_url)
    overview = ""
    if media.overview <> invalid then overview = media.overview
    year = ""
    if media.release_date <> invalid and Len(media.release_date) >= 4 then year = Left(media.release_date, 4)

    m.top.navRequest = {
        action:    "details"
        mediaId:   media.id
        title:     media.title
        kind:      kind
        posterUrl: posterUrl
        overview:  overview
        year:      year
    }
end sub

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
        else if m.results.count() > 0
            setResultsMode(true)
        end if
        return true
    end if

    return false
end function
