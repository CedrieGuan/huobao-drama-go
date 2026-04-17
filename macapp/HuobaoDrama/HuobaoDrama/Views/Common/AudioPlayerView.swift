import SwiftUI
import AVFoundation

@MainActor
@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var isLoading = false

    private var player: AVPlayer?
    private var timeObserver: Any?

    func load(urlString: String, baseURL: String) {
        let fullURL = urlString.hasPrefix("http") ? urlString : baseURL + urlString
        guard let url = URL(string: fullURL) else { return }
        isLoading = true
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        Task {
            duration = (try? await item.asset.load(.duration).seconds) ?? 0
            isLoading = false
        }
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
            startObserving()
        }
        isPlaying.toggle()
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
    }

    private func startObserving() {
        guard let player, timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
                if time.seconds >= (self?.duration ?? 0) - 0.1 {
                    self?.isPlaying = false
                }
            }
        }
    }

    func cleanup() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player?.pause()
        player = nil
    }
}

struct AudioPlayerView: View {
    var urlString: String

    @State private var vm = AudioPlayerViewModel()

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                vm.togglePlay()
            } label: {
                Image(systemName: vm.isLoading ? "ellipsis" : (vm.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accent)
                    .frame(width: 28, height: 28)
                    .background(Color.accentLight)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)

            Slider(value: Binding(
                get: { vm.currentTime },
                set: { vm.seek(to: $0) }
            ), in: 0...(vm.duration > 0 ? vm.duration : 1))
            .tint(Color.accent)

            Text(timeLabel(vm.currentTime) + " / " + timeLabel(vm.duration))
                .font(.monoSmall)
                .foregroundStyle(Color.text2)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .onAppear { vm.load(urlString: urlString, baseURL: ConnectionSettingsStore.shared.baseURL) }
        .onDisappear { vm.cleanup() }
    }
}
