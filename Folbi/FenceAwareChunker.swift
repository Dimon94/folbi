import Foundation

/// Fence 感知分块器：把 Markdown 源文本按顶层块边界切成约 `targetBytes` 的块，供分块懒渲染使用。
/// 纯函数，不触碰磁盘与编辑缓冲区（不变量：WorkspaceModel 是状态与磁盘副作用的唯一 owner）。
///
/// 合同（由 FenceAwareChunkerTests 钉住）：
/// - 重组恒等：`split(source).joined() == source`，按原始字节切片、不增删字符。
/// - 围栏配平：不在代码围栏内切断；围栏块只能整体留在同一块内，块可因此超过 targetBytes。
///   围栏识别取 CommonMark 子集：前导空格 ≤ 3；同一字符（` 或 ~）连续 ≥ 3 个开围栏；
///   闭合行要求字符相同、run 长度 ≥ 开围栏、其后只剩空白（闭合行不允许 info string）。
/// - 切点：仅在空行处、且当前块已达 targetBytes 时才切；松散列表可能在空行处分为两块（spec #10 已接受）。
enum FenceAwareChunker {
    /// 默认 8 KiB（容量默认值，L5）：#8 实测 release 构建下 8 KiB 混合块单次构建约 250 ms，
    /// 分块懒渲染首帧与文档大小解耦；调整前需重测进入预览首帧与滚动顿挫。
    static func split(_ source: String, targetBytes: Int = 8 * 1024) -> [String] {
        var chunks: [String] = []
        var current = ""
        var openFence: (marker: Character, length: Int)?

        var lineStart = source.startIndex
        while lineStart < source.endIndex {
            let newline = source[lineStart...].firstIndex(of: "\n")
            let lineEnd = newline ?? source.endIndex
            let pieceEnd = newline.map { source.index(after: $0) } ?? source.endIndex
            let line = source[lineStart..<lineEnd]

            let indent = line.prefix(while: { $0 == " " }).count
            if indent <= 3, let marker = line.dropFirst(indent).first, marker == "`" || marker == "~" {
                let rest = line.dropFirst(indent)
                let runLength = rest.prefix(while: { $0 == marker }).count
                if runLength >= 3 {
                    if let fence = openFence {
                        if marker == fence.marker, runLength >= fence.length,
                           rest.dropFirst(runLength).allSatisfy({ $0 == " " || $0 == "\t" }) {
                            openFence = nil
                        }
                    } else {
                        openFence = (marker, runLength)
                    }
                }
            }

            current += source[lineStart..<pieceEnd]
            if openFence == nil, line.isEmpty, current.utf8.count >= targetBytes {
                chunks.append(current)
                current = ""
            }
            lineStart = pieceEnd
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
