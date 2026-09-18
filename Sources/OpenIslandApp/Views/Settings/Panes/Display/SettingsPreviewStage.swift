import OpenIslandCore
import SwiftUI

struct SettingsPreviewStage<Content: View>: View {
    var contentTopPadding: CGFloat = 20
    var contentBottomPadding: CGFloat = 24
    let content: Content

    init(
        contentTopPadding: CGFloat = 20,
        contentBottomPadding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.contentTopPadding = contentTopPadding
        self.contentBottomPadding = contentBottomPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(SettingsPreviewWallpaper())
        .clipShape(IslandThemes.current.shape(cornerRadius: 14))
        .overlay(
            IslandThemes.current.shape(cornerRadius: 14)
                .stroke(V6Palette.paper.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsPreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 60.0 / 255.0, green: 35.0 / 255.0, blue: 68.0 / 255.0),
                    Color(red: 95.0 / 255.0, green: 46.0 / 255.0, blue: 88.0 / 255.0),
                    Color(red: 168.0 / 255.0, green: 81.0 / 255.0, blue: 122.0 / 255.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
