import SwiftUI
import AVFoundation

struct VideoPlayerView: View {
    let url: URL
    let title: String
    let mediaId: Int
    let serverURL: String
    let token: String
    var startAt: Double? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var availableDuration: Double = 0
    @State private var showControls = true
    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var timeObserverToken: Any?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var hideTask: Task<Void, Never>?
    @State private var progressTickCounter = 0
    @State private var tornDown = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoSurface(player: player).ignoresSafeArea()
            }

            if isLoading {
                VStack(spacing: 14) {
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Text("Loading…").font(.footnote).foregroundColor(.white.opacity(0.55))
                }
            }

            if let msg = errorMessage {
                errorOverlay(msg)
            }

            if showControls && !isLoading && errorMessage == nil {
                controlsOverlay
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .ignoresSafeArea()          // ZStack fills the full screen
        .preferredColorScheme(.dark)
        .onTapGesture { toggleControls() }
        .task { await setup() }
        .onDisappear { teardown() }
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {

            // Top: close + title
            HStack(spacing: 0) {
                Button { teardown(); dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)

            Spacer()

            // Center: skip / play / skip
            HStack(spacing: 56) {
                skipButton(seconds: -15, icon: "gobackward.15")
                playPauseButton
                skipButton(seconds: 15, icon: "goforward.15")
            }

            Spacer()

            // Bottom: seek bar + time labels
            VStack(spacing: 6) {
                seekBar
                timeRow
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 4)
        .safeAreaPadding()          // keeps all controls clear of Dynamic Island + home bar
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            VStack {
                // Top gradient bleeds into status bar
                LinearGradient(colors: [.black.opacity(0.75), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .ignoresSafeArea(edges: .top)
                Spacer()
                // Bottom gradient bleeds past home indicator
                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Control buttons

    private var playPauseButton: some View {
        Button { togglePlayPause() } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 72, height: 72)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
    }

    private func skipButton(seconds: Double, icon: String) -> some View {
        Button { skip(seconds) } label: {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
        }
    }

    // MARK: - Seek bar

    private var seekBar: some View {
        GeometryReader { geo in
            let w       = geo.size.width
            let filled  = w * progressFraction
            let encoded = duration > 0 ? w * min(1, availableDuration / duration) : filled
            let thumb: CGFloat = isDragging ? 20 : 14

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
                Capsule().fill(Color.arcticPrimary.opacity(0.4)).frame(width: max(0, encoded), height: 4)
                Capsule().fill(Color.arcticPrimary).frame(width: max(0, filled), height: 4)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .frame(width: thumb, height: thumb)
                    .offset(x: max(0, filled - thumb / 2))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: w))
        }
        .frame(height: 28)
    }

    private var progressFraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, (isDragging ? dragTime : currentTime) / duration)))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                isDragging = true
                hideTask?.cancel()
                dragTime = max(0, min(1, v.location.x / width)) * max(duration, 1)
            }
            .onEnded { v in
                let requested = max(0, min(1, v.location.x / width)) * max(duration, 1)
                let target    = min(requested, maxSeekable)
                player?.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                             toleranceBefore: .zero,
                             toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
                currentTime  = target
                isDragging   = false
                scheduleHide()
            }
    }

    private var timeRow: some View {
        HStack {
            Text(formatTime(isDragging ? dragTime : currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text(duration > 0 ? formatTime(duration) : "–:––")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Setup / teardown

    private func setup() async {
        if let info = try? await APIService.shared.streamInfo(
            serverURL: serverURL, token: token, mediaId: mediaId),
           let d = info.duration, d > 0 {
            await MainActor.run { duration = d; availableDuration = d }
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p    = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true

        await MainActor.run { player = p; isLoading = false }
        UIApplication.shared.isIdleTimerDisabled = true

        let tok = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [self] time in
            if !isDragging { currentTime = time.seconds }
            availableDuration = maxSeekable
            // Save progress every ~10 s (20 ticks × 0.5 s)
            progressTickCounter += 1
            if progressTickCounter >= 20 {
                progressTickCounter = 0
                let pos = time.seconds
                let dur = duration
                if pos > 0 && dur > 0 {
                    Task {
                        await APIService.shared.updateProgress(
                            serverURL: serverURL, token: token,
                            mediaId: mediaId, position: pos, duration: dur)
                    }
                }
            }
        }
        await MainActor.run { timeObserverToken = tok }

        let obs = item.observe(\.status, options: [.initial, .new]) { i, _ in
            switch i.status {
            case .readyToPlay:
                if self.duration == 0, i.duration.isNumeric, i.duration.seconds > 0 {
                    Task { @MainActor in self.duration = i.duration.seconds }
                }
                let seekTo = self.startAt.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
                p.seek(to: seekTo, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { _ in
                    p.play()
                    Task { @MainActor in self.isPlaying = true }
                }
            case .failed:
                Task { @MainActor in
                    self.errorMessage = i.error?.localizedDescription ?? "Unknown playback error"
                    self.isLoading = false
                }
            default: break
            }
        }
        await MainActor.run { statusObserver = obs }

        scheduleHide()
        try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
        obs.invalidate()
    }

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        hideTask?.cancel()
        statusObserver?.invalidate()
        statusObserver = nil
        if let tok = timeObserverToken {
            player?.removeTimeObserver(tok)
            timeObserverToken = nil
        }
        // Final progress save
        let pos = currentTime; let dur = duration
        if pos > 0 && dur > 0 {
            Task {
                await APIService.shared.updateProgress(
                    serverURL: serverURL, token: token,
                    mediaId: mediaId, position: pos, duration: dur)
            }
        }
        player?.pause()
        player = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private var maxSeekable: Double {
        guard let item = player?.currentItem else { return duration }
        return item.seekableTimeRanges
            .compactMap { $0 as? CMTimeRange }
            .map { ($0.start + $0.duration).seconds }
            .max() ?? duration
    }

    private func toggleControls() {
        withAnimation { showControls.toggle() }
        if showControls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isDragging { withAnimation { showControls = false } }
            }
        }
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play() }
        isPlaying.toggle()
        scheduleHide()
    }

    private func skip(_ seconds: Double) {
        guard let p = player else { return }
        let target = max(0, min(maxSeekable, currentTime + seconds))
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        scheduleHide()
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s); let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    @ViewBuilder
    private func errorOverlay(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundColor(.yellow)
            Text("Playback Error").font(.headline).foregroundColor(.white)
            Text(msg).font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal)
            Button("Close") { teardown(); dismiss() }
                .padding(.horizontal, 32).padding(.vertical, 10)
                .background(Color.white.opacity(0.2)).foregroundColor(.white).clipShape(Capsule())
        }
    }
}

// MARK: - AVPlayerLayer surface

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView { PlayerLayerView(player: player) }
    func updateUIView(_ v: PlayerLayerView, context: Context) { v.player = player }
}

class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspect }
    }
    init(player: AVPlayer) { super.init(frame: .zero); self.player = player; backgroundColor = .black }
    required init?(coder: NSCoder) { fatalError() }
}
