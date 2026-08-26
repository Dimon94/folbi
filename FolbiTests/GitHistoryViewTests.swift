import SwiftUI
import XCTest
@testable import Folbi

/// 历史视图模块测试锚点：统一单列内联差异行解析的合同测试与列表选中绑定的行为测试。
/// 三栏布局与视觉打磨走 app build / 手工 smoke（沿历史视图模块的既有验证面）。
final class GitHistoryViewTests: XCTestCase {
    /// 删除行与新增行按 patch 顺序各占一行，不配对到同一行；上下文行同时带旧/新行号。
    /// 行号自 hunk 头起点逐行推进：删除推旧侧，新增推新侧。
    func testRowsEmitDeletionsThenAdditionsSequentially() {
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

        XCTAssertEqual(InlineDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1,4 +1,4 @@"),
            .line(id: 1, kind: .context, oldLine: 1, newLine: 1, text: "上下文"),
            .line(id: 2, kind: .deleted, oldLine: 2, newLine: nil, text: "旧一"),
            .line(id: 3, kind: .deleted, oldLine: 3, newLine: nil, text: "旧二"),
            .line(id: 4, kind: .added, oldLine: nil, newLine: 2, text: "新一"),
            .line(id: 5, kind: .added, oldLine: nil, newLine: 3, text: "新二"),
            .line(id: 6, kind: .added, oldLine: nil, newLine: 4, text: "新三"),
            .line(id: 7, kind: .context, oldLine: 4, newLine: 5, text: "尾行"),
        ])
    }

    /// 文件头行（diff --git / new file mode / index / --- / +++）不产生差异行；
    /// 根提交式全新增 patch 的内容行全是新增行，行号从 + 起点开始。
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

        XCTAssertEqual(InlineDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -0,0 +1,2 @@"),
            .line(id: 1, kind: .added, oldLine: nil, newLine: 1, text: "甲"),
            .line(id: 2, kind: .added, oldLine: nil, newLine: 2, text: "乙"),
        ])
    }

    /// hunk 头重启行号：上一 hunk 末尾的删除不与下一 hunk 开头的新增混号。
    func testRowsRestartLineNumbersAtHunkBoundary() {
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

        XCTAssertEqual(InlineDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1 +0,0 @@"),
            .line(id: 1, kind: .deleted, oldLine: 1, newLine: nil, text: "甲"),
            .hunkHeader(id: 2, text: "@@ -3,0 +4 @@"),
            .line(id: 3, kind: .added, oldLine: nil, newLine: 4, text: "乙"),
        ])
    }

    /// `\` 开头标记行成为整宽标记行，不推进行号；hunk 内无法识别的行按上下文行透传，不丢信息。
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

        XCTAssertEqual(InlineDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ -1 +1 @@"),
            .line(id: 1, kind: .deleted, oldLine: 1, newLine: nil, text: "旧"),
            .noNewlineMarker(id: 2),
            .line(id: 3, kind: .added, oldLine: nil, newLine: 1, text: "新"),
            .noNewlineMarker(id: 4),
            .line(id: 5, kind: .context, oldLine: 2, newLine: 2, text: "无法识别行"),
        ])
    }

    /// hunk 头无法解析时行号为 nil（gutter 留空比误标更糟）；行种类照常。
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

        XCTAssertEqual(InlineDiffParser.rows(from: patch), [
            .hunkHeader(id: 0, text: "@@ 无法解析 @@"),
            .line(id: 1, kind: .context, oldLine: nil, newLine: nil, text: "甲"),
            .line(id: 2, kind: .deleted, oldLine: nil, newLine: nil, text: "乙"),
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

        XCTAssertEqual(InlineDiffParser.rows(from: renamePatch), [])
        XCTAssertEqual(InlineDiffParser.rows(from: ""), [])
    }

    /// 大 patch 解析保持完整：一万条删除与一万条新增各占一行，不丢行、不重行。
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

        let rows = InlineDiffParser.rows(from: patchText(lines))

        XCTAssertEqual(rows.count, 20_001)
        XCTAssertEqual(rows.first, .hunkHeader(id: 0, text: "@@ -1,10000 +1,10000 @@"))
        XCTAssertEqual(rows[1], .line(id: 1, kind: .deleted, oldLine: 1, newLine: nil, text: "旧行0"))
        XCTAssertEqual(rows.last, .line(
            id: 20_000,
            kind: .added,
            oldLine: nil,
            newLine: 10_000,
            text: "新行9999"
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
