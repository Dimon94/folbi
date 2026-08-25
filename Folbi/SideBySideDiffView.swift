import SwiftUI

// COORD: repo://Folbi/SideBySideDiffView.swift
// INPUT: 单文件 unified patch 文本（GitHistoryModel.patchResult 的 content）。
// OUTPUT: SideBySideDiffParser（patch 文本 → 带双栏行号的并排差异行）与 SideBySideDiffView（行级懒渲染）。
// POS: 历史视图模块的差异渲染单元；不读 GitHistoryModel，不写 .git 或工作区。
// TEST: repo://FolbiTests/GitHistoryViewTests.swift

/// 并排差异的一行：内容行左右各一个单元格；hunk 头与「行尾无换行」标记为整宽行。
enum SideBySideDiffRow: Equatable, Identifiable {
    case line(id: Int, old: Cell, new: Cell)
    case hunkHeader(id: Int, text: String)
    case noNewlineMarker(id: Int)

    /// 内容行一侧的单元格。空单元格出现在删除行右侧或新增行左侧。
    /// line 为该侧在对应文件中的行号；hunk 头无法解析时为 nil，gutter 留空（留空比误标更糟）。
    enum Cell: Equatable {
        case empty
        case context(line: Int?, text: String)
        case deleted(line: Int?, text: String)
        case added(line: Int?, text: String)
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
    /// OUT: 行序列，id 从 0 递增；连续删除块与紧随的新增块按序配对同行，多出的一侧与空单元格配对；
    ///      行号自 hunk 头的 -/+ 起点逐行推进，上下文行两侧同号推进。
    /// FAIL: hunk 内无法识别的行按上下文行透传（只读查看，丢信息比误归类更糟）；
    ///      hunk 头无法解析时行号为 nil。
    /// TEST: repo://FolbiTests/GitHistoryViewTests.swift
    static func rows(from patchText: String) -> [SideBySideDiffRow] {
        var lines = patchText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }

        var rows: [SideBySideDiffRow] = []
        rows.reserveCapacity(lines.count)
        var deletions: [(line: Int?, text: Substring)] = []
        var additions: [(line: Int?, text: Substring)] = []
        var oldLine: Int?
        var newLine: Int?
        var insideHunk = false

        /// 上下文行、hunk 头、标记行与文本末尾都会切断删除/新增配对。
        func flushPairs() {
            let pairCount = min(deletions.count, additions.count)
            for index in 0..<pairCount {
                rows.append(.line(
                    id: rows.count,
                    old: .deleted(line: deletions[index].line, text: String(deletions[index].text)),
                    new: .added(line: additions[index].line, text: String(additions[index].text))
                ))
            }
            for deletion in deletions.dropFirst(pairCount) {
                rows.append(.line(
                    id: rows.count,
                    old: .deleted(line: deletion.line, text: String(deletion.text)),
                    new: .empty
                ))
            }
            for addition in additions.dropFirst(pairCount) {
                rows.append(.line(
                    id: rows.count,
                    old: .empty,
                    new: .added(line: addition.line, text: String(addition.text))
                ))
            }
            deletions.removeAll()
            additions.removeAll()
        }

        /// 上下文语义：两侧同文，各自推进行号。无法识别的行也走这里（透传）。
        func appendContextLine(_ text: String) {
            flushPairs()
            rows.append(.line(
                id: rows.count,
                old: .context(line: oldLine, text: text),
                new: .context(line: newLine, text: text)
            ))
            oldLine = oldLine.map { $0 + 1 }
            newLine = newLine.map { $0 + 1 }
        }

        for line in lines {
            if line.hasPrefix("@@") {
                flushPairs()
                rows.append(.hunkHeader(id: rows.count, text: String(line)))
                (oldLine, newLine) = hunkStartLines(of: line)
                insideHunk = true
                continue
            }
            guard insideHunk else { continue }

            switch line.first {
            case "-":
                deletions.append((oldLine, line.dropFirst()))
                oldLine = oldLine.map { $0 + 1 }
            case "+":
                additions.append((newLine, line.dropFirst()))
                newLine = newLine.map { $0 + 1 }
            case "\\":
                flushPairs()
                rows.append(.noNewlineMarker(id: rows.count))
            case " ":
                appendContextLine(String(line.dropFirst()))
            default:
                appendContextLine(String(line))
            }
        }
        flushPairs()
        return rows
    }

    /// 从 hunk 头解析两侧起始行号：「@@ -旧起点[,行数] +新起点[,行数] @@」，行数可省略。
    /// 无法解析返回双 nil，该 hunk 的行 gutter 留空。
    private static func hunkStartLines(of header: Substring) -> (old: Int?, new: Int?) {
        let fields = header.split(separator: " ")
        guard fields.count >= 3 else { return (nil, nil) }
        return (startLine(of: fields[1], prefix: "-"), startLine(of: fields[2], prefix: "+"))
    }

    private static func startLine(of field: Substring, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        return Int(field.dropFirst().prefix(while: { $0.isNumber }))
    }
}

/// 差异栏的并排渲染。行级 LazyVStack 懒渲染：首帧只物化可视行，行视图与文本测量随滚动渐进；
/// 内容超宽时双轴滚动（单一 ScrollView，左右栏天然同步），不降级为统一单列。
/// patch 上限 1 MiB（repo://Folbi/GitHistoryModel.swift），body 内的单次线性解析开销有界。
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
                .frame(minWidth: columnMinWidth * 2 + 1, maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
        case .noNewlineMarker:
            Text("行尾无换行符")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: columnMinWidth * 2 + 1, maxWidth: .infinity, alignment: .leading)
        case .line(_, let old, let new):
            HStack(spacing: 0) {
                SideBySideDiffCellView(cell: old, columnMinWidth: columnMinWidth)
                Divider()
                SideBySideDiffCellView(cell: new, columnMinWidth: columnMinWidth)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SideBySideDiffCellView: View {
    let cell: SideBySideDiffRow.Cell
    let columnMinWidth: CGFloat

    /// 行号 gutter 固定宽：五位数以内行号完整显示（超出时缩小一档而非截断），各行 gutter 垂直对齐。
    private static let gutterWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Text(lineNumberText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.trailing, 6)
                .frame(width: Self.gutterWidth, alignment: .trailing)
                .frame(maxHeight: .infinity)
                .background(gutterBackground)
            Text(displayText)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .frame(maxHeight: .infinity, alignment: .leading)
        }
        .frame(minWidth: columnMinWidth, alignment: .leading)
        .background(contentBackground)
    }

    /// 空文本替换为空格，保证空行与有内容行同高，左右两侧行号对齐不错位。
    private var displayText: String {
        switch cell {
        case .empty:
            return " "
        case .context(_, let text), .deleted(_, let text), .added(_, let text):
            return text.isEmpty ? " " : text
        }
    }

    private var lineNumberText: String {
        switch cell {
        case .empty:
            return ""
        case .context(let line, _), .deleted(let line, _), .added(let line, _):
            return line.map(String.init) ?? ""
        }
    }

    /// 删除/新增行的底色来源；上下文与空单元格无底色。
    private var tintColor: Color? {
        switch cell {
        case .deleted:
            return Color(nsColor: .systemRed)
        case .added:
            return Color(nsColor: .systemGreen)
        case .empty, .context:
            return nil
        }
    }

    /// 内容区背景：变更行浅色着色；空单元格（对侧无对应行）淡灰表示缺失。
    private var contentBackground: Color {
        if let tintColor { return tintColor.opacity(0.15) }
        if case .empty = cell { return Color.secondary.opacity(0.05) }
        return .clear
    }

    /// gutter 背景：变更行同色系加深一档；其余统一浅灰，保持行号列视觉连续。
    private var gutterBackground: Color {
        if let tintColor { return tintColor.opacity(0.25) }
        return Color.secondary.opacity(0.08)
    }
}
