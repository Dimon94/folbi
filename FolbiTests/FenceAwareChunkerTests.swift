import XCTest
@testable import Folbi

/// Seam 1（spec #10）：fence 感知分块器纯函数。
/// 重组恒等与围栏配平断言迁移自 #8 原型 bench。
final class FenceAwareChunkerTests: XCTestCase {
    func testEmptyDocumentProducesNoChunks() {
        XCTAssertEqual(FenceAwareChunker.split(""), [])
    }

    func testSmallDocumentStaysSingleChunk() {
        let source = "# 标题\n\n短文档。\n"
        XCTAssertEqual(FenceAwareChunker.split(source), [source])
    }

    /// 精确块大小边界：块字节数恰好等于 targetBytes 时，在紧随的空行处切出。
    func testCutFiresAtBlankLineWhenChunkReachesExactTarget() {
        let target = 64
        // 62 字节段落 + "\n"（63）+ 空行 "\n"（恰好 64）
        let source = String(repeating: "a", count: 62) + "\n\n" + String(repeating: "b", count: 10)
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].utf8.count, target)
        XCTAssertTrue(chunks[0].hasSuffix("\n\n"), "切点钉在空行之后")
        XCTAssertEqual(chunks.joined(), source)
    }

    /// 未达 targetBytes 时空行不切；其后无空行则整块保留（块可超过 targetBytes）。
    func testNoCutAtBlankLineBelowTarget() {
        let target = 64
        // 60 字节段落 + "\n\n"（62 < 64，不切）+ 30 字节段落（无尾随换行）
        let source = String(repeating: "a", count: 60) + "\n\n" + String(repeating: "b", count: 30)
        XCTAssertEqual(FenceAwareChunker.split(source, targetBytes: target), [source])
    }

    /// 围栏跨块：超过 targetBytes 且内含空行的代码围栏必须整体留在同一块内，
    /// 切点只允许出现在围栏结束后的空行。
    func testFenceBlockStaysInOneChunkWhenSpanningTarget() {
        let target = 64
        let chunks = FenceAwareChunker.split(backtickFenceDocument, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("```swift"))
        XCTAssertTrue(chunks[0].hasSuffix("```\n\n"), "围栏整体留在块内，切点在围栏结束后的空行")
        XCTAssertEqual(chunks[1], "结尾段落")
        XCTAssertEqual(chunks.joined(), backtickFenceDocument)
    }

    /// marker 不匹配的围栏行是围栏内容：``` 围栏内的 ~~~ 行不关闭围栏。
    func testMismatchedFenceMarkerLineDoesNotCloseFence() {
        let target = 64
        let source = "```\n"
            + String(repeating: "a", count: 60) + "\n"
            + "~~~\n"   // marker 不匹配，仍是围栏内容
            + "\n"       // 围栏内空行：误判为已关闭的实现会在此切断
            + String(repeating: "b", count: 10) + "\n"
            + "```\n"
            + "\n"
            + "结尾"
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].hasSuffix("```\n\n"))
        XCTAssertEqual(chunks[1], "结尾")
        XCTAssertEqual(chunks.joined(), source)
    }

    /// CommonMark 闭合规则：闭合 run 长度必须 ≥ 开围栏。4 反引号围栏内的 3 反引号行是内容。
    func testFourBacktickFenceIsNotClosedByThreeBacktickLine() {
        let target = 64
        let source = "````\n"
            + String(repeating: "a", count: 60) + "\n"
            + "```\n"   // run 长度 3 < 开围栏 4，是内容
            + "\n"       // 围栏内空行：误判为已关闭的实现会在此切断
            + String(repeating: "b", count: 10) + "\n"
            + "````\n"
            + "\n"
            + "结尾"
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].hasSuffix("````\n\n"), "切点在 4 反引号围栏真正闭合后的空行")
        XCTAssertEqual(chunks[1], "结尾")
        XCTAssertEqual(chunks.joined(), source)
    }

    /// CommonMark 闭合规则：闭合行不允许 info string。围栏内带文字的标记行是内容。
    func testFenceMarkerLineWithInfoStringDoesNotCloseFence() {
        let target = 64
        let source = "```\n"
            + String(repeating: "a", count: 60) + "\n"
            + "``` 带文字的围栏内容行\n"   // 闭合行带 info string 非法，仍是内容
            + "\n"                        // 围栏内空行：误判为已关闭的实现会在此切断
            + String(repeating: "b", count: 10) + "\n"
            + "```\n"
            + "\n"
            + "结尾"
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].hasSuffix("```\n\n"))
        XCTAssertEqual(chunks[1], "结尾")
        XCTAssertEqual(chunks.joined(), source)
    }

    /// CommonMark：行首 4+ 空格缩进的标记行是缩进代码块内容，不是围栏。
    /// 误判为开围栏会产生永不闭合的幻影围栏，其后所有空行都不再切。
    func testIndentedMarkerLineIsNotAFence() {
        let target = 64
        let source = String(repeating: "a", count: 40) + "\n"
            + "\n"                           // 42 < 64，不切
            + "    ```\n"                     // 4 空格缩进 = 缩进代码块，非围栏
            + "    code\n"
            + "\n"                           // 59 < 64，不切
            + String(repeating: "b", count: 20) + "\n"
            + "\n"                           // 累计 82 ≥ 64：幻影围栏会吞掉这个切点
            + "结尾"
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].utf8.count, 82)
        XCTAssertEqual(chunks[1], "结尾")
        XCTAssertEqual(chunks.joined(), source)
    }

    /// 钉住 8 KiB 默认值（容量决策，L5 合同见 split 声明处）：
    /// 8000 字节处的空行不许切（排除更小的默认值），8200 字节处的空行必须切（排除更大的默认值）。
    func testDefaultTargetIsEightKiB() {
        let source = String(repeating: "a", count: 7998) + "\n\n"   // 8000 < 8192，不切
            + String(repeating: "b", count: 198) + "\n\n"           // 累计 8200 ≥ 8192，切
            + "c"
        let chunks = FenceAwareChunker.split(source)

        XCTAssertEqual(chunks.map { $0.utf8.count }, [8200, 1])
        XCTAssertEqual(chunks.joined(), source)
    }

    /// 松散列表空行切点：达到 targetBytes 后在列表项之间的空行切分（spec #10 已接受的 trade-off）。
    func testLooseListSplitsAtBlankLineBetweenItems() {
        let target = 64
        let item = "- item: load children lazily\n\n"  // 30 字节/项
        let source = String(repeating: item, count: 5)
        let chunks = FenceAwareChunker.split(source, targetBytes: target)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].utf8.count, 90, "第 3 项后的空行处切出")
        XCTAssertTrue(chunks[0].hasSuffix("\n\n"))
        XCTAssertEqual(chunks.joined(), source)
    }

    /// 重组恒等（迁移自 bench）：任意输入下 chunks.joined() 与原文逐字节一致。
    func testRejoiningChunksAlwaysMatchesSource() {
        let sources = [
            "无尾随换行",
            "# 标题\n\n段落。\n",
            backtickFenceDocument,
            tildeFenceDocument,
            String(repeating: "- item\n\n", count: 40),
            makeMixedDocument(targetBytes: 20 * 1024),
        ]
        for source in sources {
            XCTAssertEqual(FenceAwareChunker.split(source).joined(), source)
            XCTAssertEqual(FenceAwareChunker.split(source, targetBytes: 256).joined(), source)
        }
    }

    /// 围栏配平（迁移自 bench）：每块围栏标记行数为偶数，即不在围栏内切断。
    func testEveryChunkHasBalancedFenceMarkers() {
        let sources = [
            backtickFenceDocument,
            tildeFenceDocument,
            makeMixedDocument(targetBytes: 20 * 1024),
        ]
        for source in sources {
            for chunk in FenceAwareChunker.split(source, targetBytes: 256) {
                XCTAssertEqual(fenceMarkerLineCount(in: chunk) % 2, 0)
            }
        }
    }

    /// “约 8 KiB”语义：除末块外每块都达到 targetBytes（末块可能不足）。
    func testNonFinalChunksReachTarget() {
        let target = 512
        let chunks = FenceAwareChunker.split(makeMixedDocument(targetBytes: 4 * 1024), targetBytes: target)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks.dropLast() {
            XCTAssertGreaterThanOrEqual(chunk.utf8.count, target)
        }
    }

    // MARK: - Fixtures

    /// 超过 64 字节、内含空行的 ``` 围栏，后跟结尾段落。
    private var backtickFenceDocument: String {
        "```swift\n"
            + (0..<6).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
            + "\n"  // 围栏内空行：围栏无感知的实现会在此切断
            + (0..<3).map { "print(value\($0))" }.joined(separator: "\n") + "\n"
            + "```\n"
            + "\n"
            + "结尾段落"
    }

    /// 超过 64 字节的 ~~~ 围栏，后跟结尾行。
    private var tildeFenceDocument: String {
        "~~~python\n"
            + String(repeating: "x = 1\n", count: 20)
            + "~~~\n"
            + "\n"
            + "结尾\n"
    }

    /// 确定性混合文档：标题/段落/表格/fenced code/列表循环节，直到达到目标字节数。
    private func makeMixedDocument(targetBytes: Int) -> String {
        let section = """
        ## 混合节

        段落含 **加粗**、`行内代码` 与 [链接](https://github.com/Dimon94/folbi)。

        | 列 A | 列 B |
        |:-----|-----:|
        | 甲 | 1 |

        ```swift
        func loadChildren() -> [FileNode] { [] }
        ```

        - 列表项一
        - 列表项二

        """
        var doc = ""
        while doc.utf8.count < targetBytes {
            doc += section
        }
        return doc
    }

    private func fenceMarkerLineCount(in chunk: String) -> Int {
        chunk.split(separator: "\n").count { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
        }
    }
}
