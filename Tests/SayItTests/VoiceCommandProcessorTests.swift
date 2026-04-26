import XCTest
@testable import SayIt

final class VoiceCommandProcessorTests: XCTestCase {

    var processor: VoiceCommandProcessor!

    override func setUp() {
        super.setUp()
        processor = VoiceCommandProcessor.shared
        // 强制开启
        UserDefaults.standard.set(true, forKey: "voiceCommands")
    }

    // MARK: - 中文标点命令

    func testNewLine() {
        let result = processor.process("你好换行世界")
        XCTAssertEqual(result, "你好\n世界")
    }

    func testNewLineVariant() {
        let result = processor.process("你好新行世界")
        XCTAssertEqual(result, "你好\n世界")
    }

    func testPeriod() {
        let result = processor.process("你好句号")
        XCTAssertEqual(result, "你好。")
    }

    func testComma() {
        let result = processor.process("你好逗号世界")
        XCTAssertEqual(result, "你好，世界")
    }

    func testQuestionMark() {
        let result = processor.process("你好吗问号")
        XCTAssertEqual(result, "你好吗？")
    }

    func testExclamationMark() {
        let result = processor.process("太好了感叹号")
        XCTAssertEqual(result, "太好了！")
    }

    func testExclamationMarkVariant() {
        let result = processor.process("太好了叹号")
        XCTAssertEqual(result, "太好了！")
    }

    func testPauseMark() {
        let result = processor.process("苹果顿号香蕉")
        XCTAssertEqual(result, "苹果、香蕉")
    }

    func testColon() {
        let result = processor.process("注意冒号以下内容")
        XCTAssertEqual(result, "注意：以下内容")
    }

    func testSemicolon() {
        let result = processor.process("第一分号第二")
        XCTAssertEqual(result, "第一；第二")
    }

    func testEllipsis() {
        let result = processor.process("然后省略号")
        XCTAssertEqual(result, "然后……")
    }

    func testDash() {
        let result = processor.process("以下是破折号补充")
        XCTAssertEqual(result, "以下是——补充")
    }

    func testLeftQuote() {
        let result = processor.process("他说左引号你好")
        XCTAssertEqual(result, "他说\u{201C}你好")
    }

    func testRightQuote() {
        let result = processor.process("你好右引号世界")
        XCTAssertEqual(result, "你好\u{201D}世界")
    }

    // MARK: - 英文命令

    func testEnglishPeriod() {
        let result = processor.process("hello period world")
        // 正则替换保留了前后的空格
        XCTAssertEqual(result, "hello . world")
    }

    func testEnglishNewLine() {
        let result = processor.process("hello new line world")
        // "new line" 是两个词，替换后前后空格保留为 " \n "
        XCTAssertEqual(result, "hello \n world")
    }

    // MARK: - 多个命令

    func testMultipleCommands() {
        let result = processor.process("你好逗号世界句号")
        XCTAssertEqual(result, "你好，世界。")
    }

    // MARK: - 删除命令

    func testDeleteChinese() {
        let result = processor.process("你好世界删除")
        // 删除"界"字
        XCTAssertEqual(result, "你好世")
    }

    func testDeleteEnglish() {
        let result = processor.process("hello world delete")
        // 删除"world "
        XCTAssertEqual(result, "hello ")
    }

    // MARK: - 开关

    func testDisabled() {
        UserDefaults.standard.set(false, forKey: "voiceCommands")
        let result = processor.process("你好换行世界")
        XCTAssertEqual(result, "你好换行世界")
        // 恢复
        UserDefaults.standard.set(true, forKey: "voiceCommands")
    }

    // MARK: - 不匹配

    func testNoMatch() {
        let result = processor.process("这是一段正常的语音转写文本")
        XCTAssertEqual(result, "这是一段正常的语音转写文本")
    }
}
