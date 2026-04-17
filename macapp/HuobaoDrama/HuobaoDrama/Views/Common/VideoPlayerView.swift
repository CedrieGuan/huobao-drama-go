import SwiftUI
import AVKit

struct VideoPlayerView: View {
    var urlString: String
    var aspectRatio: CGFloat = 16 / 9

    @State private var player: AVPlayer?

    private var fullURL: String {
        urlString.hasPrefix("http") ? urlString : ConnectionSettingsStore.shared.baseURL + urlString
    }

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            } else {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.bg2)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay {
                        Image(systemName: "video")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.text3)
                    }
            }
        }
        .onAppear {
            if let url = URL(string: fullURL) {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
