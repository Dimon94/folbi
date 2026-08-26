import SwiftUI

// COORD: repo://Folbi/InlineDiffView.swift
// INPUT: 单文件 unified patch 文本（GitHistoryModel.patchResult 的 content）。
// OUTPUT: InlineDiffParser（patch 文本 → 带双 gutter 行号的统一单列差异行）与 InlineDiffView（行级懒渲染）。
// POS: 历史视图模块的差异渲染单元；不读 GitHistoryModel，不写 .git 或工作区。
// TEST: repo://FolbiTests/GitHistoryViewTests.swift

/// 统一单列差异的一行：内容行各占一整行；hunk 头与「行尾无换行」标记为整宽行。
enum InlineDiffRow: Equatable, Identifiable {
    case line(id: Int, kind: Kind, oldLine: Int?, newLine: Int?, text: String)
    case hunkHeader(id: Int, text: String)
    case noNewlineMarker(id: Int)

    /// 行种类决定 gutter 哪一侧有号、符号列与底色。
    enum Kind: Equatable {
        case context
        case deleted
        case added
    }

    var id: Int {
        switch self {
        case .line(let id, _, _, _, _): id
        case .hunkHeader(let id, _): id
        case .noNewlineMarker(let id): id
        }
    }
}

/// unified patch 文本到统一单列差异行的纯解析。不启动进程，不读取文件。
enum InlineDiffParser {
    /// IN: GitPatch.text，单文件 unified patch；首个 hunk 头之前的文件头行不产生差异行。
    /// OUT: 行序列，id 从 0 递增；删除行与新增行按 patch 出现顺序各占一行，不配对；
    ///      行号自 hunk 头的 -/+ 起点逐行推进，上下文行两侧同号推进。
    /// FAIL: hunk 内无法识别的行按上下文行透传（只读查看，丢信息比误归类更糟）；
    ///      hunk 头无法解析时行号为 nil。
    /// TEST: repo://FolbiTests/GitHistoryViewTests.swift
    static func rows(from patchText: String) -> [InlineDiffRow] {
        var lines = patchText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }

        var rows: [InlineDiffRow] = []
        rows.reserveCapacity(lines.count)
        var oldLine: Int?
        var newLine: Int?
        var insideHunk = false

        for line in lines {
            if line.hasPrefix("@@") {
                rows.append(.hunkHeader(id: rows.count, text: String(line)))
                (oldLine, newLine) = hunkStartLines(of: line)
                insideHunk = true
                continue
            }
            guard insideHunk else { continue }

            switch line.first {
            case "-":
                rows.append(.line(
                    id: rows.count,
                    kind: .deleted,
                    oldLine: oldLine,
                    newLine: nil,
                    text: String(line.dropFirst())
                ))
                oldLine = oldLine.map { $0 + 1 }
            case "+":
                rows.append(.line(
                    id: rows.count,
                    kind: .added,
                    oldLine: nil,
                    newLine: newLine,
                    text: String(line.dropFirst())
                ))
                newLine = newLine.map { $0 + 1 }
            case "\\":
                rows.append(.noNewlineMarker(id: rows.count))
            case " ":
                rows.append(.line(
                    id: rows.count,
                    kind: .context,
                    oldLine: oldLine,
                    newLine: newLine,
                    text: String(line.dropFirst())
                ))
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            default:
                rows.append(.line(
                    id: rows.count,
                    kind: .context,
                    oldLine: oldLine,
                    newLine: newLine,
                    text: String(line)
                ))
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            }
        }
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

/// 差异栏的统一单列渲染。行级 LazyVStack 懒渲染：首帧只物化可视行，行视图与文本测量随滚动渐进；
/// 内容超宽时双轴滚动（单一 ScrollView）。
/// patch 上限 1 MiB（repo://Folbi/GitHistoryModel.swift），body 内的单次线性解析开销有界。
/// Equatable：视图唯一输入是 patchText，模型无关发布（如提交列表翻页）不触发重解析。
struct InlineDiffView: View, Equatable {
    /// 单文件 patch 文本（GitPatch.text）。
    let patchText: String

    var body: some View {
        let rows = InlineDiffParser.rows(from: patchText)
        if rows.isEmpty {
            // 纯重命名、纯模式变更等无 hunk 的 patch。
            HistoryColumnPlaceholder(message: "无文本差异", systemImage: "doc.text")
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            InlineDiffRowView(row: row, minWidth: proxy.size.width)
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
            }
        }
    }
}

private struct InlineDiffRowView: View {
    let row: InlineDiffRow
    let minWidth: CGFloat

    var body: some View {
        switch row {
        case .hunkHeader(_, let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
        case .noNewlineMarker:
            Text("行尾无换行符")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
        case .line(_, let kind, let oldLine, let newLine, let text):
            HStack(spacing: 0) {
                gutter(oldLine, kind: kind)
                gutter(newLine, kind: kind)
                Text(sign(for: kind))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(signColor(for: kind))
                    .frame(width: 14)
                    .frame(maxHeight: .infinity)
                    .background(contentBackground(for: kind))
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .background(contentBackground(for: kind))
            }
            .frame(minWidth: minWidth, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// 行号 gutter 固定宽：五位数以内行号完整显示（超出时缩小一档而非截断），各行 gutter 垂直对齐。
    private static let gutterWidth: CGFloat = 44

    private func gutter(_ line: Int?, kind: InlineDiffRow.Kind) -> some View {
        Text(line.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.trailing, 6)
            .frame(width: Self.gutterWidth, alignment: .trailing)
            .frame(maxHeight: .infinity)
            .background(gutterBackground(for: kind, hasLine: line != nil))
    }

    private func sign(for kind: InlineDiffRow.Kind) -> String {
        switch kind {
        case .context: return " "
        case .deleted: return "-"
        case .added: return "+"
        }
    }

    private func signColor(for kind: InlineDiffRow.Kind) -> Color {
        switch kind {
        case .context: return .secondary
        case .deleted: return Color(nsColor: .systemRed)
        case .added: return Color(nsColor: .systemGreen)
        }
    }

    private func tintColor(for kind: InlineDiffRow.Kind) -> Color? {
        switch kind {
        case .deleted: return Color(nsColor: .systemRed)
        case .added: return Color(nsColor: .systemGreen)
        case .context: return nil
        }
    }

    private func contentBackground(for kind: InlineDiffRow.Kind) -> Color {
        if let tint = tintColor(for: kind) { return tint.opacity(0.15) }
        return .clear
    }

    private func gutterBackground(for kind: InlineDiffRow.Kind, hasLine: Bool) -> Color {
        if hasLine, let tint = tintColor(for: kind) { return tint.opacity(0.25) }
        return Color.secondary.opacity(0.08)
    }
}
