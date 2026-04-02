import SwiftUI
import AVKit
import AVFoundation

// MARK: - Bare video surface (no native controls, no tap interception)

private struct PlayerLayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false   // we draw our own
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

// MARK: - Player view

struct VideoPlayerView: View {
    let mediaId: Int
    let streamURL: URL
    let title: String

    @EnvironmentObject private var api: APIService
    @StateObject private var coordinator = PlayerCoordinator()
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var progressTimer: Timer?

    // Subtitles
    @State private var subtitleTracks: [SubtitleTrack] = []
    @State private var selectedSubtitleIdx: Int? = nil
    @State private var showSubtitlePicker = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                PlayerLayer(player: coordinator.player)
                    .ignoresSafeArea()

                if showControls {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, geo.safeAreaInsets.top + 8)
                            .padding(.horizontal, 20)
                            .background(
                                LinearGradient(
                                    colors: [.black.opacity(0.7), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .ignoresSafeArea(edges: .top)
                            )

                        Spacer()

                        bottomBar
                            .padding(.bottom, geo.safeAreaInsets.bottom + 8)
                            .padding(.horizontal, 20)
                            .background(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.7)],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .ignoresSafeArea(edges: .bottom)
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSubtitlePicker) { subtitlePickerSheet }
        .onAppear {
            coordinator.load(url: streamURL)
            Task { await resumeProgress() }
            Task { await loadSubtitleTracks() }
            scheduleHideControls()
            startProgressTimer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            stopProgressTimer()
            coordinator.pause()
            let pos = coordinator.currentPosition
            let dur = coordinator.player.currentItem?.duration.seconds
            guard pos > 5 else { return }
            let validDur = (dur?.isFinite == true && dur! > 0) ? dur : nil
            // Detached so it survives view dismissal
            let service = api
            let id = mediaId
            Task.detached { @MainActor in
                try? await service.saveProgress(mediaId: id, position: pos, duration: validDur)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.pause()
                let pos = coordinator.currentPosition
                let dur = coordinator.player.currentItem?.duration.seconds
                let validDur = (dur?.isFinite == true && dur! > 0) ? dur : nil
                let service = api
                let id = mediaId
                Task.detached { @MainActor in
                    try? await service.saveProgress(mediaId: id, position: pos, duration: validDur)
                }
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            Button {
                coordinator.togglePlayback()
                resetHideTimer()
            } label: {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }

            Spacer()

            if !subtitleTracks.filter({ !$0.is_image }).isEmpty {
                Button {
                    showSubtitlePicker = true
                    resetHideTimer()
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.title2)
                        .foregroundStyle(selectedSubtitleIdx != nil ? .yellow : .white)
                        .shadow(radius: 3)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Subtitle picker sheet

    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                Button {
                    selectedSubtitleIdx = nil
                    reloadStream(sidx: nil)
                    showSubtitlePicker = false
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

                ForEach(subtitleTracks.filter { !$0.is_image }) { track in
                    Button {
                        selectedSubtitleIdx = track.index
                        reloadStream(sidx: track.index, stype: "text")
                        showSubtitlePicker = false
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

    // MARK: - Subtitle helpers

    private func loadSubtitleTracks() async {
        subtitleTracks = (try? await api.getStreamInfo(mediaId: mediaId))?.subtitle_tracks ?? []
    }

    private func reloadStream(sidx: Int?, stype: String = "text") {
        let pos = coordinator.currentPosition
        guard let newURL = api.streamURL(mediaId: mediaId, sidx: sidx, stype: stype, t: pos > 5 ? pos : nil) else { return }
        coordinator.load(url: newURL)
        if pos > 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let time = CMTime(seconds: pos, preferredTimescale: 600)
                coordinator.player.seek(to: time,
                                        toleranceBefore: CMTime(seconds: 2, preferredTimescale: 600),
                                        toleranceAfter:  CMTime(seconds: 2, preferredTimescale: 600)) { _ in
                    coordinator.play()
                }
            }
        } else {
            coordinator.play()
        }
    }

    // MARK: - Controls timer

    private func toggleControls() {
        showControls.toggle()
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            withAnimation { showControls = false }
        }
    }

    private func resetHideTimer() {
        if showControls { scheduleHideControls() }
    }

    // MARK: - Watch progress

    private func resumeProgress() async {
        if let progress = try? await api.getProgress(mediaId: mediaId),
           !progress.completed,
           progress.position_seconds > 5 {
            let time = CMTime(seconds: progress.position_seconds, preferredTimescale: 600)
            await coordinator.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        coordinator.play()
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            let pos = coordinator.currentPosition
            let dur = coordinator.player.currentItem?.duration.seconds
            guard pos > 5 else { return }
            let validDur = (dur?.isFinite == true && dur! > 0) ? dur : nil
            let service = api
            let id = mediaId
            Task { @MainActor in
                try? await service.saveProgress(mediaId: id, position: pos, duration: validDur)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Player coordinator

@MainActor
final class PlayerCoordinator: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false
    @Published private(set) var currentPosition: Double = 0

    private var timeObserver: Any?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        // Reliable position tracking — avoids race conditions with currentTime()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.isValid, !time.seconds.isNaN, time.seconds > 0 else { return }
            self?.currentPosition = time.seconds
        }
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
    }

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play()  { player.play();  isPlaying = true  }
    func pause() { player.pause(); isPlaying = false }
    func togglePlayback() { isPlaying ? pause() : play() }
}
