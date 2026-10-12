#if DEBUG
import SwiftUI

/// Real app components, with local fixture data and no backend requests.
struct CinemaPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            CinemaPreviewBoard()
                .previewDisplayName("375 pt · компоненты")
                .previewLayout(.fixed(width: 375, height: 812))
            CinemaPreviewBoard()
                .environment(\.dynamicTypeSize, .accessibility3)
                .environment(\.accessibilityReduceMotion, true)
                .previewDisplayName("Крупный текст · без движения")
                .previewLayout(.fixed(width: 375, height: 812))
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(CinemaPalette.ink)
        .tint(CinemaPalette.accent)
    }
}

private struct CinemaPreviewBoard: View {
    @State private var name = ""
    @State private var password = ""
    private let room = Room(id: 1, owner: 1, ownerName: "Анна", title: "Вечер с друзьями",
                            inviteCode: "CINEMA", mediaURL: "", thumbnailURL: "", membersCount: 3, playback: nil)
    var body: some View {
        ZStack {
            AcrylicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CinemaHeading(eyebrow: "Pusheen · watch together", title: "Твой кинозал")
                    RoomCard(room: room)
                    GlassField(icon: "at", title: "Username", text: $name)
                    GlassSecureField(title: "Пароль", text: $password)
                    Button {} label: {
                        HStack { Text("Создать комнату"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(CinemaPrimaryButtonStyle())
                    CinemaLoadingIndicator()
                }.padding(24)
            }
        }
    }
}
#endif
