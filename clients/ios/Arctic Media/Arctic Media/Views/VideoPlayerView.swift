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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if isLoading && errorMessage == nil {
                VStack(spacing: 14) {
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Text("Loading…").font(.footnote).foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let msg = errorMessage {
                errorOverlay(msg)
            }

            // Close button — VideoPlayer doesn't expose one when presented via fullScreenCover
            if !isLoading && errorMessage == nil {
                VStack {
                    HStack {
                        Button {
                            teardown()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white, Color.black.opacity(0.45))
                                .shadow(radius: 4)
                        }
                        .padding(.leading, 16)
                        .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
                .safeAreaPadding(.top)
            }
        }
        .preferredColorScheme(.dark)
        .task { await setup() }
        .onDisappear { teardown() }
    }

    // MARK: - Setup / teardown

    private func setup() async {
        // Pre-fetch duration from server for better seek UX before AVPlayer loads
        if let info = try? await APIService.shared.streamInfo(
            serverURL: serverURL, token: token, mediaId: mediaId),
           let d = info.duration, d > 0 {
            await MainActor.run { duration = d }
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        await MainActor.run { player = p }

        // Progress autosave every ~10 s
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

        // Seek to resume point and start playing once ready
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

        // End-of-playback: save completion + trigger autoplay
        let eo = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
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
