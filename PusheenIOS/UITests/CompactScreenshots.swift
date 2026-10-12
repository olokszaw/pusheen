import XCTest

@MainActor
final class CompactScreenshots: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAuthenticationAndRegistration() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Войти"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Кино сближает"].exists)
        capture(app, "auth-compact")
        app.buttons["Регистрация"].tap()
        XCTAssertTrue(app.buttons["Создать аккаунт"].waitForExistence(timeout: 5))
        capture(app, "registration-compact")
    }

    func testNativeTabsAndProfileSections() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["Друзья"].waitForExistence(timeout: 10))
        capture(app, "rooms-compact")
        app.buttons["Друзья"].tap()
        XCTAssertTrue(app.buttons["Найти друзей"].waitForExistence(timeout: 5))
        capture(app, "friends-compact")
        app.buttons["Профиль"].tap()
        XCTAssertTrue(app.buttons["Редактировать профиль"].waitForExistence(timeout: 5))
        capture(app, "profile-compact")
        let genres = app.staticTexts["Жанры"].firstMatch
        XCTAssertTrue(genres.waitForExistence(timeout: 5))
        // SwiftUI exposes the pager's label as a zero-sized StaticText.
        // Anchor the real gesture to the visible card heading instead.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let gestureY = genres.frame.maxY + 30
        let start = origin.withOffset(CGVector(dx: app.frame.width * 0.82, dy: gestureY))
        let finish = origin.withOffset(CGVector(dx: app.frame.width * 0.18, dy: gestureY))
        start.press(forDuration: 0.05, thenDragTo: finish)
        XCTAssertTrue(app.staticTexts["Активность"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "activity-compact")
        start.press(forDuration: 0.05, thenDragTo: finish)
        capture(app, "together-compact")
    }
}
