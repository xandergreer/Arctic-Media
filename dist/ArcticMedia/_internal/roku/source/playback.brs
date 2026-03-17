sub PlayHls(url as string)
  video = CreateObject("roSGNode", "Video")
  video.content = {
    streamFormat: "hls"
    url: url
  }
  m.top.appendChild(video)
  video.control = "play"
end sub
