import SwiftUI
import NukeUI
import ActivityIndicatorView

/// Content is opaque and quiet; Liquid Glass belongs to navigation and controls.
enum CinemaPalette {
    static let background = Color(red: 0.047, green: 0.051, blue: 0.059)
    static let surface = Color(red: 0.090, green: 0.098, blue: 0.110)
    static let elevated = Color(red: 0.133, green: 0.145, blue: 0.165)
    static let ink = Color(red: 0.933, green: 0.941, blue: 0.953)
    static let muted = Color(red: 0.596, green: 0.612, blue: 0.643)
    static let accent = Color(red: 0.835, green: 0.855, blue: 0.886)
    static let line = Color.white.opacity(0.08)
    static let display = Font.system(.title3).weight(.semibold)
    static let section = Font.system(.subheadline).weight(.semibold)
}

extension View {
    func cinemaSurface<S: Shape>(_ shape: S = RoundedRectangle(cornerRadius: 16)) -> some View {
        background(CinemaPalette.surface, in: shape)
            .overlay(shape.stroke(CinemaPalette.line, lineWidth: 0.5))
    }

    func cinemaArrival() -> some View { modifier(CinemaArrival()) }
}

private struct CinemaArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86)) { appeared = true }
            }
    }
}

struct CinemaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CinemaPalette.background)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(CinemaPalette.accent, in: RoundedRectangle(cornerRadius: 11))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct CinemaHeading: View {
    let title: String
    var body: some View {
        Text(title).font(CinemaPalette.display).foregroundStyle(CinemaPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CinemaEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular))
                .foregroundStyle(CinemaPalette.muted).accessibilityHidden(true)
            Text(title).font(CinemaPalette.section)
            Text(detail).font(.subheadline).foregroundStyle(CinemaPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

/// Only actual room/catalog artwork is shown. Missing art stays a neutral frame.
struct CinemaArtwork: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        LazyImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.22))) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else {
                CinemaPalette.elevated
                    .overlay {
                        Image(systemName: "film").font(.title2.weight(.light))
                            .foregroundStyle(CinemaPalette.muted)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CinemaLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "hourglass").font(.title2)
            } else {
                ActivityIndicatorView(type: .equalizer(count: 4))
            }
        }
        .foregroundStyle(CinemaPalette.accent)
        .frame(width: 28, height: 24)
        .accessibilityLabel("Загрузка")
    }
}
