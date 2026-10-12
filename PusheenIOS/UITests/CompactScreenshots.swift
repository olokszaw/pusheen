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
        let heading = app.staticTexts["СТАТИСТИКА"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        // The original pager's accessibility label propagates to its children.
        // Anchor the gesture to the independent, visible section heading.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let gestureY = heading.frame.maxY + 75
        let start = origin.withOffset(CGVector(dx: app.frame.width * 0.82, dy: gestureY))
        let finish = origin.withOffset(CGVector(dx: app.frame.width * 0.18, dy: gestureY))
        start.press(forDuration: 0.05, thenDragTo: finish)
        let activity = app.images["chart.bar.xaxis"]
        XCTAssertLessThan(activity.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThan(activity.frame.minX, app.frame.minX)
        capture(app, "activity-compact")
        start.press(forDuration: 0.05, thenDragTo: finish)
        let companion = app.staticTexts["Нажми на аватар"]
        XCTAssertLessThan(companion.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThan(companion.frame.minX, app.frame.minX)
        capture(app, "together-compact")
    }
}
