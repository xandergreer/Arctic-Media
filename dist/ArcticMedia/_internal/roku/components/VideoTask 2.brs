' ── VideoTask — roVideoScreen with native Roku OSD ───────────────────────
'
' Runs on a background Task thread.  Creates roVideoScreen so the user gets
' Roku's built-in OSD (seek bar, CC, trickplay) instead of a custom one.
' When the video ends the task sets done=true so MainScene can restore focus.
' Autoplay: if an episodeList is provided, sets nextIdx so MainScene can
' restart the task for the next episode.

sub init()
    m.top.functionName = "run"
end sub

sub run()
    mediaId    = m.top.mediaId
    title      = m.top.title
    hlsUrl     = m.top.hlsUrl
    startSec   = m.top.startSec
    episodes   = m.top.episodes
    episodeIdx = m.top.episodeIdx
    serverUrl  = GetReg("server_url")

    screen = CreateObject("roVideoScreen")
    port   = screen.GetMessagePort()

    content              = {}
    content.url          = hlsUrl
    content.title        = title
    content.streamFormat = "hls"
    if startSec > 0
        content.BookmarkPosition = Int(startSec) * 1000  ' ms
    end if

    ' Enable captions based on saved pref
    ccOn = (GetReg("subtitles") = "On")
    screen.ShowSubtitle(ccOn)

    screen.SetContent(content)
    screen.Show()

    lastSaveSec    = 0
    saveIntervalSec = 15

    while true
        msg = wait(0, port)
        if type(msg) = "roVideoScreenEvent"

            if msg.isPlaybackPosition()
                posSec = msg.GetIndex()
                if posSec - lastSaveSec >= saveIntervalSec
                    SaveProgress(mediaId, posSec, 0.0)
                    lastSaveSec = posSec
                end if

            else if msg.isFullResult()
                ' Video finished naturally → try autoplay
                SaveProgress(mediaId, msg.GetIndex(), 0.0)
                if episodes <> invalid and episodeIdx >= 0
                    nextIdx = episodeIdx + 1
                    if nextIdx < episodes.count()
                        m.top.nextIdx = nextIdx   ' signals MainScene to start next ep
                        return
                    end if
                end if
                m.top.done = true
                return

            else if msg.isPartialResult() or msg.isScreenClosed()
                ' User pressed Back or playback stopped partway
                SaveProgress(mediaId, msg.GetIndex(), 0.0)
                m.top.done = true
                return

            else if msg.isRequestFailed()
                m.top.done = true
                return

            end if
        end if
    end while
end sub
