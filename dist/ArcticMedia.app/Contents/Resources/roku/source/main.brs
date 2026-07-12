sub Main(args as Object)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    ' ECP deep-link (cast from iOS)
    if args.DoesExist("contentId") and args.DoesExist("MediaType")
        scene.launchContent = {
            contentId: args.contentId
            mediaType: args.MediaType
        }
    end if

    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        end if
    end while
end sub
