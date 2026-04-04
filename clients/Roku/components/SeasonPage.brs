sub init()
    m.showTitle   = m.top.findNode("showTitle")
    m.seasonList  = m.top.findNode("seasonList")
    m.episodeList = m.top.findNode("episodeList")
    m.backdrop    = m.top.findNode("backdrop")
    m.epThumb     = m.top.findNode("epThumb")
    m.epTitle     = m.top.findNode("epTitle")
    m.epInfo      = m.top.findNode("epInfo")
    m.epOverview  = m.top.findNode("epOverview")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.seasons          = []
    m.episodes         = []
    m.posterUri        = ""
    m.currentSeasonNum = 1
    m.focusOnEpisodes  = false

    ' Seasons: auto-load episodes as user navigates through seasons
    m.seasonList.observeField("itemFocused",  "onSeasonFocused")
    m.seasonList.observeField("itemSelected", "onSeasonFocused")

    ' Episodes: update preview on navigation, play on OK
    m.episodeList.observeField("itemFocused",  "onEpisodeFocused")
    m.episodeList.observeField("itemSelected", "onEpisodeSelected")

    m.top.observeField("params", "onParams")
    m.top.setFocus(true)
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
        m.epThumb.uri  = p.posterUrl
    end if

    loadSeasons()
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
    if data = invalid then return
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

    if m.seasons.count() > 0
        sNum = m.seasons[0].season_number
        if sNum = invalid then sNum = 1
        m.currentSeasonNum = sNum
        loadEpisodes(m.seasons[0].id)
    end if
end sub

sub onSeasonFocused(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.seasons.count() then return
    sNum = m.seasons[idx].season_number
    if sNum = invalid then sNum = idx + 1
    m.currentSeasonNum = sNum
    loadEpisodes(m.seasons[idx].id)
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
    data = event.getData()
    if data = invalid then return
    m.episodes = data

    content = CreateObject("roSGNode", "ContentNode")
    for each ep in m.episodes
        item = CreateObject("roSGNode", "ContentNode")
        epNum = ep.episode_number
        if epNum = invalid then epNum = 0
        numStr = epNum.ToStr()
        item.title = "E" + numStr + "  " + ep.title
        item.addFields({mediaId: ep.id, epTitle: ep.title, epNum: epNum})
        content.appendChild(item)
    end for
    m.episodeList.content = content

    ' Show preview for first episode
    if m.episodes.count() > 0 then updateEpisodePanel(m.episodes[0], 0)
end sub

' -------------------------------------------------------
' Episode preview panel
' -------------------------------------------------------

sub onEpisodeFocused(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.episodes.count() then return
    updateEpisodePanel(m.episodes[idx], idx)
end sub

sub updateEpisodePanel(ep as object, listIdx as integer)
    if ep = invalid then return

    ' Thumbnail: prefer 16:9 backdrop_url, then poster_url, then show poster
    thumb = m.posterUri
    if ep.backdrop_url <> invalid and ep.backdrop_url <> ""
        thumb = ResolveUrl(m.serverUrl, ep.backdrop_url)
    else if ep.poster_url <> invalid and ep.poster_url <> ""
        thumb = ResolveUrl(m.serverUrl, ep.poster_url)
    end if
    m.epThumb.uri = thumb

    ' Episode title
    m.epTitle.text = ep.title

    ' Info line: S1 · E3 · 2024
    epNum = ep.episode_number
    if epNum = invalid then epNum = listIdx + 1
    info = "S" + m.currentSeasonNum.ToStr() + "  ·  E" + epNum.ToStr()
    airYear = ""
    if ep.release_date <> invalid and Len(ep.release_date) >= 4
        airYear = Left(ep.release_date, 4)
    end if
    if airYear <> "" then info = info + "  ·  " + airYear
    m.epInfo.text = info

    ' Overview
    ov = ""
    if ep.overview <> invalid then ov = ep.overview
    m.epOverview.text = ov
end sub

sub onEpisodeSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.episodes.count() then return

    ep = m.episodes[idx]
    mediaId = ep.id
    hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)

    m.top.navRequest = {
        action:      "play"
        mediaId:     mediaId
        title:       ep.title
        url:         hlsUrl
        position:    0.0
        episodeList: m.episodes
        episodeIdx:  idx
    }
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
        m.episodeList.setFocus(true)
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
