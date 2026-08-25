import SwiftUI
import XCTest
@testable import Folbi

/// 历史视图模块测试锚点：并排差异行解析的合同测试（#46，#47 增加行号）与列表选中绑定的行为测试（#47）。
/// 三栏布局与视觉打磨走 app build / 手工 smoke（沿历史视图模块的既有验证面）。
final class GitHistoryViewTests: XCTestCase {
    /// 连续删除块与紧随的新增块按序配对同行；多出的一侧与空单元格配对；上下文行两侧同文。
    /// 行号自 hunk 头起点逐行推进：旧侧用 - 起点，新侧用 + 起点。
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
            .line(id: 1, old: .context(line: 1, text: "上下文"), new: .context(line: 1, text: "上下文")),
            .line(id: 2, old: .deleted(line: 2, text: "旧一"), new: .added(line: 2, text: "新一")),
            .line(id: 3, old: .deleted(line: 3, text: "旧二"), new: .added(line: 3, text: "新二")),
            .line(id: 4, old: .empty, new: .added(line: 4, text: "新三")),
            .line(id: 5, old: .context(line: 4, text: "尾行"), new: .context(line: 5, text: "尾行")),
        ])
    }

    /// 文件头行（diff --git / new file mode / index / --- / +++）不产生差异行；
    /// 根提交式全新增 patch 的所有内容行只进入右侧，行号从 + 起点开始。
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
            .line(id: 1, old: .empty, new: .added(line: 1, text: "甲")),
            .line(id: 2, old: .empty, new: .added(line: 2, text: "乙")),
        ])
    }

    /// hunk 头切断配对：上一 hunk 末尾的删除不得与下一 hunk 开头的新增同行；
    /// 行号在每个 hunk 头按各自起点重启。
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
            .line(id: 1, old: .deleted(line: 1, text: "甲"), new: .empty),
            .hunkHeader(id: 2, text: "@@ -3,0 +4 @@"),
            .line(id: 3, old: .empty, new: .added(line: 4, text: "乙")),
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
            .line(id: 1, old: .deleted(line: 1, text: "旧"), new: .empty),
            .noNewlineMarker(id: 2),
            .line(id: 3, old: .empty, new: .added(line: 1, text: "新")),
            .noNewlineMarker(id: 4),
            .line(id: 5, old: .context(line: 2, text: "无法识别行"), new: .context(line: 2, text: "无法识别行")),
        ])
    }

    /// hunk 头无法解析时行号为 nil（gutter 留空比误标更糟）；行内容与配对照常。
    func testRowsLeaveLineNumbersBlankWhenHunkHeaderUnparseable() {
        let patch = patchText([
            "diff --git a/f.txt b/f.txt",
            "index 1111111..2222222 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ 无法解析 @@",
            " 甲",
            "-乙",
        ])

        XCTAssertEqual(SideBySideDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ 无法解析 @@"),
            .line(id: 1, old: .context(line: nil, text: "甲"), new: .context(line: nil, text: "甲")),
            .line(id: 2, old: .deleted(line: nil, text: "乙"), new: .empty),
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

    /// 大 patch 解析保持完整：一万对删除/新增全部成对，不丢行、不重行，行号连续推进。
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
        XCTAssertEqual(rows.last, .line(
            id: 10_000,
            old: .deleted(line: 10_000, text: "旧行9999"),
            new: .added(line: 10_000, text: "新行9999")
        ))
    }

    private func patchText(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}

/// 三栏列表选中绑定的行为测试（#47）：List 原生选中（点选/方向键）经绑定转发给 GitHistoryModel。
/// 临时仓库 fixture 归 repo://FolbiTests/GitTestSupport.swift。
@MainActor
final class GitHistoryViewSelectionTests: XCTestCase {
    /// 提交绑定：写入 hash 选中该提交并加载变更文件；写入 nil 或列表中不存在的 hash 取消选中并清空。
    func testCommitSelectionBindingDrivesModelSelection() throws {
        let repository = try GitTestSupport.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try GitTestSupport.commitText("one\n", path: "note.txt", subject: "first", in: repository)
        try GitTestSupport.commitText("two\n", path: "note.txt", subject: "second", in: repository)

        let model = try XCTUnwrap(GitHistoryModel(rootFolderURL: repository))
        model.enterHistory()
        let binding = GitHistoryView.commitSelectionBinding(model: model)
        XCTAssertNil(binding.wrappedValue)

        let second = try XCTUnwrap(model.commits.first { $0.subject == "second" })
        binding.wrappedValue = second.hash
        XCTAssertEqual(model.selectedCommit, second)
        XCTAssertEqual(model.changedFiles.map(\.path), ["note.txt"])

        // 列表翻页重置等场景可能写入已不在列表中的 hash：按取消选中处理，不崩溃、不滞留旧选中。
        binding.wrappedValue = "0" + String(repeating: "0", count: 39)
        XCTAssertNil(model.selectedCommit)
        XCTAssertEqual(model.changedFiles, [])

        binding.wrappedValue = second.hash
        binding.wrappedValue = nil
        XCTAssertNil(model.selectedCommit)
        XCTAssertEqual(model.changedFiles, [])
    }

    /// 文件绑定：写入 path 选中该文件并加载其 patch；写入 nil 清空选中与 patch。
    func testFileSelectionBindingDrivesModelSelection() throws {
        let repository = try GitTestSupport.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try GitTestSupport.commitText("one\n", path: "note.txt", subject: "first", in: repository)
        try GitTestSupport.commitText("two\n", path: "other.txt", subject: "second", in: repository)

        let model = try XCTUnwrap(GitHistoryModel(rootFolderURL: repository))
        model.enterHistory()
        model.selectCommit(try XCTUnwrap(model.commits.first { $0.subject == "second" }))
        let binding = GitHistoryView.fileSelectionBinding(model: model)
        XCTAssertNil(binding.wrappedValue)

        binding.wrappedValue = "other.txt"
        XCTAssertEqual(model.selectedFile?.path, "other.txt")
        guard case .content = model.patchResult else {
            return XCTFail("选中文件应加载该文件 patch")
        }

        binding.wrappedValue = nil
        XCTAssertNil(model.selectedFile)
        XCTAssertNil(model.patchResult)
    }
}
