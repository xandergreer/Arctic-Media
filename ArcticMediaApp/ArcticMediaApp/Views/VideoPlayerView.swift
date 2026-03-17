import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @EnvironmentObject var api: APIService
    @Environment(\.dismiss) var dismiss

    let mediaId: Int
    let fileId: Int?
    let audioIndex: Int?
    let subtitleIndex: Int?
    let title: String

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let err = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text(err)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }

            // Close button overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    Spacer()
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    // Balance button
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.clear)
                }
                .padding()
                Spacer()
            }
        }
        .task { await setupPlayer() }
        .onDisappear { player?.pause() }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private func setupPlayer() async {
        isLoading = true
        error = nil

        guard let url = api.streamURL(
            mediaId: mediaId,
            fileId: fileId,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex
        ) else {
            error = "Could not construct stream URL"
            isLoading = false
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)

        // Configure audio session for iOS
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        #endif

        player = newPlayer
        newPlayer.play()
        isLoading = false
    }
}
