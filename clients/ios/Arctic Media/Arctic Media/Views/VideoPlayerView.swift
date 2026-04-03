import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let url: URL
    let title: String
    let mediaId: Int
    let serverURL: String
    let token: String
    var startAt: Double? = nil
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tornDown = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserverToken: Any?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var endObserver: Any?
    @State private var progressTickCounter = 0

    @State private var offlineLoader: OfflinePlaybackHelper?
    @State private var subtitleTracks: [SubtitleTrack] = []
    @State private var selectedSubtitleIdx: Int? = nil
    @State private var showSubtitlePicker = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let player {
                    AVPlayerControllerRepresentable(player: player)
                }

                if isLoading && errorMessage == nil {
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Loading…").font(.footnote).foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let msg = errorMessage {
                    errorOverlay(msg)
                }

                // Overlay buttons — positioned using actual safe area insets
                if !isLoading && errorMessage == nil {
                    HStack(alignment: .center) {
                        Button {
                            teardown()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white, Color.black.opacity(0.5))
                                .shadow(radius: 4)
                        }

                        Spacer()

                        if !subtitleTracks.isEmpty {
                            Button { showSubtitlePicker = true } label: {
                                Image(systemName: "captions.bubble.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(
                                        selectedSubtitleIdx != nil ? Color.yellow : Color.white,
                                        Color.black.opacity(0.5)
                                    )
                                    .shadow(radius: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geo.safeAreaInsets.top + 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task { await setup() }
        .onDisappear { teardown() }
        .sheet(isPresented: $showSubtitlePicker) { subtitlePickerSheet }
    }

    // MARK: - Setup / teardown

    private func setup() async {
        // Fetch stream info: duration + subtitle tracks
        if let info = try? await APIService.shared.streamInfo(
            serverURL: serverURL, token: token, mediaId: mediaId) {
            if let d = info.duration, d > 0 {
                await MainActor.run { duration = d }
            }
            let tracks = info.subtitleTracks.filter { !$0.isImage }
            if !tracks.isEmpty {
                await MainActor.run { subtitleTracks = tracks }
            }
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true

        let item: AVPlayerItem
        if url.isFileURL {
            let loader = OfflinePlaybackHelper(mediaId: mediaId, localPlaylistURL: url)
            await MainActor.run { offlineLoader = loader }
            item = loader.makePlayerItem()
        } else {
            item = AVPlayerItem(url: url)
        }
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        await MainActor.run { player = p }

        // Save progress every ~10 s via periodic observer
        let tok = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [self] time in
            currentTime = time.seconds
            progressTickCounter += 1
            if progressTickCounter >= 20 {
                progressTickCounter = 0
                let pos = time.seconds
                let dur = duration
                if pos > 5 && dur > 0 {
                    Task {
                        await APIService.shared.updateProgress(
                            serverURL: serverURL, token: token,
                            mediaId: mediaId, position: pos, duration: dur)
                    }
                }
            }
        }
        await MainActor.run { timeObserverToken = tok }

        // Observe item status: seek to startAt when ready, then play
        let obs = item.observe(\.status, options: [.initial, .new]) { i, _ in
            switch i.status {
            case .readyToPlay:
                if self.duration == 0, i.duration.isNumeric, i.duration.seconds > 0 {
                    Task { @MainActor in self.duration = i.duration.seconds }
                }
                Task { @MainActor in self.isLoading = false }
                let seekTo = self.startAt.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
                p.seek(to: seekTo, toleranceBefore: .zero,
                       toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { _ in
                    p.play()
                }
            case .failed:
                Task { @MainActor in
                    self.errorMessage = i.error?.localizedDescription ?? "Playback error"
                    self.isLoading = false
                }
            default: break
            }
        }
        await MainActor.run { statusObserver = obs }

        // End-of-playback
        let eo = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [self] _ in
            guard !self.tornDown else { return }
            self.onFinished?()
            self.teardown()
            self.dismiss()
        }
        await MainActor.run { endObserver = eo }
    }

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        statusObserver?.invalidate()
        statusObserver = nil
        if let eo = endObserver {
            NotificationCenter.default.removeObserver(eo)
            endObserver = nil
        }
        if let tok = timeObserverToken {
            player?.removeTimeObserver(tok)
            timeObserverToken = nil
        }
        // Final progress save
        let pos = currentTime; let dur = duration
        if pos > 5 && dur > 0 {
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

    // MARK: - Subtitle reload

    private func reloadWithSubtitle(sidx: Int?) {
        let pos = currentTime
        var urlStr = "\(serverURL)/api/v1/stream/\(mediaId)/master.m3u8?token=\(token)"
        if let sidx { urlStr += "&sidx=\(sidx)&stype=text" }
        guard let newURL = URL(string: urlStr) else { return }

        statusObserver?.invalidate()
        statusObserver = nil
        if let eo = endObserver {
            NotificationCenter.default.removeObserver(eo)
            endObserver = nil
        }

        isLoading = true
        let newItem = AVPlayerItem(url: newURL)
        player?.replaceCurrentItem(with: newItem)

        let obs = newItem.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                self.isLoading = false
                if pos > 5 {
                    let t = CMTime(seconds: pos, preferredTimescale: 600)
                    self.player?.seek(to: t, toleranceBefore: .zero,
                                      toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { _ in
                        self.player?.play()
                    }
                } else {
                    self.player?.play()
                }
            }
        }
        statusObserver = obs

        let eo = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newItem, queue: .main
        ) { [self] _ in
            guard !self.tornDown else { return }
            self.onFinished?()
            self.teardown()
            self.dismiss()
        }
        endObserver = eo
    }

    // MARK: - Subtitle picker sheet

    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                Button {
                    selectedSubtitleIdx = nil
                    showSubtitlePicker = false
                    reloadWithSubtitle(sidx: nil)
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if selectedSubtitleIdx == nil {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)

                ForEach(subtitleTracks) { track in
                    Button {
                        selectedSubtitleIdx = track.index
                        showSubtitlePicker = false
                        reloadWithSubtitle(sidx: track.index)
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if selectedSubtitleIdx == track.index {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSubtitlePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Error overlay

    @ViewBuilder
    private func errorOverlay(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44)).foregroundColor(.yellow)
            Text("Playback Error").font(.headline).foregroundColor(.white)
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Close") { teardown(); dismiss() }
                .padding(.horizontal, 32).padding(.vertical, 10)
                .background(Color.white.opacity(0.2))
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AVPlayerViewController wrapper

private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
