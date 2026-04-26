import XCTest
@testable import SayIt

final class UserDictionaryTests: XCTestCase {

    var dict: UserDictionary!

    override func setUp() {
        super.setUp()
        dict = UserDictionary.shared
        // 清空
        dict.replaceAll([])
    }

    override func tearDown() {
        dict.replaceAll([])
        super.tearDown()
    }

    // MARK: - 添加和查询

    func testAddEntry() {
        dict.addEntry(phrase: "Finogeeks", replacements: ["非奴极客"])
        let entries = dict.allEntries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].phrase, "Finogeeks")
        XCTAssertEqual(entries[0].replacements, ["非奴极客"])
    }

    func testAddMultipleEntries() {
        dict.addEntry(phrase: "Kubernetes")
        dict.addEntry(phrase: "DeepSeek")
        dict.addEntry(phrase: "Whisper")
        XCTAssertEqual(dict.allEntries.count, 3)
    }

    // MARK: - 文本纠正

    func testCorrectText() {
        dict.addEntry(phrase: "Finogeeks", replacements: ["非奴极客", "飞诺极客"])
        let result = dict.correct("我在非奴极客工作")
        XCTAssertEqual(result, "我在Finogeeks工作")
    }

    func testCorrectMultipleOccurrences() {
        dict.addEntry(phrase: "SayIt", replacements: ["赛义特"])
        let result = dict.correct("赛义特是一个好用的工具，赛义特很棒")
        XCTAssertEqual(result, "SayIt是一个好用的工具，SayIt很棒")
    }

    func testNoCorrectionNeeded() {
        dict.addEntry(phrase: "Finogeeks", replacements: ["非奴极客"])
        let result = dict.correct("Hello World")
        XCTAssertEqual(result, "Hello World")
    }

    // MARK: - 删除

    func testDeleteEntry() {
        dict.addEntry(phrase: "Test1")
        dict.addEntry(phrase: "Test2")
        let id = dict.allEntries[0].id
        dict.deleteEntry(id: id)
        XCTAssertEqual(dict.allEntries.count, 1)
        XCTAssertEqual(dict.allEntries[0].phrase, "Test2")
    }

    // MARK: - Whisper prompt

    func testWhisperPromptEmpty() {
        XCTAssertTrue(dict.whisperPromptSuffix.isEmpty)
    }

    func testWhisperPromptWithEntries() {
        dict.addEntry(phrase: "Finogeeks")
        dict.addEntry(phrase: "Kubernetes")
        let prompt = dict.whisperPromptSuffix
        XCTAssertTrue(prompt.contains("Finogeeks"))
        XCTAssertTrue(prompt.contains("Kubernetes"))
        XCTAssertTrue(prompt.hasPrefix(" "))
    }
}
