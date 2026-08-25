import SwiftUI

// COORD: repo://Folbi/SideBySideDiffView.swift
// INPUT: 单文件 unified patch 文本（GitHistoryModel.patchResult 的 content）。
// OUTPUT: SideBySideDiffParser（patch 文本 → 并排差异行）与 SideBySideDiffView（行级懒渲染）。
// POS: 历史视图模块的差异渲染单元；不读 GitHistoryModel，不写 .git 或工作区。
// TEST: repo://FolbiTests/GitHistoryViewTests.swift

/// 并排差异的一行：内容行左右各一个单元格；hunk 头与「行尾无换行」标记为整宽行。
enum SideBySideDiffRow: Equatable, Identifiable {
    case line(id: Int, old: Cell, new: Cell)
    case hunkHeader(id: Int, text: String)
    case noNewlineMarker(id: Int)

    /// 内容行一侧的单元格。空单元格出现在删除行右侧或新增行左侧。
    enum Cell: Equatable {
        case empty
        case context(String)
        case deleted(String)
        case added(String)
    }

    var id: Int {
        switch self {
        case .line(let id, _, _): id
        case .hunkHeader(let id, _): id
        case .noNewlineMarker(let id): id
        }
    }
}

/// unified patch 文本到并排差异行的纯解析。不启动进程，不读取文件。
enum SideBySideDiffParser {
    /// IN: GitPatch.text，单文件 unified patch；首个 hunk 头之前的文件头行不产生差异行。
    /// OUT: 行序列，id 从 0 递增；连续删除块与紧随的新增块按序配对同行，多出的一侧与空单元格配对。
    /// FAIL: hunk 内无法识别的行按上下文行透传（只读查看，丢信息比误归类更糟）。
    /// TEST: repo://FolbiTests/GitHistoryViewTests.swift
    static func rows(from patchText: String) -> [SideBySideDiffRow] {
        var lines = patchText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }

        var rows: [SideBySideDiffRow] = []
        rows.reserveCapacity(lines.count)
        var deletions: [Substring] = []
        var additions: [Substring] = []
        var insideHunk = false

        /// 上下文行、hunk 头、标记行与文本末尾都会切断删除/新增配对。
        func flushPairs() {
            let pairCount = min(deletions.count, additions.count)
            for index in 0..<pairCount {
                rows.append(.line(
                    id: rows.count,
                    old: .deleted(String(deletions[index])),
                    new: .added(String(additions[index]))
                ))
            }
            for deletion in deletions.dropFirst(pairCount) {
                rows.append(.line(id: rows.count, old: .deleted(String(deletion)), new: .empty))
            }
            for addition in additions.dropFirst(pairCount) {
                rows.append(.line(id: rows.count, old: .empty, new: .added(String(addition))))
            }
            deletions.removeAll()
            additions.removeAll()
        }

        for line in lines {
            if line.hasPrefix("@@") {
                flushPairs()
                rows.append(.hunkHeader(id: rows.count, text: String(line)))
                insideHunk = true
                continue
            }
            guard insideHunk else { continue }

            switch line.first {
            case "-":
                deletions.append(line.dropFirst())
            case "+":
                additions.append(line.dropFirst())
            case "\\":
                flushPairs()
                rows.append(.noNewlineMarker(id: rows.count))
            case " ":
                flushPairs()
                let text = String(line.dropFirst())
                rows.append(.line(id: rows.count, old: .context(text), new: .context(text)))
            default:
                flushPairs()
                rows.append(.line(id: rows.count, old: .context(String(line)), new: .context(String(line))))
            }
        }
        flushPairs()
        return rows
    }
}

/// 差异栏的并排渲染。行级 LazyVStack 懒渲染：首帧只物化可视行，行视图与文本测量随滚动渐进；
/// 内容超宽时双轴滚动，不降级为统一单列。patch 上限 1 MiB（repo://Folbi/GitHistoryModel.swift），
/// body 内的单次线性解析开销有界。
/// Equatable：视图唯一输入是 patchText，模型无关发布（如提交列表翻页）不触发重解析。
struct SideBySideDiffView: View, Equatable {
    /// 单文件 patch 文本（GitPatch.text）。
    let patchText: String

    var body: some View {
        let rows = SideBySideDiffParser.rows(from: patchText)
        if rows.isEmpty {
            // 纯重命名、纯模式变更等无 hunk 的 patch。
            HistoryColumnPlaceholder(message: "无文本差异", systemImage: "doc.text")
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            SideBySideDiffRowView(
                                row: row,
                                columnMinWidth: Self.columnMinWidth(forViewportWidth: proxy.size.width)
                            )
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
            }
        }
    }

    /// 每个单元格至少半栏宽（减去行内 Divider 的 1pt），行短时并排结构仍铺满视口。
    static func columnMinWidth(forViewportWidth width: CGFloat) -> CGFloat {
        max((width - 1) / 2, 160)
    }
}

private struct SideBySideDiffRowView: View {
    let row: SideBySideDiffRow
    let columnMinWidth: CGFloat

    var body: some View {
        switch row {
        case .hunkHeader(_, let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: columnMinWidth * 2 + 1, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
        case .noNewlineMarker:
            Text("行尾无换行符")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: columnMinWidth * 2 + 1, alignment: .leading)
        case .line(_, let old, let new):
            HStack(spacing: 0) {
                SideBySideDiffCellView(cell: old, columnMinWidth: columnMinWidth)
                Divider()
                SideBySideDiffCellView(cell: new, columnMinWidth: columnMinWidth)
            }
        }
    }
}

private struct SideBySideDiffCellView: View {
    let cell: SideBySideDiffRow.Cell
    let columnMinWidth: CGFloat

    var body: some View {
        Text(displayText)
            .font(.system(size: 13, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(minWidth: columnMinWidth, alignment: .leading)
            .background(highlight ?? Color.clear)
    }

    /// 空文本替换为空格，保证空行与有内容行同高，左右两侧行号对齐不错位。
    private var displayText: String {
        switch cell {
        case .empty:
            return " "
        case .context(let text), .deleted(let text), .added(let text):
            return text.isEmpty ? " " : text
        }
    }

    private var highlight: Color? {
        switch cell {
        case .deleted:
            return Color(nsColor: .systemRed).opacity(0.15)
        case .added:
            return Color(nsColor: .systemGreen).opacity(0.15)
        case .empty, .context:
            return nil
        }
    }
}
