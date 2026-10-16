import SwiftUI
import Kingfisher
import Shimmer

enum CinemaPalette {
    static let background = Color(red: 0.057, green: 0.061, blue: 0.065)
    static let surface = Color(red: 0.102, green: 0.106, blue: 0.114)
    static let elevated = Color(red: 0.157, green: 0.165, blue: 0.176)
    static let ink = Color(red: 0.949, green: 0.941, blue: 0.922)
    static let muted = Color(red: 0.608, green: 0.620, blue: 0.631)
    // Retained tint for the existing glass navigation and genre interactions.
    static let accent = Color(red: 0.65, green: 0.69, blue: 1.0)
    static let line = Color.white.opacity(0.08)
    static let display = Font.system(.title3).weight(.bold)
    static let section = Font.system(.subheadline).weight(.semibold)
}

enum StudioPalette {
    static let action = CinemaPalette.ink
    static let data = Color(red: 0.56, green: 0.77, blue: 0.68)
    static let danger = Color(red: 0.96, green: 0.49, blue: 0.47)
}

enum StudioMotion {
    static var previewReduced: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-fixtures-reduce-motion")
        #else
        return false
        #endif
    }
}

extension View {
    func cinemaSurface<S: Shape>(_ shape: S = RoundedRectangle(cornerRadius: 14)) -> some View {
        background(CinemaPalette.surface, in: shape)
            .overlay(shape.stroke(CinemaPalette.line, lineWidth: 0.7))
    }
    func cinemaArrival() -> some View { modifier(CinemaArrival()) }
}

private struct CinemaArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || StudioMotion.previewReduced }
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.16)) { appeared = true }
            }
    }
}

struct CinemaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || StudioMotion.previewReduced }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(CinemaPalette.background)
            .padding(.horizontal, 18).frame(minHeight: 46)
            .background(StudioPalette.action, in: RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.28), value: configuration.isPressed)
    }
}

struct StudioIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .background(CinemaPalette.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(AlivePressButtonStyle()).accessibilityLabel(label)
    }
}

struct CinemaHeading: View {
    let title: String
    var body: some View {
        Text(title).font(CinemaPalette.display).foregroundStyle(CinemaPalette.ink)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
}

struct StudioSection: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(CinemaPalette.muted) }
        }.accessibilityAddTraits(.isHeader)
    }
}

struct CinemaEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(CinemaPalette.muted).frame(height: 48).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(CinemaPalette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 32)
    }
}

struct StudioField: View {
    let title: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(CinemaPalette.muted)
            Group {
                if secure { SecureField(title, text: $text).textContentType(.password) }
                else { TextField(title, text: $text).textContentType(title == "Username" ? .username : .nickname) }
            }.font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).padding(.horizontal, 14).frame(minHeight: 48)
                .background(CinemaPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? CinemaPalette.ink.opacity(0.65) : CinemaPalette.line, lineWidth: 1))
        }.animation(.snappy(duration: 0.24), value: focused)
    }
}

struct CinemaArtwork: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || StudioMotion.previewReduced }
    var body: some View {
        Group {
            if let url {
                KFImage(url).placeholder { placeholder.shimmering(active: !reduceMotion) }
                    .fade(duration: reduceMotion ? 0 : 0.2).cancelOnDisappear(true)
                    .resizable().aspectRatio(contentMode: contentMode)
            } else { placeholder }
        }.accessibilityHidden(true)
    }
    private var placeholder: some View {
        Rectangle().fill(CinemaPalette.elevated)
            .overlay {
                Image(systemName: "play.rectangle").font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(CinemaPalette.muted.opacity(0.7))
            }
    }
}

struct CinemaLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || StudioMotion.previewReduced }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { _ in Capsule().fill(CinemaPalette.muted).frame(width: 6, height: 18) }
        }.shimmering(active: !reduceMotion).accessibilityLabel("Загрузка")
    }
}
