sub init()
    m.rowList      = m.top.findNode("rowList")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.userLabel    = m.top.findNode("userLabel")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.continueRows = invalid
    m.movieItems   = invalid
    m.showItems    = invalid

    m.rowList.observeField("itemSelected", "onItemSelected")

    ' Load all rows in parallel
    loadContinueWatching()
    loadMovies()
    loadShows()
end sub

' -------------------------------------------------------
' Data loading
' -------------------------------------------------------

sub loadContinueWatching()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/history"
    task.token = m.token
    task.observeField("resultArr", "onContinueResult")
    task.observeField("apiError",  "onContinueError")
    task.control = "run"
    m.cwTask = task
end sub

sub loadMovies()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/movies?skip=0&limit=200"
    task.token = m.token
    task.observeField("resultArr", "onMoviesResult")
    task.observeField("apiError",  "onMoviesError")
    task.control = "run"
    m.moviesTask = task
end sub

sub loadShows()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/shows?skip=0&limit=200"
    task.token = m.token
    task.observeField("resultArr", "onShowsResult")
    task.observeField("apiError",  "onShowsError")
    task.control = "run"
    m.showsTask = task
end sub

sub onContinueResult(event as object)
    items = event.getData()
    m.continueRows = items
    rebuildContent()
end sub

sub onContinueError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.continueRows = []
    rebuildContent()
end sub

sub onMoviesResult(event as object)
    m.movieItems = event.getData()
    rebuildContent()
end sub

sub onMoviesError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.movieItems = []
    rebuildContent()
end sub

sub onShowsResult(event as object)
    m.showItems = event.getData()
    rebuildContent()
end sub

sub onShowsError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.showItems = []
    rebuildContent()
end sub

' -------------------------------------------------------
' Build RowList content
' -------------------------------------------------------

sub rebuildContent()
    ' Wait until we have at least movies or shows
    if m.movieItems = invalid and m.showItems = invalid then return

    root = CreateObject("roSGNode", "ContentNode")

    ' Continue Watching row (only if we have items)
    if m.continueRows <> invalid and m.continueRows.count() > 0
        cwRow = CreateObject("roSGNode", "ContentNode")
        cwRow.title = "Continue Watching"
        for each cw in m.continueRows
            item = CreateObject("roSGNode", "ContentNode")
            item.title = cw.title
            posterUrl = ""
            if cw.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, cw.poster_url)
            item.hdPosterUrl = posterUrl
            item.addFields({
                mediaId:  cw.media_id
                kind:     cw.kind
                showId:   cw.show_id
                position: cw.position_seconds
            })
            cwRow.appendChild(item)
        end for
        root.appendChild(cwRow)
    end if

    ' Movies row
    if m.movieItems <> invalid and m.movieItems.count() > 0
        movRow = CreateObject("roSGNode", "ContentNode")
        movRow.title = "Movies"
        for each media in m.movieItems
            item = createMediaNode(media)
            movRow.appendChild(item)
        end for
        root.appendChild(movRow)
    end if

    ' TV Shows row
    if m.showItems <> invalid and m.showItems.count() > 0
        showRow = CreateObject("roSGNode", "ContentNode")
        showRow.title = "TV Shows"
        for each media in m.showItems
            item = createMediaNode(media)
            showRow.appendChild(item)
        end for
        root.appendChild(showRow)
    end if

    m.rowList.content = root
    m.loadingLabel.visible = false
    m.rowList.setFocus(true)
end sub

function createMediaNode(media as object) as object
    item = CreateObject("roSGNode", "ContentNode")
    item.title = media.title
    posterUrl = ""
    if media.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, media.poster_url)
    item.hdPosterUrl = posterUrl
    item.addFields({
        mediaId:   media.id
        kind:      media.kind
        parentId:  media.parent_id
        overview:  media.overview
        year:      ""
        position:  0.0
    })
    if media.release_date <> invalid and Len(media.release_date) >= 4
        item.year = Left(media.release_date, 4)
    end if
    return item
end function

' -------------------------------------------------------
' Item selection
' -------------------------------------------------------

sub onItemSelected(event as object)
    idx = event.getData()  ' [rowIndex, itemIndex]
    if idx = invalid then return

    rowIdx  = idx[0]
    itemIdx = idx[1]

    row = m.rowList.content.getChild(rowIdx)
    if row = invalid then return
    item = row.getChild(itemIdx)
    if item = invalid then return

    kind = item.kind
    mediaId = item.mediaId

    if kind = "movie"
        ' Get saved position, then play
        position = 0.0
        if item.position <> invalid then position = item.position
        hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)
        m.top.navRequest = {
            action:     "play"
            mediaId:    mediaId
            title:      item.title
            url:        hlsUrl
            position:   position
            posterUrl:  item.hdPosterUrl
            overview:   item.overview
        }

    else if kind = "episode"
        ' Navigate to the show if we have showId
        showId = item.showId
        if showId <> invalid and showId <> 0
            m.top.navRequest = {
                action:  "episodes"
                showId:  showId
                title:   item.title
            }
        else
            position = 0.0
            if item.position <> invalid then position = item.position
            hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)
            m.top.navRequest = {
                action:   "play"
                mediaId:  mediaId
                title:    item.title
                url:      hlsUrl
                position: position
            }
        end if

    else if kind = "show"
        m.top.navRequest = {
            action:     "details"
            mediaId:    mediaId
            title:      item.title
            kind:       kind
            posterUrl:  item.hdPosterUrl
            overview:   item.overview
            year:       item.year
        }

    end if
end sub

' -------------------------------------------------------
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        ' At home root — ignore (user can press Roku home)
        return true
    end if

    if key = "options"
        m.top.navRequest = {action: "signout"}
        return true
    end if

    return false
end function
