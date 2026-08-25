import XCTest
@testable import Folbi

/// 历史视图模块测试锚点：并排差异行解析的合同测试（#46）。
/// 三栏布局与选中联动走 app build / 手工 smoke（沿历史视图模块的既有验证面）。
final class GitHistoryViewTests: XCTestCase {
    /// 连续删除块与紧随的新增块按序配对同行；多出的一侧与空单元格配对；上下文行两侧同文。
    func testRowsPairDeletionsWithAdditionsAroundContext() {
        let patch = patchText([
            "diff --git a/笔记.txt b/笔记.txt",
            "index 1111111..2222222 100644",
            "--- a/笔记.txt",
            "+++ b/笔记.txt",
            "@@ -1,4 +1,4 @@",
            " 上下文",
            "-旧一",
            "-旧二",
            "+新一",
            "+新二",
            "+新三",
            " 尾行",
        ])

        XCTAssertEqual(SideBySideDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1,4 +1,4 @@"),
            .line(id: 1, old: .context("上下文"), new: .context("上下文")),
            .line(id: 2, old: .deleted("旧一"), new: .added("新一")),
            .line(id: 3, old: .deleted("旧二"), new: .added("新二")),
            .line(id: 4, old: .empty, new: .added("新三")),
            .line(id: 5, old: .context("尾行"), new: .context("尾行")),
        ])
    }

    /// 文件头行（diff --git / new file mode / index / --- / +++）不产生差异行；
    /// 根提交式全新增 patch 的所有内容行只进入右侧。
    func testRowsSkipFileHeadersAndRenderNewFileAsAdditions() {
        let patch = patchText([
            "diff --git a/新增.txt b/新增.txt",
            "new file mode 100644",
            "index 0000000..1111111",
            "--- /dev/null",
            "+++ b/新增.txt",
            "@@ -0,0 +1,2 @@",
            "+甲",
            "+乙",
        ])

        XCTAssertEqual(SideBySideDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -0,0 +1,2 @@"),
            .line(id: 1, old: .empty, new: .added("甲")),
            .line(id: 2, old: .empty, new: .added("乙")),
        ])
    }

    /// hunk 头切断配对：上一 hunk 末尾的删除不得与下一 hunk 开头的新增同行。
    func testRowsResetPairingAtHunkBoundary() {
        let patch = patchText([
            "diff --git a/f.txt b/f.txt",
            "index 1111111..2222222 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1 +0,0 @@",
            "-甲",
            "@@ -3,0 +4 @@",
            "+乙",
        ])

        XCTAssertEqual(SideBySideDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1 +0,0 @@"),
            .line(id: 1, old: .deleted("甲"), new: .empty),
            .hunkHeader(id: 2, text: "@@ -3,0 +4 @@"),
            .line(id: 3, old: .empty, new: .added("乙")),
        ])
    }

    /// `\` 开头标记行成为整宽标记行并切断配对；hunk 内无法识别的行按上下文行透传，不丢信息。
    func testRowsEmitNoNewlineMarkerAndPassThroughUnrecognizedLines() {
        let patch = patchText([
            "diff --git a/f.txt b/f.txt",
            "index 1111111..2222222 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1 +1 @@",
            "-旧",
            "\\ No newline at end of file",
            "+新",
            "\\ No newline at end of file",
            "无法识别行",
        ])

        XCTAssertEqual(SideBySideDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1 +1 @@"),
            .line(id: 1, old: .deleted("旧"), new: .empty),
            .noNewlineMarker(id: 2),
            .line(id: 3, old: .empty, new: .added("新")),
            .noNewlineMarker(id: 4),
            .line(id: 5, old: .context("无法识别行"), new: .context("无法识别行")),
        ])
    }

    /// 纯重命名/模式变更 patch 只有文件头，无差异行（视图据此显示「无文本差异」）。
    func testRowsForHeaderOnlyPatchIsEmpty() {
        let renamePatch = [
            "diff --git a/旧名.txt b/新名.txt",
            "similarity index 100%",
            "rename from 旧名.txt",
            "rename to 新名.txt",
        ].joined(separator: "\n")

        XCTAssertEqual(SideBySideDiffParser.rows(from: renamePatch), [])
        XCTAssertEqual(SideBySideDiffParser.rows(from: ""), [])
    }

    /// 大 patch 解析保持完整：一万对删除/新增全部成对，不丢行、不重行。
    func testRowsHandleLargePatchWithoutDroppingLines() {
        var lines = [
            "diff --git a/big.txt b/big.txt",
            "index 1111111..2222222 100644",
            "--- a/big.txt",
            "+++ b/big.txt",
            "@@ -1,10000 +1,10000 @@",
        ]
        for index in 0..<10_000 {
            lines.append("-旧行\(index)")
        }
        for index in 0..<10_000 {
            lines.append("+新行\(index)")
        }

        let rows = SideBySideDiffParser.rows(from: patchText(lines))

        XCTAssertEqual(rows.count, 10_001)
        XCTAssertEqual(rows.first, .hunkHeader(id: 0, text: "@@ -1,10000 +1,10000 @@"))
        XCTAssertEqual(rows.last, .line(id: 10_000, old: .deleted("旧行9999"), new: .added("新行9999")))
    }

    private func patchText(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}
