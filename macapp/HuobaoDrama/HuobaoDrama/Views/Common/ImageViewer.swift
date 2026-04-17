import SwiftUI

struct ImageViewer: View {
    var urlString: String
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    private var fullURL: String {
        if urlString.hasPrefix("http") { return urlString }
        return ConnectionSettingsStore.shared.baseURL + urlString
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            AsyncImage(url: URL(string: fullURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = max(0.5, min($0, 5)) }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { offset = $0.translation }
                                .onEnded { _ in
                                    if scale <= 1 { withAnimation { offset = .zero } }
                                }
                        )
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.text3)
                default:
                    ProgressView()
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.lg)
                }
                Spacer()
            }
        }
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }
}
