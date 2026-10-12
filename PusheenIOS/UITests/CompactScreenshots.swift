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
        app.buttons["Активность"].tap()
        capture(app, "activity-compact")
        app.buttons["Вместе"].tap()
        capture(app, "together-compact")
    }
}
