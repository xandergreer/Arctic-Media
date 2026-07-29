sub init()
    m.showTitle   = m.top.findNode("showTitle")
    m.seasonInfo  = m.top.findNode("seasonInfo")
    m.seasonList  = m.top.findNode("seasonList")
    m.episodeGrid = m.top.findNode("episodeGrid")
    m.backdrop    = m.top.findNode("backdrop")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.seasons          = []
    m.episodes         = []
    m.histMap          = {}      ' media_id (string) -> {posSec, pct}
    m.posterUri        = ""
    m.currentSeasonNum = 1
    m.focusOnEpisodes  = false

    ' Seasons: auto-load episodes as user navigates through seasons;
    ' OK on a season jumps straight to its episode list
    m.seasonList.observeField("itemFocused",  "onSeasonFocused")
    m.seasonList.observeField("itemSelected", "onSeasonSelected")

    ' Episodes: backdrop follows focus, play on OK
    m.episodeGrid.observeField("itemFocused",  "onEpisodeFocused")
    m.episodeGrid.observeField("itemSelected", "onEpisodeSelected")

    m.top.observeField("params",       "onParams")
    m.top.observeField("restoreFocus", "onRestoreFocus")
    m.top.setFocus(true)
end sub

' Called by MainScene after popping back to this page — put focus back on the
' list the user was last using so up/down works immediately.
sub onRestoreFocus(event as object)
    if not event.getData() then return
    if m.focusOnEpisodes
        m.episodeGrid.setFocus(true)
    else
        m.seasonList.setFocus(true)
    end if
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return
    m.showId = p.showId
    if p.title <> invalid then m.showTitle.text = p.title

    ' Use show poster as backdrop and fallback thumbnail
    if p.posterUrl <> invalid and p.posterUrl <> ""
        m.posterUri    = p.posterUrl
        m.backdrop.uri = p.posterUrl
    end if

    loadSeasons()
    loadHistory()
end sub

' -------------------------------------------------------
' Watch history (per-episode progress bars + resume)
' -------------------------------------------------------

sub loadHistory()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/history"
    task.token = m.token
    task.observeField("resultArr", "onHistoryRows")
    task.control = "run"
    m.historyTask = task
end sub

sub onHistoryRows(event as object)
    rows = event.getData()
    if rows = invalid or rows.count() = 0 then return
    for each row in rows
        rowId = row.media_id
        if rowId <> invalid
            posSec = 0.0
            if row.position_seconds <> invalid then posSec = row.position_seconds
            pct = 0
            if row.progress_pct <> invalid
                pct = row.progress_pct
            else if row.duration_seconds <> invalid and row.duration_seconds > 0
                pct = Int(posSec / row.duration_seconds * 100)
            end if
            m.histMap[rowId.ToStr()] = {posSec: posSec, pct: pct}
        end if
    end for
    ' Cards may already be on screen — refresh their progress bars
    if m.episodes.count() > 0 then buildEpisodeContent(true)
end sub

' -------------------------------------------------------
' Season loading
' -------------------------------------------------------

sub loadSeasons()
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/shows/" + m.showId.ToStr() + "/seasons"
    task.token = m.token
    task.observeField("resultArr", "onSeasonsResult")
    task.control = "run"
    m.seasonsTask = task
end sub

sub onSeasonsResult(event as object)
    data = event.getData()
    if data = invalid or data.count() = 0 then return
    m.seasons = data

    content = CreateObject("roSGNode", "ContentNode")
    for each s in m.seasons
        item = CreateObject("roSGNode", "ContentNode")
        sNum = s.season_number
        if sNum = invalid then sNum = 0
        item.title = "Season " + sNum.ToStr()
        item.addFields({seasonId: s.id, seasonNum: sNum})
        content.appendChild(item)
    end for
    m.seasonList.content = content
    m.seasonList.setFocus(true)

    sNum = m.seasons[0].season_number
    if sNum = invalid then sNum = 1
    m.currentSeasonNum = sNum
    loadEpisodes(m.seasons[0].id)
end sub

sub onSeasonFocused(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.seasons.count() then return
    sNum = m.seasons[idx].season_number
    if sNum = invalid then sNum = idx + 1
    m.currentSeasonNum = sNum
    loadEpisodes(m.seasons[idx].id)
end sub

sub onSeasonSelected(event as object)
    if m.episodes.count() = 0 then return
    m.focusOnEpisodes = true
    m.episodeGrid.setFocus(true)
end sub

' -------------------------------------------------------
' Episode loading
' -------------------------------------------------------

sub loadEpisodes(seasonId as integer)
    m.currentSeasonId = seasonId
    task = CreateObject("roSGNode", "ApiTask")
    task.url   = m.serverUrl + "/api/v1/media/seasons/" + seasonId.ToStr() + "/episodes"
    task.token = m.token
    task.observeField("resultArr", "onEpisodesResult")
    task.control = "run"
    m.episodesTask = task
end sub

sub onEpisodesResult(event as object)
    ' Fast season scrolling fires overlapping fetches — only the latest task's
    ' response may populate the grid, or a slow older season wins the race.
    task = event.getRoSGNode()
    if m.episodesTask <> invalid and not task.isSameNode(m.episodesTask) then return
    data = event.getData()
    if data = invalid then return
    m.episodes = data
    buildEpisodeContent(false)

    info = "SEASON " + m.currentSeasonNum.ToStr()
    info = info + "  ·  " + m.episodes.count().ToStr() + " EPISODE"
    if m.episodes.count() <> 1 then info = info + "S"
    m.seasonInfo.text = info
end sub

' Build (or rebuild, when history arrives late) the episode card list.
sub buildEpisodeContent(keepFocus as boolean)
    prevIdx = 0
    if keepFocus then prevIdx = m.episodeGrid.itemFocused

    content = CreateObject("roSGNode", "ContentNode")
    idx = 0
    for each ep in m.episodes
        item = CreateObject("roSGNode", "ContentNode")

        epNum = ep.episode_number
        if epNum = invalid then epNum = idx + 1
        epTitle = ep.title
        if epTitle = invalid or epTitle = "" then epTitle = "Episode " + epNum.ToStr()
        item.title = epNum.ToStr() + ".  " + epTitle

        ' Thumbnail: prefer 16:9 backdrop_url, then poster_url, then show poster
        thumb = m.posterUri
        if ep.backdrop_url <> invalid and ep.backdrop_url <> ""
            thumb = ResolveUrl(m.serverUrl, ep.backdrop_url)
        else if ep.poster_url <> invalid and ep.poster_url <> ""
            thumb = ResolveUrl(m.serverUrl, ep.poster_url)
        end if

        ' Meta line: S1 · E3 · 2019 · 7 min
        meta = "S" + m.currentSeasonNum.ToStr() + "  ·  E" + epNum.ToStr()
        if ep.release_date <> invalid and Len(ep.release_date) >= 4
            meta = meta + "  ·  " + Left(ep.release_date, 4)
        end if
        if ep.duration_seconds <> invalid and ep.duration_seconds > 0
            mins = Int(ep.duration_seconds / 60)
            if mins > 0 then meta = meta + "  ·  " + mins.ToStr() + " min"
        end if

        ov = ""
        if ep.overview <> invalid then ov = ep.overview

        pct = 0
        if ep.id <> invalid
            h = m.histMap[ep.id.ToStr()]
            if h <> invalid then pct = h.pct
        end if

        item.addFields({thumbUri: thumb, metaText: meta, overview: ov, progressPct: pct})
        content.appendChild(item)
        idx = idx + 1
    end for
    m.episodeGrid.content = content

    if keepFocus and prevIdx > 0 and prevIdx < m.episodes.count()
        m.episodeGrid.jumpToItem = prevIdx
    end if
end sub

' -------------------------------------------------------
' Focus / selection
' -------------------------------------------------------

sub onEpisodeFocused(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.episodes.count() then return
    ep = m.episodes[idx]
    if ep = invalid then return
    ' Backdrop follows the focused episode when it has real artwork
    if ep.backdrop_url <> invalid and ep.backdrop_url <> ""
        m.backdrop.uri = ResolveUrl(m.serverUrl, ep.backdrop_url)
    end if
end sub

sub onEpisodeSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.episodes.count() then return

    ep = m.episodes[idx]
    mediaId = ep.id
    hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)

    durSec = 0.0
    if ep.duration_seconds <> invalid then durSec = ep.duration_seconds

    epNum = ep.episode_number
    if epNum = invalid then epNum = idx + 1
    epLabel = "S" + m.currentSeasonNum.ToStr() + " E" + epNum.ToStr()

    ' Resume partially-watched episodes; fully-watched ones restart from 0:00
    posSec = 0.0
    if mediaId <> invalid
        h = m.histMap[mediaId.ToStr()]
        if h <> invalid and h.pct < 95 then posSec = h.posSec
    end if

    nav = {
        action:          "play"
        mediaId:         mediaId
        title:           ep.title
        url:             hlsUrl
        durationSeconds: durSec
        episodeList:     m.episodes
        episodeIdx:      idx
        episodeLabel:    epLabel
    }
    nav["position"] = posSec
    m.top.navRequest = nav
end sub

' -------------------------------------------------------
' Key handling
' -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "back"
        m.top.navRequest = {action: "back"}
        return true
    end if

    if key = "right" and not m.focusOnEpisodes
        m.focusOnEpisodes = true
        m.episodeGrid.setFocus(true)
        return true
    end if

    if key = "left" and m.focusOnEpisodes
        m.focusOnEpisodes = false
        m.seasonList.setFocus(true)
        return true
    end if

    if key = "options"
        m.top.navRequest = {action: "signout"}
        return true
    end if

    return false
end function
