import Foundation
import SwiftUI
import UIKit

/// Keeps visible dates in sync with the settings of this iPhone. Date format,
/// locale and time-zone changes do not require rebuilding the current screen.
@MainActor
final class DeviceEnvironmentStore: ObservableObject {
    @Published private(set) var formattingRevision = 0
    @Published private(set) var currentTime = Date()

    private var observers: [NSObjectProtocol] = []
    private var clockTask: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        let notifications: [Notification.Name] = [
            NSLocale.currentLocaleDidChangeNotification,
            .NSSystemTimeZoneDidChange,
            UIApplication.significantTimeChangeNotification,
            UIApplication.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
        ]
        observers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.currentTime = Date()
            }
        }
    }

    func refresh() {
        TimeZone.resetSystemTimeZone()
        currentTime = Date()
        formattingRevision &+= 1
    }
}
