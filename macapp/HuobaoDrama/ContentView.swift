import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("火爆短剧")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI 驱动的短剧制作工具")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
