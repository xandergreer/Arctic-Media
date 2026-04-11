sub init()
    ' Tab nodes
    m.tabHome     = m.top.findNode("tabHome")
    m.tabMovies   = m.top.findNode("tabMovies")
    m.tabShows    = m.top.findNode("tabShows")
    m.tabSettings = m.top.findNode("tabSettings")
    m.tabSearch   = m.top.findNode("tabSearch")
    m.tabLine     = m.top.findNode("tabLine")

    ' Views
    m.homeView     = m.top.findNode("homeView")
    m.movieGrid    = m.top.findNode("movieGrid")
    m.showGrid     = m.top.findNode("showGrid")
    m.settingsView = m.top.findNode("settingsView")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.headerHint   = m.top.findNode("headerHint")
    m.gridHint     = m.top.findNode("gridHint")
    ' Home row label nodes
    m.labelCategories = m.top.findNode("labelCategories")
    m.labelCW         = m.top.findNode("labelCW")
    m.labelMovies     = m.top.findNode("labelMovies")
    m.labelShows      = m.top.findNode("labelShows")

    ' Home row group nodes
    m.categoryRowGroup = m.top.findNode("categoryRowGroup")
    m.cwRowGroup       = m.top.findNode("cwRowGroup")
    m.moviesRowGroup   = m.top.findNode("moviesRowGroup")
    m.showsRowGroup    = m.top.findNode("showsRowGroup")

    ' Tab positions: [Home, Movies, Shows, Settings, Search]
    m.tabLineX = [370, 530, 690, 890, 1070]
    m.tabLineW = [70,  90,  120, 110,  90]

    ' Custom grid config: 8 cols × 230px stride = 1840px (x40→1880)
    ' 3 visible rows × 300px stride = 900px (y126→1026)
    m.numGridCols   = 8
    m.gridStrideX   = 230
    m.gridStrideY   = 300
    m.movieRowGroups = []
    m.showRowGroups  = []
    m.movieRowItems  = []
    m.showRowItems   = []
    m.gridFocusRow   = 0
    m.gridFocusCol   = 0
    m.gridScrollTop  = 0

    m.serverUrl = GetReg("server_url").Trim()
    m.token     = GetReg("access_token")

    ' Settings view nodes
    m.sItem   = []
    m.sAccent = []
    m.sValue  = []
    for i = 0 to 4
        m.sItem.push(m.top.findNode("sItem" + i.ToStr()))
        m.sAccent.push(m.top.findNode("sAccent" + i.ToStr()))
        m.sValue.push(m.top.findNode("sValue" + i.ToStr()))
    end for
    m.sStatus0     = m.top.findNode("sStatus0")
    m.sAboutDevice = m.top.findNode("sAboutDevice")

    ' Settings state
    m.settFocusIdx    = 0
    m.settNumItems    = 5
    m.qualityOptions  = ["Auto", "1080p", "720p", "480p"]
    m.subtitleOptions = ["Off", "On"]
    m.qualityIdx      = 0
    m.subtitleIdx     = 0
    savedQ = GetReg("quality_pref")
    if savedQ <> ""
        for i = 0 to m.qualityOptions.count() - 1
            if m.qualityOptions[i] = savedQ then m.qualityIdx = i
        end for
    end if
    savedS = GetReg("subtitle_pref")
    if savedS <> ""
        for i = 0 to m.subtitleOptions.count() - 1
            if m.subtitleOptions[i] = savedS then m.subtitleIdx = i
        end for
    end if

    ' State
    m.continueRows   = invalid
    m.movieItems     = invalid   ' A-Z list for the Movies grid tab
    m.showItems      = invalid   ' A-Z list for the Shows grid tab
    m.recentMovies   = invalid   ' sort=added for home "Recently Added" row
    m.recentShows    = invalid   ' sort=added for home "Recently Added" row
    m.activeIdx      = 0
    m.inContent      = false
    m.homeRowsBuilt  = false
    m.movieGridBuilt = false
    m.showGridBuilt  = false

    ' Home row nav state (populated by buildHomeRows)
    m.numHomeRows   = 0
    m.activeHomeRow = 0
    m.homeScrollY   = 0
    m.rowFocusIdx   = []
    m.rowScrollX    = []
    m.homeRowGroups = invalid
    m.homeRowTypes  = invalid
    m.homeRowLabels = invalid
    m.homeRowStride = invalid
    m.homeRowWidth  = invalid

    m.top.observeField("onReturnedToHome", "onReturnedToHome")
    m.top.setFocus(true)
    updateTabs()

    loadContinueWatching()
    loadRecentMovies()
    loadRecentShows()
    loadMovies()
    loadShows()
end sub

' -------------------------------------------------------
' Tab highlight + view visibility
' -------------------------------------------------------

sub updateTabs()
    m.tabHome.color     = "0x555555FF"
    m.tabMovies.color   = "0x555555FF"
    m.tabShows.color    = "0x555555FF"
    m.tabSettings.color = "0x555555FF"
    m.tabSearch.color   = "0x555555FF"

    if m.activeIdx = 0
        m.tabHome.color = "0xFFFFFFFF"
    else if m.activeIdx = 1
        m.tabMovies.color = "0xFFFFFFFF"
    else if m.activeIdx = 2
        m.tabShows.color = "0xFFFFFFFF"
    else if m.activeIdx = 3
        m.tabSettings.color = "0xFFFFFFFF"
    else if m.activeIdx = 4
        m.tabSearch.color = "0xFFFFFFFF"
    end if

    m.tabLine.translation = [m.tabLineX[m.activeIdx], 104]
    m.tabLine.width       = m.tabLineW[m.activeIdx]

    m.homeView.visible     = (m.activeIdx = 0)
    m.movieGrid.visible    = (m.activeIdx = 1)
    m.showGrid.visible     = (m.activeIdx = 2)
    m.settingsView.visible = (m.activeIdx = 3)
    if m.activeIdx = 3 then loadSettingsInfo()
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
    task.url   = m.serverUrl + "/api/v1/media/movies?skip=0&limit=100&sort=az"
    task.token = m.token
    task.observeField("resultArr", "onMoviesResult")
    task.observeField("apiError",  "onMoviesError")
    task.control = "run"
    m.moviesTask = task
end sub

sub loadShows()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/shows?skip=0&limit=100&sort=az"
    task.token = m.token
    task.observeField("resultArr", "onShowsResult")
    task.observeField("apiError",  "onShowsError")
    task.control = "run"
    m.showsTask = task
end sub

sub loadRecentMovies()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/movies?skip=0&limit=20&sort=added"
    task.token = m.token
    task.observeField("resultArr", "onRecentMoviesResult")
    task.observeField("apiError",  "onRecentMoviesError")
    task.control = "run"
    m.recentMoviesTask = task
end sub

sub loadRecentShows()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/shows?skip=0&limit=20&sort=added"
    task.token = m.token
    task.observeField("resultArr", "onRecentShowsResult")
    task.observeField("apiError",  "onRecentShowsError")
    task.control = "run"
    m.recentShowsTask = task
end sub

sub onContinueResult(event as object)
    m.continueRows = event.getData()
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

sub onContinueError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.continueRows = []
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

sub onReturnedToHome(event as object)
    if not event.getData() then return   ' ignore false fires
    ' Silently refresh Continue Watching when returning from content.
    ' onContinueResult will reset homeRowsBuilt and rebuild rows with fresh CW data.
    loadContinueWatching()
end sub

sub onMoviesResult(event as object)
    m.movieItems     = event.getData()
    m.movieGridBuilt = false
    ' Grid tab: rebuild grid if Movies tab is active
    if m.activeIdx = 1 then buildMovieGrid()
end sub

sub onMoviesError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.movieItems = []
end sub

sub onShowsResult(event as object)
    m.showItems     = event.getData()
    m.showGridBuilt = false
    ' Grid tab: rebuild grid if Shows tab is active
    if m.activeIdx = 2 then buildShowGrid()
end sub

sub onShowsError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.showItems = []
end sub

' Recently-added data — drives home page rows only (sort=added, limit=20)
sub onRecentMoviesResult(event as object)
    m.recentMovies  = event.getData()
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

sub onRecentMoviesError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.recentMovies = []
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

sub onRecentShowsResult(event as object)
    m.recentShows = event.getData()
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

sub onRecentShowsError(event as object)
    if event.getData() = "Unauthorized"
        m.top.navRequest = {action: "signout"}
        return
    end if
    m.recentShows = []
    if not m.inContent
        m.homeRowsBuilt = false
        if m.activeIdx = 0 then buildHomeRows()
    end if
end sub

' -------------------------------------------------------
' Build home rows
' -------------------------------------------------------

sub buildHomeRows()
    if m.homeRowsBuilt then return
    if m.continueRows  = invalid then return  ' wait for CW data
    if m.recentMovies  = invalid then return  ' wait for recently-added movies
    if m.recentShows   = invalid then return  ' wait for recently-added shows

    hasCW     = m.continueRows <> invalid and m.continueRows.count() > 0
    hasMovies = m.recentMovies <> invalid and m.recentMovies.count() > 0
    hasShows  = m.recentShows  <> invalid and m.recentShows.count() > 0

    ' Reset row arrays
    m.homeRowGroups = []
    m.homeRowTypes  = []
    m.homeRowLabels = []
    m.homeRowStride = []
    m.homeRowWidth  = []

    ' ── Category tiles (always first) ───────────────────
    m.labelCategories.translation  = [40, 136]
    m.categoryRowGroup.translation = [40, 174]
    m.homeRowGroups.push(m.categoryRowGroup)
    m.homeRowTypes.push("category")
    m.homeRowLabels.push(m.labelCategories)
    m.homeRowStride.push(360)
    m.homeRowWidth.push(320)
    buildCategoryRow()

    ' PosterItem is 270px tall. Each row section = 38 (label) + 270 (poster) + 60 (gap) = 368px.
    ' Y cursor starts after category row (174 + 180 + 50 gap)
    ROW_STRIDE = 368   ' label + poster height + breathing room
    nextY = 404

    ' Reset homeView scroll
    m.homeScrollY = 0
    m.homeView.translation = [0, 0]

    ' ── Continue Watching ───────────────────────────────
    if hasCW
        m.labelCW.translation    = [40, nextY]
        m.labelCW.visible        = true
        m.cwRowGroup.translation = [40, nextY + 38]
        m.cwRowGroup.visible     = true
        m.homeRowGroups.push(m.cwRowGroup)
        m.homeRowTypes.push("poster")
        m.homeRowLabels.push(m.labelCW)
        m.homeRowStride.push(218)
        m.homeRowWidth.push(182)
        populateRowGroup(m.cwRowGroup, m.continueRows, "PosterItem", true)
        nextY = nextY + ROW_STRIDE
    else
        m.labelCW.visible    = false
        m.cwRowGroup.visible = false
    end if

    ' ── Recently Added Movies ────────────────────────────
    if hasMovies
        m.labelMovies.translation    = [40, nextY]
        m.labelMovies.visible        = true
        m.moviesRowGroup.translation = [40, nextY + 38]
        m.moviesRowGroup.visible     = true
        m.homeRowGroups.push(m.moviesRowGroup)
        m.homeRowTypes.push("poster")
        m.homeRowLabels.push(m.labelMovies)
        m.homeRowStride.push(218)
        m.homeRowWidth.push(182)
        populateRowGroup(m.moviesRowGroup, m.recentMovies, "PosterItem", false)
        nextY = nextY + ROW_STRIDE
    else
        m.labelMovies.visible    = false
        m.moviesRowGroup.visible = false
    end if

    ' ── Recently Added TV Shows ──────────────────────────────
    if hasShows
        m.labelShows.translation    = [40, nextY]
        m.labelShows.visible        = true
        m.showsRowGroup.translation = [40, nextY + 38]
        m.showsRowGroup.visible     = true
        m.homeRowGroups.push(m.showsRowGroup)
        m.homeRowTypes.push("poster")
        m.homeRowLabels.push(m.labelShows)
        m.homeRowStride.push(218)
        m.homeRowWidth.push(182)
        populateRowGroup(m.showsRowGroup, m.recentShows, "PosterItem", false)
        nextY = nextY + ROW_STRIDE
    else
        m.labelShows.visible    = false
        m.showsRowGroup.visible = false
    end if

    m.numHomeRows = m.homeRowGroups.count()

    ' Reset per-row focus/scroll state
    m.rowFocusIdx = []
    m.rowScrollX  = []
    for i = 0 to m.numHomeRows - 1
        m.rowFocusIdx.push(0)
        m.rowScrollX.push(40)
    end for
    m.activeHomeRow = 0

    updateRowLabels()
    m.homeRowsBuilt = true
    m.loadingLabel.visible = false
end sub

sub buildCategoryRow()
    while m.categoryRowGroup.getChildCount() > 0
        m.categoryRowGroup.removeChildIndex(0)
    end while

    categories = [
        {title: "Movies",   kind: "movies", bgColor: "0x0D1F38FF"},
        {title: "TV Shows", kind: "shows",  bgColor: "0x1A0D38FF"}
    ]

    i = 0
    for each cat in categories
        tile = CreateObject("roSGNode", "CategoryTile")
        tile.translation = [i * 360, 0]

        cn = CreateObject("roSGNode", "ContentNode")
        cn.title = cat.title
        cn.addFields({kind: cat.kind, bgColor: cat.bgColor})

        posterUrl = ""
        if cat.kind = "movies" and m.recentMovies <> invalid and m.recentMovies.count() > 0
            firstItem = m.recentMovies[0]
            if firstItem.poster_url <> invalid
                posterUrl = ResolveUrl(m.serverUrl, firstItem.poster_url)
            end if
        else if cat.kind = "shows" and m.recentShows <> invalid and m.recentShows.count() > 0
            firstItem = m.recentShows[0]
            if firstItem.poster_url <> invalid
                posterUrl = ResolveUrl(m.serverUrl, firstItem.poster_url)
            end if
        end if
        cn.hdPosterUrl = posterUrl

        tile.itemContent  = cn
        tile.focusPercent = 0.0
        m.categoryRowGroup.appendChild(tile)
        i = i + 1
    end for
end sub

sub populateRowGroup(rowGroup as object, items as object, componentName as string, isCW as boolean)
    while rowGroup.getChildCount() > 0
        rowGroup.removeChildIndex(0)
    end while
    if items = invalid then return

    stride = 218
    if componentName = "WideItem" then stride = 316

    maxItems = 20
    i = 0
    for each media in items
        if i >= maxItems then exit for
        item = CreateObject("roSGNode", componentName)
        item.translation = [i * stride, 0]
        if isCW
            item.itemContent = makeCWNode(media)
        else
            item.itemContent = createMediaNode(media)
        end if
        item.focusPercent = 0.0
        rowGroup.appendChild(item)
        i = i + 1
    end for
end sub

function makeCWNode(cw as object) as object
    item = CreateObject("roSGNode", "ContentNode")
    item.title = cw.title
    posterUrl = ""
    if cw.poster_url <> invalid then posterUrl = ResolveUrl(m.serverUrl, cw.poster_url)
    item.hdPosterUrl = posterUrl

    pct = 0
    pp = cw.progress_pct
    if pp <> invalid then pct = pp

    epLabel = ""
    sn = cw.season_number
    en = cw.episode_number
    if sn <> invalid and en <> invalid then
        epLabel = "S" + sn.ToStr() + " E" + en.ToStr()
    else if en <> invalid then
        epLabel = "E" + en.ToStr()
    end if

    item.addFields({
        mediaId:      cw.media_id
        kind:         cw.kind
        showId:       cw.show_id
        progressPct:  pct
        episodeLabel: epLabel
    })
    item.addFields({position: cw.position_seconds})
    durSec = 0.0
    if cw.duration_seconds <> invalid then durSec = cw.duration_seconds
    item.addFields({durationSeconds: durSec})
    return item
end function

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

sub updateRowLabels()
    if m.homeRowLabels = invalid then return
    for i = 0 to m.numHomeRows - 1
        if i = m.activeHomeRow
            m.homeRowLabels[i].color = "0xFFFFFFFF"
        else
            m.homeRowLabels[i].color = "0x888888FF"
        end if
    end for
end sub

' -------------------------------------------------------
' Home row focus helpers
' -------------------------------------------------------

sub setHomeItemFocus(rowIdx as integer, itemIdx as integer)
    if m.homeRowGroups = invalid then return
    if rowIdx >= m.homeRowGroups.count() then return
    oldPoster = m.homeRowGroups[rowIdx].getChild(m.rowFocusIdx[rowIdx])
    if oldPoster <> invalid then oldPoster.focusPercent = 0.0
    m.rowFocusIdx[rowIdx] = itemIdx
    newPoster = m.homeRowGroups[rowIdx].getChild(itemIdx)
    if newPoster <> invalid then newPoster.focusPercent = 1.0
    scrollHomeRow(rowIdx)
end sub

sub activateHomeRow(rowIdx as integer)
    if m.homeRowGroups = invalid then return
    oldPoster = m.homeRowGroups[m.activeHomeRow].getChild(m.rowFocusIdx[m.activeHomeRow])
    if oldPoster <> invalid then oldPoster.focusPercent = 0.0
    m.activeHomeRow = rowIdx
    newPoster = m.homeRowGroups[rowIdx].getChild(m.rowFocusIdx[rowIdx])
    if newPoster <> invalid then newPoster.focusPercent = 1.0
    updateRowLabels()
    scrollHomeToRow(rowIdx)
end sub

sub scrollHomeToRow(rowIdx as integer)
    if m.homeRowLabels = invalid then return
    SCREEN_TOP    = 120   ' just below the tab bar
    SCREEN_BOTTOM = 1040  ' just above the hint label

    rowLabel = m.homeRowLabels[rowIdx]
    rowGroup = m.homeRowGroups[rowIdx]
    labelY   = rowLabel.translation[1]
    rowBot   = rowGroup.translation[1] + 270 + 30   ' PosterItem height + buffer

    ' Scroll up if the row bottom would be off the bottom of the screen
    if rowBot + m.homeScrollY > SCREEN_BOTTOM
        m.homeScrollY = SCREEN_BOTTOM - rowBot
    end if
    ' Scroll back down if the label would be above the visible area
    if labelY + m.homeScrollY < SCREEN_TOP
        m.homeScrollY = SCREEN_TOP - labelY
    end if
    ' Never scroll past the natural top position
    if m.homeScrollY > 0 then m.homeScrollY = 0

    m.homeView.translation = [0, m.homeScrollY]
end sub

sub clearHomeAllFocus()
    if m.homeRowGroups = invalid then return
    for i = 0 to m.numHomeRows - 1
        poster = m.homeRowGroups[i].getChild(m.rowFocusIdx[i])
        if poster <> invalid then poster.focusPercent = 0.0
    end for
end sub

sub scrollHomeRow(rowIdx as integer)
    if m.homeRowGroups = invalid then return
    itemIdx = m.rowFocusIdx[rowIdx]
    stride  = m.homeRowStride[rowIdx]
    itemW   = m.homeRowWidth[rowIdx]

    itemScreenX = m.rowScrollX[rowIdx] + itemIdx * stride

    if itemScreenX < 40
        m.rowScrollX[rowIdx] = 40 - itemIdx * stride
    else if itemScreenX + itemW > 1880
        m.rowScrollX[rowIdx] = 1880 - itemW - itemIdx * stride
    end if

    curTrans = m.homeRowGroups[rowIdx].translation
    m.homeRowGroups[rowIdx].translation = [m.rowScrollX[rowIdx], curTrans[1]]
end sub

' -------------------------------------------------------
' Custom grid builders (Movies / Shows tabs)
' -------------------------------------------------------

sub buildMovieGrid()
    if m.movieGridBuilt then return
    if m.movieItems = invalid then return
    m.movieRowGroups = []
    m.movieRowItems  = []
    buildCustomGrid(m.movieGrid, m.movieItems, m.movieRowGroups, m.movieRowItems)
    m.movieGridBuilt = true
    m.loadingLabel.visible = false
end sub

sub buildShowGrid()
    if m.showGridBuilt then return
    if m.showItems = invalid then return
    m.showRowGroups = []
    m.showRowItems  = []
    buildCustomGrid(m.showGrid, m.showItems, m.showRowGroups, m.showRowItems)
    m.showGridBuilt = true
    m.loadingLabel.visible = false
end sub

sub buildCustomGrid(container as object, items as object, rowGroups as object, rowItems as object)
    while container.getChildCount() > 0
        container.removeChildIndex(0)
    end while
    maxItems   = 100
    numCols    = m.numGridCols
    i          = 0
    rowIdx     = 0
    curGroup   = invalid
    curRowList = invalid
    for each media in items
        if i >= maxItems then exit for
        if i mod numCols = 0
            curGroup             = CreateObject("roSGNode", "Group")
            curGroup.translation = [0, rowIdx * m.gridStrideY]
            isVisible            = (rowIdx < 3)
            curGroup.visible     = isVisible
            curGroup.addFields({postersLoaded: isVisible})
            curRowList           = []
            container.appendChild(curGroup)
            rowGroups.push(curGroup)
            rowItems.push(curRowList)
            rowIdx = rowIdx + 1
        end if
        tile             = CreateObject("roSGNode", "PosterItem")
        tile.translation = [(i mod numCols) * m.gridStrideX, 0]
        tile.focusPercent = 0.0
        curGroup.appendChild(tile)
        curRowList.push(media)
        ' Only fire poster requests for the 3 initially-visible rows
        if (rowIdx - 1) < 3
            tile.itemContent = createMediaNode(media)
        end if
        i = i + 1
    end for
end sub

function activeGridRowGroups() as object
    if m.activeIdx = 1 then return m.movieRowGroups
    return m.showRowGroups
end function

function activeGridRowItems() as object
    if m.activeIdx = 1 then return m.movieRowItems
    return m.showRowItems
end function

sub setGridItemFocus(row as integer, col as integer, pct as float)
    rows = activeGridRowGroups()
    if row < 0 or row >= rows.count() then return
    rg = rows[row]
    if rg = invalid then return
    tile = rg.getChild(col)
    if tile <> invalid then tile.focusPercent = pct
end sub

sub scrollGrid(newTop as integer)
    rows        = activeGridRowGroups()
    rowItemsArr = activeGridRowItems()
    if rows.count() = 0 then return
    m.gridScrollTop = newTop
    for i = 0 to rows.count() - 1
        rg = rows[i]
        if rg = invalid then
        else
            displayRow = i - newTop
            if displayRow >= 0 and displayRow < 3
                rg.visible     = true
                rg.translation = [0, displayRow * m.gridStrideY]
                ' Lazy-load poster images the first time a row scrolls into view
                if not rg.postersLoaded and rowItemsArr <> invalid and i < rowItemsArr.count()
                    rowMediaList = rowItemsArr[i]
                    for j = 0 to rg.getChildCount() - 1
                        tile = rg.getChild(j)
                        if tile <> invalid and j < rowMediaList.count()
                            tile.itemContent = createMediaNode(rowMediaList[j])
                        end if
                    end for
                    rg.postersLoaded = true
                end if
            else
                rg.visible = false
            end if
        end if
    end for
end sub

sub navigateToItem(item as object)
    kind    = item.kind
    mediaId = item.mediaId

    if kind = "movie"
        nav = {action: "details", mediaId: mediaId, title: item.title, kind: kind, posterUrl: item.hdPosterUrl, overview: item.overview, year: item.year}
        m.top.navRequest = nav
    else if kind = "episode"
        posSec = 0.0
        if item["position"] <> invalid then posSec = item["position"]
        durSec = 0.0
        if item.durationSeconds <> invalid then durSec = item.durationSeconds
        hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)
        nav = {action: "play", mediaId: mediaId, title: item.title, url: hlsUrl, durationSeconds: durSec}
        nav["position"] = posSec
        m.top.navRequest = nav
    else if kind = "show"
        nav = {action: "details", mediaId: mediaId, title: item.title, kind: kind, posterUrl: item.hdPosterUrl, overview: item.overview, year: item.year}
        m.top.navRequest = nav
    end if
end sub

' -------------------------------------------------------
' Settings helpers
' -------------------------------------------------------

sub loadSettingsInfo()
    if m.sItem = invalid or m.sItem.count() = 0 then return
    m.sValue[0].text  = m.serverUrl
    m.sStatus0.text   = "● Checking…"
    m.sStatus0.color  = "0x888888FF"
    di = CreateObject("roDeviceInfo")
    m.sAboutDevice.text = di.GetModelDisplayName()
    m.sValue[3].text  = m.subtitleOptions[m.subtitleIdx]
    m.sValue[4].text  = m.qualityOptions[m.qualityIdx]
    pingServer()
end sub

sub pingServer()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/movies?limit=1"
    task.token = m.token
    task.observeField("resultArr", "onPingSuccess")
    task.observeField("apiError",  "onPingError")
    task.control = "run"
    m.pingTask = task
end sub

sub onPingSuccess(event as object)
    m.sStatus0.text  = "● Connected"
    m.sStatus0.color = "0x4FD070FF"
end sub

sub onPingError(event as object)
    err = event.getData()
    if err = "Unauthorized" or Left(err, 5) = "HTTP "
        m.sStatus0.text  = "● Connected"
        m.sStatus0.color = "0x4FD070FF"
    else
        m.sStatus0.text  = "● Unreachable"
        m.sStatus0.color = "0xFF6666FF"
    end if
end sub

sub updateSettingsFocus()
    BG_NORMAL  = "0x0E0E28FF"
    BG_FOCUSED = "0x152840FF"
    for i = 0 to m.settNumItems - 1
        if m.inContent and i = m.settFocusIdx
            m.sItem[i].color     = BG_FOCUSED
            m.sAccent[i].opacity = 1.0
        else
            m.sItem[i].color     = BG_NORMAL
            m.sAccent[i].opacity = 0.0
        end if
    end for
end sub

sub activateSettingsItem()
    idx = m.settFocusIdx
    if idx = 1 or idx = 2
        m.top.navRequest = {action: "signout"}
    else if idx = 3
        m.subtitleIdx = (m.subtitleIdx + 1) mod m.subtitleOptions.count()
        SetReg("subtitle_pref", m.subtitleOptions[m.subtitleIdx])
        m.sValue[3].text = m.subtitleOptions[m.subtitleIdx]
    else if idx = 4
        m.qualityIdx = (m.qualityIdx + 1) mod m.qualityOptions.count()
        SetReg("quality_pref", m.qualityOptions[m.qualityIdx])
        m.sValue[4].text = m.qualityOptions[m.qualityIdx]
    end if
end sub

' -------------------------------------------------------
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "options"
        m.top.navRequest = {action: "signout"}
        return true
    end if

    ' ── Settings item navigation ─────────────────────────
    if m.activeIdx = 3 and m.inContent
        if key = "back"
            m.inContent          = false
            m.gridHint.visible   = false
            m.headerHint.visible = true
            updateSettingsFocus()
            m.top.setFocus(true)
            return true
        end if
        if key = "up"
            if m.settFocusIdx > 0
                m.settFocusIdx = m.settFocusIdx - 1
                updateSettingsFocus()
            else
                m.inContent          = false
                m.gridHint.visible   = false
                m.headerHint.visible = true
                updateSettingsFocus()
                m.top.setFocus(true)
            end if
            return true
        end if
        if key = "down"
            if m.settFocusIdx < m.settNumItems - 1
                m.settFocusIdx = m.settFocusIdx + 1
                updateSettingsFocus()
            end if
            return true
        end if
        if key = "OK"
            activateSettingsItem()
            return true
        end if
        return true
    end if

    ' ── Home tab row navigation ──────────────────────────
    if m.activeIdx = 0 and m.inContent
        if key = "back"
            clearHomeAllFocus()
            m.inContent          = false
            m.gridHint.visible   = false
            m.headerHint.visible = true
            m.top.setFocus(true)
            return true
        end if

        if key = "up"
            if m.activeHomeRow > 0
                activateHomeRow(m.activeHomeRow - 1)
            else
                ' Top of rows — return to tab bar
                clearHomeAllFocus()
                m.inContent          = false
                m.gridHint.visible   = false
                m.headerHint.visible = true
                m.top.setFocus(true)
            end if
            return true
        end if

        if key = "down"
            if m.activeHomeRow < m.numHomeRows - 1 then activateHomeRow(m.activeHomeRow + 1)
            return true
        end if

        if key = "left"
            idx = m.rowFocusIdx[m.activeHomeRow]
            if idx > 0 then setHomeItemFocus(m.activeHomeRow, idx - 1)
            return true
        end if

        if key = "right"
            idx    = m.rowFocusIdx[m.activeHomeRow]
            maxIdx = m.homeRowGroups[m.activeHomeRow].getChildCount() - 1
            if idx < maxIdx then setHomeItemFocus(m.activeHomeRow, idx + 1)
            return true
        end if

        if key = "OK"
            rIdx    = m.activeHomeRow
            rowType = m.homeRowTypes[rIdx]
            if rowType = "category"
                idx = m.rowFocusIdx[rIdx]
                clearHomeAllFocus()
                m.inContent          = false
                m.gridHint.visible   = false
                m.headerHint.visible = true
                if idx = 0
                    m.activeIdx = 1
                    buildMovieGrid()
                else if idx = 1
                    m.activeIdx = 2
                    buildShowGrid()
                end if
                updateTabs()
            else
                rowGroup = m.homeRowGroups[rIdx]
                item     = rowGroup.getChild(m.rowFocusIdx[rIdx])
                if item <> invalid and item.itemContent <> invalid
                    navigateToItem(item.itemContent)
                end if
            end if
            return true
        end if

        return true
    end if

    ' ── Custom grid navigation (Movies / Shows tabs) ─────────────────
    if (m.activeIdx = 1 or m.activeIdx = 2) and m.inContent
        rows = activeGridRowGroups()

        if key = "up"
            if m.gridFocusRow > 0
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 0.0)
                m.gridFocusRow = m.gridFocusRow - 1
                maxCol = rows[m.gridFocusRow].getChildCount() - 1
                if m.gridFocusCol > maxCol then m.gridFocusCol = maxCol
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 1.0)
                if m.gridFocusRow < m.gridScrollTop then scrollGrid(m.gridFocusRow)
            else
                setGridItemFocus(0, m.gridFocusCol, 0.0)
                m.inContent          = false
                m.headerHint.visible = true
                m.gridHint.visible   = false
            end if
            return true
        end if

        if key = "down"
            if m.gridFocusRow < rows.count() - 1
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 0.0)
                m.gridFocusRow = m.gridFocusRow + 1
                maxCol = rows[m.gridFocusRow].getChildCount() - 1
                if m.gridFocusCol > maxCol then m.gridFocusCol = maxCol
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 1.0)
                if m.gridFocusRow >= m.gridScrollTop + 3 then scrollGrid(m.gridScrollTop + 1)
            end if
            return true
        end if

        if key = "left"
            if m.gridFocusCol > 0
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 0.0)
                m.gridFocusCol = m.gridFocusCol - 1
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 1.0)
            end if
            return true
        end if

        if key = "right"
            maxCol = rows[m.gridFocusRow].getChildCount() - 1
            if m.gridFocusCol < maxCol
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 0.0)
                m.gridFocusCol = m.gridFocusCol + 1
                setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 1.0)
            end if
            return true
        end if

        if key = "OK"
            rg = rows[m.gridFocusRow]
            if rg <> invalid
                tile = rg.getChild(m.gridFocusCol)
                if tile <> invalid and tile.itemContent <> invalid
                    navigateToItem(tile.itemContent)
                end if
            end if
            return true
        end if

        if key = "back"
            setGridItemFocus(m.gridFocusRow, m.gridFocusCol, 0.0)
            m.inContent          = false
            m.headerHint.visible = true
            m.gridHint.visible   = false
            return true
        end if

        return true
    end if

    ' ── Tab bar navigation ───────────────────────────────
    if not m.inContent
        if key = "back" then return true

        if key = "left"
            if m.activeIdx > 0
                m.activeIdx = m.activeIdx - 1
                updateTabs()
            end if
            return true
        end if

        if key = "right"
            if m.activeIdx < 4
                m.activeIdx = m.activeIdx + 1
                updateTabs()
                if m.activeIdx = 1 then buildMovieGrid()
                if m.activeIdx = 2 then buildShowGrid()
            end if
            return true
        end if

        if key = "down" or key = "OK"
            if m.activeIdx = 4
                m.top.navRequest = {action: "search"}
                return true
            end if
            if m.activeIdx = 3
                m.inContent          = true
                m.settFocusIdx       = 0
                m.headerHint.visible = false
                m.gridHint.visible   = true
                updateSettingsFocus()
                return true
            end if
            if m.activeIdx = 0
                buildHomeRows()
                if m.numHomeRows > 0
                    m.inContent          = true
                    m.headerHint.visible = false
                    m.gridHint.visible   = true
                    m.activeHomeRow      = 0
                    setHomeItemFocus(0, m.rowFocusIdx[0])
                end if
            else
                if m.activeIdx = 1 then buildMovieGrid()
                if m.activeIdx = 2 then buildShowGrid()
                m.inContent          = true
                m.headerHint.visible = false
                m.gridHint.visible   = true
                m.gridFocusRow  = 0
                m.gridFocusCol  = 0
                m.gridScrollTop = 0
                scrollGrid(0)
                setGridItemFocus(0, 0, 1.0)
            end if
            return true
        end if

        return true
    end if

    ' ── Back from flat grid ───────────────────────────────
    if key = "back"
        m.inContent          = false
        m.gridHint.visible   = false
        m.headerHint.visible = true
        m.top.setFocus(true)
        return true
    end if

    return false
end function
