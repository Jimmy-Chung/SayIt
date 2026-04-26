import XCTest
@testable import SayIt

final class SpeechLanguageTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(SpeechLanguage.allCases.count, 8)
    }

    func testAutoDetect() {
        let lang = SpeechLanguage.auto_detect
        XCTAssertEqual(lang.displayName, "自动检测")
        XCTAssertEqual(lang.whisperCode, "auto")
        XCTAssertEqual(lang.deepgramCode, "multi")
    }

    func testChinese() {
        let lang = SpeechLanguage.chinese
        XCTAssertEqual(lang.displayName, "中文")
        XCTAssertEqual(lang.whisperCode, "zh")
        XCTAssertEqual(lang.deepgramCode, "zh-CN")
    }

    func testEnglish() {
        let lang = SpeechLanguage.english
        XCTAssertEqual(lang.displayName, "English")
        XCTAssertEqual(lang.whisperCode, "en")
        XCTAssertEqual(lang.deepgramCode, "en-US")
    }

    func testJapanese() {
        let lang = SpeechLanguage.japanese
        XCTAssertEqual(lang.whisperCode, "ja")
    }

    func testCurrentDefault() {
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
        let current = SpeechLanguage.current
        XCTAssertEqual(current, .auto_detect)
    }

    func testCurrentFromDefaults() {
        UserDefaults.standard.set("en", forKey: "speechLanguage")
        XCTAssertEqual(SpeechLanguage.current, .english)
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
    }
}

final class OverlayPositionTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(OverlayPosition.allCases.count, 3)
    }

    func testDisplayNames() {
        XCTAssertEqual(OverlayPosition.bottomCenter.displayName, "屏幕底部居中")
        XCTAssertEqual(OverlayPosition.nearCursor.displayName, "跟随鼠标")
        XCTAssertEqual(OverlayPosition.lastPosition.displayName, "记住上次位置")
    }

    func testCurrentDefault() {
        UserDefaults.standard.removeObject(forKey: "overlayPosition")
        XCTAssertEqual(OverlayPosition.current, .bottomCenter)
    }
}
