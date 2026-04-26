import XCTest
@testable import SayIt

final class ContextProviderTests: XCTestCase {

    var provider: ContextProvider!

    override func setUp() {
        super.setUp()
        provider = ContextProvider.shared
    }

    // MARK: - AppContext 属性

    func testEmailContext() {
        let ctx = AppContext.email
        XCTAssertEqual(ctx.displayName, "邮件")
        XCTAssertTrue(ctx.llmPromptSuffix.contains("邮件"))
        XCTAssertTrue(ctx.llmPromptSuffix.contains("专业"))
    }

    func testMessagingContext() {
        let ctx = AppContext.messaging
        XCTAssertEqual(ctx.displayName, "聊天")
        XCTAssertTrue(ctx.llmPromptSuffix.contains("聊天"))
        XCTAssertTrue(ctx.llmPromptSuffix.contains("简洁"))
    }

    func testCodeContext() {
        let ctx = AppContext.code
        XCTAssertEqual(ctx.displayName, "代码")
        XCTAssertTrue(ctx.llmPromptSuffix.contains("代码"))
        XCTAssertTrue(ctx.llmPromptSuffix.contains("技术"))
    }

    func testDocumentContext() {
        let ctx = AppContext.document
        XCTAssertEqual(ctx.displayName, "文档")
        XCTAssertTrue(ctx.llmPromptSuffix.contains("文档"))
    }

    func testNoteContext() {
        let ctx = AppContext.note
        XCTAssertEqual(ctx.displayName, "笔记")
        XCTAssertTrue(ctx.llmPromptSuffix.contains("笔记"))
    }

    func testGeneralContext() {
        let ctx = AppContext.general
        XCTAssertEqual(ctx.displayName, "通用")
        XCTAssertTrue(ctx.llmPromptSuffix.isEmpty)
    }

    // MARK: - detect()

    func testDetectReturnsSomeContext() {
        // 在测试环境中前台应用可能是 Xcode 或终端
        let ctx = provider.detect()
        // 至少不应崩溃
        XCTAssertNotNil(ctx)
    }

    // MARK: - AppContext CaseIterable

    func testAllCases() {
        XCTAssertEqual(AppContext.allCases.count, 6)
    }
}
