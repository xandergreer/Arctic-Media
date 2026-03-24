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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // Pure video layer — no native controls, taps pass through to ZStack
                PlayerLayer(player: coordinator.player)
                    .ignoresSafeArea()

                // Controls overlay — positioned with explicit safe area insets
                // so nothing is clipped by the status bar or Dynamic Island
                if showControls {
                    VStack(spacing: 0) {
                        topBar
                            // geo.safeAreaInsets.top includes the Dynamic Island height
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
        .onAppear {
            coordinator.load(url: streamURL)
            Task { await resumeProgress() }
            scheduleHideControls()
            startProgressTimer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            stopProgressTimer()
            coordinator.pause()
            Task { await saveProgress() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.pause()
                Task { await saveProgress() }
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
        }
        .padding(.vertical, 10)
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
            Task { await saveProgress() }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func saveProgress() async {
        let pos = coordinator.player.currentTime().seconds
        let dur = coordinator.player.currentItem?.duration.seconds
        guard pos.isFinite, pos > 0 else { return }
        let validDur = (dur?.isFinite == true && dur! > 0) ? dur : nil
        try? await api.saveProgress(mediaId: mediaId, position: pos, duration: validDur)
    }
}

// MARK: - Player coordinator

@MainActor
final class PlayerCoordinator: ObservableObject {
    let player = AVPlayer()
    @Published var isPlaying = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play()  { player.play();  isPlaying = true  }
    func pause() { player.pause(); isPlaying = false }
    func togglePlayback() { isPlaying ? pause() : play() }
}
