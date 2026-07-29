sub Main(args as Object)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    ' roInput — handle input sent to an already-running channel
    ' (deep links / casting from the iOS app while open). Required for cert.
    m.input = CreateObject("roInput")
    m.input.SetMessagePort(m.port)

    ' Memory monitoring — get notified before we hit the per-app limit.
    m.memMon = CreateObject("roAppMemoryMonitor")
    m.memMon.SetMessagePort(m.port)
    m.memMon.EnableMemoryWarningEvent(true)
    usedPct   = m.memMon.GetMemoryLimitPercent()
    availKb   = m.memMon.GetChannelAvailableMemory()
    memLimits = m.memMon.GetChannelMemoryLimit()

    di = CreateObject("roDeviceInfo")
    di.SetMessagePort(m.port)
    di.EnableLowGeneralMemoryEvent(true)

    ' Deep-link at launch (cold start via ECP / iOS cast)
    applyLaunchArgs(scene, args)

    while true
        msg = wait(0, m.port)
        mt = type(msg)

        if mt = "roSGScreenEvent"
            if msg.isScreenClosed() then return

        else if mt = "roInputEvent"
            ' Warm deep link — channel already running
            if msg.IsInput()
                info = msg.GetInfo()
                if info <> invalid and info.DoesExist("contentId")
                    scene.launchContent = {
                        contentId: info.contentId
                        mediaType: info.mediaType
                    }
                end if
            end if

        else if mt = "roAppMemoryNotificationEvent"
            ' Approaching the memory ceiling — reclaim what we can.
            RunGarbageCollector()

        else if mt = "roDeviceInfoEvent"
            info = msg.GetInfo()
            if info <> invalid and info.DoesExist("lowGeneralMemory")
                RunGarbageCollector()
            end if
        end if
    end while
end sub

' Normalize cold-start launch args and hand them to the scene as a deep link.
sub applyLaunchArgs(scene as object, args as object)
    contentId = invalid
    if args.DoesExist("contentId") then contentId = args.contentId

    mediaType = "movie"
    if args.DoesExist("mediaType")
        mediaType = args.mediaType
    else if args.DoesExist("MediaType")
        mediaType = args.MediaType
    end if

    if contentId <> invalid
        scene.launchContent = {
            contentId: contentId
            mediaType: mediaType
        }
    end if
end sub
