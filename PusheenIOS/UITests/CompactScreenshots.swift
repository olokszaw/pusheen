import XCTest

@MainActor
final class CompactScreenshots: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func fixtures(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Друзья"].waitForExistence(timeout: 10))
        return app
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
        let app = fixtures()
        capture(app, "rooms-compact")
        app.buttons["Друзья"].tap()
        XCTAssertTrue(app.buttons["friend-search-button"].waitForExistence(timeout: 5))
        capture(app, "friends-compact")
        app.staticTexts["Маша"].firstMatch.tap()
        XCTAssertTrue(app.buttons["open-full-profile"].waitForExistence(timeout: 5))
        capture(app, "friend-preview")
        app.buttons["open-full-profile"].tap()
        XCTAssertTrue(app.buttons["Закрыть профиль пользователя"].waitForExistence(timeout: 5))
        capture(app, "friend-profile")
        app.buttons["Закрыть профиль пользователя"].tap()
        app.buttons["Профиль"].tap()
        XCTAssertTrue(app.buttons["profile-menu"].waitForExistence(timeout: 5))
        capture(app, "profile-compact")
        app.buttons["stats-1"].tap()
        XCTAssertTrue(app.buttons["heatmap-months-1"].waitForExistence(timeout: 5))
        capture(app, "activity-compact")
        app.buttons["heatmap-months-1"].tap()
        capture(app, "activity-month")
        app.buttons["stats-2"].tap()
        XCTAssertTrue(app.staticTexts["Совместные просмотры"].waitForExistence(timeout: 5))
        capture(app, "together-compact")
        app.buttons["stats-0"].tap()
        app.buttons["profile-menu"].tap()
        XCTAssertTrue(app.buttons["Выйти из аккаунта"].waitForExistence(timeout: 5))
        capture(app, "profile-menu")
        app.buttons["Выйти из аккаунта"].tap()
        XCTAssertTrue(app.buttons["Отмена"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.buttons["profile-menu"].exists)
        capture(app, "profile-after-cancel")
        app.buttons["Редактировать профиль"].tap()
        XCTAssertTrue(app.buttons["save-profile"].waitForExistence(timeout: 5))
        capture(app, "profile-editor")
        app.buttons["Закрыть редактор"].tap()
        XCTAssertTrue(app.buttons["profile-menu"].waitForExistence(timeout: 5))
    }
    func testEmptyFriendsSearch() {
        let app = fixtures(["--ui-fixtures-empty-friends"])
        app.buttons["Друзья"].tap()
        let search = app.buttons["empty-friends-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        capture(app, "friends-empty")
        search.tap()
        let field = app.textFields["friend-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("nobody_here")
        XCTAssertTrue(app.staticTexts["Никого не найдено"].waitForExistence(timeout: 5))
        capture(app, "friends-search-empty")
        app.buttons["Закрыть поиск"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }
    func testRoomCreationAndPlaybackLayout() {
        let app = fixtures()
        app.buttons["Создать комнату"].tap()
        XCTAssertTrue(app.staticTexts["Источник видео"].waitForExistence(timeout: 5))
        capture(app, "create-room")
        app.buttons["Закрыть создание комнаты"].tap()
        app.buttons["Войти по коду"].tap()
        XCTAssertTrue(app.textFields["Код комнаты"].waitForExistence(timeout: 5))
        capture(app, "join-room")
        app.buttons["Закрыть ввод кода"].tap()
        let room = app.buttons["room-1"]
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        room.tap()
        XCTAssertTrue(app.buttons["Участники комнаты"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Я готов")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "player-chat")
        app.buttons["Назад к комнатам"].tap()
        XCTAssertTrue(app.buttons["Создать комнату"].waitForExistence(timeout: 5))
    }
    func testLargeTextAndReducedMotion() {
        let app = fixtures(["--ui-fixtures-empty-friends", "--ui-fixtures-reduce-motion", "--ui-fixtures-large-text"])
        app.buttons["Друзья"].tap()
        XCTAssertTrue(app.buttons["empty-friends-search"].waitForExistence(timeout: 5))
        capture(app, "friends-large-text")
        app.buttons["Профиль"].tap()
        XCTAssertTrue(app.buttons["profile-menu"].waitForExistence(timeout: 5))
        capture(app, "profile-large-text")
    }
}
