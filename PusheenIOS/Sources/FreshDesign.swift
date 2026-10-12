import SwiftUI
import Charts

// The authentication screen retains CinemaPalette. This system belongs to the signed-in app.
enum FreshPalette {
    static let background = Color(red: 0.039, green: 0.043, blue: 0.043)
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.082)
    static let elevated = Color(red: 0.14, green: 0.16, blue: 0.15)
    static let ink = Color(red: 0.94, green: 0.95, blue: 0.91)
    static let muted = Color(red: 0.58, green: 0.62, blue: 0.58)
    static let accent = Color(red: 0.79, green: 0.88, blue: 0.70)
    static let line = Color.white.opacity(0.10)
    static let display = Font.system(.title2).weight(.semibold)
    static let section = Font.system(.subheadline).weight(.semibold)
}

struct FreshBackdrop: View {
    var body: some View { FreshPalette.background.ignoresSafeArea() }
}

struct FreshButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(FreshPalette.background).padding(.horizontal, 18).frame(minHeight: 44)
            .background(FreshPalette.accent, in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension View {
    func freshSurface<S: Shape>(_ shape: S = RoundedRectangle(cornerRadius: 10)) -> some View {
        background(FreshPalette.surface, in: shape)
    }
}

struct FreshField: View {
    let icon: String
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(FreshPalette.muted)
                .frame(width: 20).accessibilityHidden(true)
            TextField(title, text: $text).focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(title)
        }.font(.body).padding(.vertical, 15)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? FreshPalette.accent : FreshPalette.line).frame(height: focused ? 2 : 1)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focused)
    }
}

struct FreshHistoryChart: View {
    let daily: [String: Int]
    @State private var selectedDate: Date?
    private struct Day: Identifiable {
        let date: Date
        let seconds: Int
        var id: Date { date }
    }
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, seconds: daily[Self.formatter.string(from: date)] ?? 0)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("За две недели").font(.headline)
                Spacer()
                Text("\(days.reduce(0) { $0 + $1.seconds } / 3600) ч").font(.headline.monospacedDigit())
            }
            Chart(days) { day in
                BarMark(x: .value("День", day.date, unit: .day), y: .value("Часы", Double(day.seconds) / 3600))
                    .foregroundStyle(FreshPalette.accent).cornerRadius(3)
                if let selectedDate, Calendar.current.isDate(day.date, inSameDayAs: selectedDate) {
                    RuleMark(x: .value("Выбранный день", day.date)).foregroundStyle(FreshPalette.muted)
                }
            }
            .chartYScale(domain: 0...max(1, Double(days.map(\.seconds).max() ?? 0) / 3600))
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { AxisValueLabel(format: .dateTime.day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
            .accessibilityLabel("История просмотра за последние 14 дней, в часах")
            if let selectedDate {
                let seconds = daily[Self.formatter.string(from: selectedDate)] ?? 0
                Text("\(selectedDate.formatted(.dateTime.day().month(.wide))): \(seconds / 60) мин")
                    .font(.caption).foregroundStyle(FreshPalette.muted)
            } else {
                Text(daily.isEmpty ? "Пока нет просмотров" : "Коснись графика, чтобы посмотреть день")
                    .font(.caption).foregroundStyle(FreshPalette.muted)
            }
        }.padding(.vertical, 16)
    }
}

struct FreshCompanionRow: View {
    let companion: ViewingCompanion?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Совместные просмотры").font(.headline)
            if let companion {
                HStack(spacing: 14) {
                    AvatarView(dataURL: companion.avatarDataURL, name: companion.nickname, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(companion.nickname).font(.subheadline.weight(.semibold))
                        Text("@\(companion.username)").font(.caption).foregroundStyle(FreshPalette.muted)
                    }
                    Spacer()
                    Text("\(companion.seconds / 3600) ч").font(.title3.monospacedDigit())
                }
            } else {
                Text("Пока нет совместных просмотров").font(.subheadline).foregroundStyle(FreshPalette.muted)
            }
        }.padding(.vertical, 16)
    }
}
