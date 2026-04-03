sub init()
    m.showTitle   = m.top.findNode("showTitle")
    m.seasonList  = m.top.findNode("seasonList")
    m.episodeList = m.top.findNode("episodeList")

    m.serverUrl = GetReg("server_url")
    m.token     = GetReg("access_token")

    m.seasons  = []
    m.episodes = []
    m.focusOnEpisodes = false

    m.seasonList.observeField("itemSelected",  "onSeasonSelected")
    m.episodeList.observeField("itemSelected", "onEpisodeSelected")

    m.top.observeField("params", "onParams")
    m.top.setFocus(true)
end sub

sub onParams(event as object)
    p = event.getData()
    if p = invalid then return
    m.showId = p.showId
    if p.title <> invalid then m.showTitle.text = p.title
    loadSeasons()
end sub

' -------------------------------------------------------
' Load seasons
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
        item.addFields({seasonId: s.id})
        content.appendChild(item)
    end for
    m.seasonList.content = content
    m.seasonList.setFocus(true)

    ' Auto-load first season
    if m.seasons.count() > 0
        loadEpisodes(m.seasons[0].id)
    end if
end sub

sub onSeasonSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.seasons.count() then return
    loadEpisodes(m.seasons[idx].id)
end sub

' -------------------------------------------------------
' Load episodes
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
        label = "E" + epNum.ToStr() + "  " + ep.title
        item.title = label
        item.addFields({mediaId: ep.id, title: ep.title})
        content.appendChild(item)
    end for
    m.episodeList.content = content
end sub

sub onEpisodeSelected(event as object)
    idx = event.getData()
    if idx < 0 or idx >= m.episodes.count() then return

    ep = m.episodes[idx]
    mediaId = ep.id
    hlsUrl = BuildHlsUrl(m.serverUrl, m.token, mediaId)

    m.top.navRequest = {
        action:   "play"
        mediaId:  mediaId
        title:    ep.title
        url:      hlsUrl
        position: 0.0
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

    return false
end function
