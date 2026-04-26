import XCTest
@testable import SayIt

final class HistoryManagerTests: XCTestCase {

    var manager: HistoryManager!

    override func setUp() {
        super.setUp()
        manager = HistoryManager.shared
        // 清空
        manager.clearAll()
    }

    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }

    // MARK: - 添加和查询

    func testAddRecord() {
        manager.addRecord(rawText: "你好世界", optimizedText: "你好，世界。", sttEngine: "local")
        let records = manager.allRecords
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].rawText, "你好世界")
        XCTAssertEqual(records[0].optimizedText, "你好，世界。")
        XCTAssertEqual(records[0].sttEngine, "local")
    }

    func testAddMultipleRecords() {
        manager.addRecord(rawText: "第一条", optimizedText: nil, sttEngine: "local")
        manager.addRecord(rawText: "第二条", optimizedText: "优化后", sttEngine: "deepgram")
        manager.addRecord(rawText: "第三条", optimizedText: nil, sttEngine: "openai_whisper")
        XCTAssertEqual(manager.allRecords.count, 3)
    }

    // MARK: - 顺序（最新在前）

    func testOrderNewestFirst() {
        manager.addRecord(rawText: "旧", optimizedText: nil, sttEngine: "local")
        manager.addRecord(rawText: "新", optimizedText: nil, sttEngine: "local")
        let records = manager.allRecords
        XCTAssertEqual(records[0].rawText, "新")
        XCTAssertEqual(records[1].rawText, "旧")
    }

    // MARK: - displayText

    func testDisplayTextWithOptimization() {
        manager.addRecord(rawText: "原始", optimizedText: "优化后", sttEngine: "local")
        XCTAssertEqual(manager.allRecords[0].displayText, "优化后")
    }

    func testDisplayTextWithoutOptimization() {
        manager.addRecord(rawText: "原始", optimizedText: nil, sttEngine: "local")
        XCTAssertEqual(manager.allRecords[0].displayText, "原始")
    }

    // MARK: - 删除

    func testDeleteRecord() {
        manager.addRecord(rawText: "要删除", optimizedText: nil, sttEngine: "local")
        let id = manager.allRecords[0].id
        manager.deleteRecord(id: id)
        XCTAssertTrue(manager.allRecords.isEmpty)
    }

    // MARK: - 清空

    func testClearAll() {
        for i in 0..<10 {
            manager.addRecord(rawText: "记录\(i)", optimizedText: nil, sttEngine: "local")
        }
        XCTAssertEqual(manager.allRecords.count, 10)
        manager.clearAll()
        XCTAssertTrue(manager.allRecords.isEmpty)
    }
}
