import SwiftUI
import NukeUI
import ActivityIndicatorView

/// Content is opaque and quiet; Liquid Glass belongs to navigation and controls.
enum CinemaPalette {
    static let background = Color(red: 0.063, green: 0.063, blue: 0.067)
    static let surface = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let elevated = Color(red: 0.153, green: 0.153, blue: 0.165)
    static let ink = Color(red: 0.957, green: 0.937, blue: 0.906)
    static let muted = Color(red: 0.690, green: 0.682, blue: 0.671)
    static let accent = Color(red: 0.941, green: 0.478, blue: 0.376)
    static let line = Color.white.opacity(0.12)
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let section = Font.system(.title3).weight(.semibold)
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
            .font(.body.weight(.semibold))
            .foregroundStyle(CinemaPalette.background)
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .background(CinemaPalette.accent, in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct CinemaHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold)).tracking(2)
                .foregroundStyle(CinemaPalette.muted)
            Text(title).font(CinemaPalette.display).foregroundStyle(CinemaPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct CinemaEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
                .foregroundStyle(CinemaPalette.muted).accessibilityHidden(true)
            Text(title).font(CinemaPalette.section)
            Text(detail).font(.subheadline).foregroundStyle(CinemaPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
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
