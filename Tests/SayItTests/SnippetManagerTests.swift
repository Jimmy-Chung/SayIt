import XCTest
@testable import SayIt

final class SnippetManagerTests: XCTestCase {

    var manager: SnippetManager!

    override func setUp() {
        super.setUp()
        manager = SnippetManager.shared
        manager.replaceAll([])
    }

    override func tearDown() {
        manager.replaceAll([])
        super.tearDown()
    }

    // MARK: - 精确匹配

    func testExactMatch() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com/user/30min")
        let result = manager.process("日历")
        XCTAssertEqual(result, "https://calendly.com/user/30min")
    }

    func testNoMatch() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com")
        let result = manager.process("今天天气真好")
        XCTAssertEqual(result, "今天天气真好")
    }

    func testTrimmedMatch() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com")
        let result = manager.process("  日历  ")
        XCTAssertEqual(result, "https://calendly.com")
    }

    // MARK: - 模糊匹配

    func testFuzzyMatchOneCharDiff() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com")
        // "日力" 与 "日历" 编辑距离为 1
        let result = manager.process("日力")
        XCTAssertEqual(result, "https://calendly.com")
    }

    func testFuzzyMatchNotTooFar() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com")
        // "太阳" 与 "日历" 编辑距离为 2，不应匹配
        let result = manager.process("太阳")
        XCTAssertEqual(result, "太阳")
    }

    // MARK: - 多个 snippet

    func testMultipleSnippets() {
        manager.addSnippet(trigger: "日历", expansion: "https://calendly.com")
        manager.addSnippet(trigger: "邮箱", expansion: "user@example.com")
        XCTAssertEqual(manager.process("日历"), "https://calendly.com")
        XCTAssertEqual(manager.process("邮箱"), "user@example.com")
    }

    // MARK: - CRUD

    func testAddAndDelete() {
        manager.addSnippet(trigger: "test", expansion: "value")
        XCTAssertEqual(manager.allSnippets.count, 1)
        let id = manager.allSnippets[0].id
        manager.deleteSnippet(id: id)
        XCTAssertTrue(manager.allSnippets.isEmpty)
    }

    // MARK: - 不匹配时原样返回

    func testLongTextNoMatch() {
        manager.addSnippet(trigger: "日历", expansion: "link")
        let result = manager.process("今天我想和你讨论一下项目的进展情况")
        XCTAssertEqual(result, "今天我想和你讨论一下项目的进展情况")
    }
}
