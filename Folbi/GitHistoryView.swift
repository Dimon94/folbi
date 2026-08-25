import AppKit
import SwiftUI

// COORD: repo://Folbi/GitHistoryView.swift
// INPUT: GitHistoryModel 的只读可观察状态。
// OUTPUT: 三栏历史视图（HSplitView：提交列表｜变更文件｜差异）、List 原生选中联动、占位与错误呈现。
// POS: 历史视图模块；只读 GitHistoryModel，不写 .git 或工作区。剪贴板写入只来自右键菜单动作。
// TEST: repo://FolbiTests/GitHistoryViewTests.swift

/// 提交列表滚动分页的触发锚点。末项出现时加载下一页，直到历史末尾。
private struct LoadMoreAnchor: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear(perform: action)
    }
}

/// 栏内居中占位：图标加一行说明。模块内共用（本文件与 repo://Folbi/SideBySideDiffView.swift）。
struct HistoryColumnPlaceholder: View {
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 三栏历史视图：提交列表｜变更文件｜差异。
/// 选中提交加载变更文件、选中文件按需加载该文件 patch，联动语义归 GitHistoryModel（#44）；
/// 本视图只做呈现与动作转发。
struct GitHistoryView: View {
    @ObservedObject var model: GitHistoryModel

    /// 列表日期格式：短日期加短时间，配合等宽数字在提交行行尾右对齐（#47 排版打磨）。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        // HSplitView 承担分隔线拖拽与窗口缩放分配（macOS 三栏原生惯例）；
        // 三栏最小宽度之和 680pt 低于窗口最小宽度 720pt，最小窗口下也不互相挤压。
        HSplitView {
            commitListColumn
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400, maxHeight: .infinity)
            changedFilesColumn
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 360, maxHeight: .infinity)
            diffColumn
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 提交列表栏

    private var commitListColumn: some View {
        VStack(spacing: 0) {
            if let commitsError = model.commitsError {
                inlineError(commitsError)
            }

            if model.commits.isEmpty && model.commitsError == nil {
                HistoryColumnPlaceholder(message: "暂无提交", systemImage: "clock")
            } else {
                // List 承担原生选中态、方向键导航与焦点环；选中经绑定转发给 GitHistoryModel。
                List(selection: Self.commitSelectionBinding(model: model)) {
                    ForEach(model.commits, id: \.hash) { commit in
                        commitRow(commit)
                            .tag(commit.hash)
                    }
                    if model.hasMoreCommits {
                        LoadMoreAnchor {
                            model.loadNextPage()
                        }
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("提交列表")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 提交行排版：主题一行、完整 hash 一行（过窄时中间截断，tooltip 与右键菜单可取完整值）、
    /// 作者名加右对齐等宽数字日期一行。长 hash/作者/主题均截断，不破坏行布局。
    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
                .font(.body)
                .lineLimit(1)
            Text(commit.hash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text(commit.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.dateFormatter.string(from: commit.authorDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(commit.hash)
        .contextMenu {
            Button("复制完整 Hash") {
                copyToPasteboard(commit.hash)
            }
        }
    }

    // MARK: - 变更文件栏

    private var changedFilesColumn: some View {
        VStack(spacing: 0) {
            if let changedFilesError = model.changedFilesError {
                inlineError(changedFilesError)
            }

            if model.selectedCommit == nil {
                HistoryColumnPlaceholder(message: "选中提交后显示", systemImage: "doc.text")
            } else if model.changedFiles.isEmpty {
                // diff 执行失败时横幅已承担占位，正文留空；
                // 空输出即合并提交（#44 模型语义，spec #42 §5）。
                if model.changedFilesError == nil {
                    HistoryColumnPlaceholder(message: "合并提交，不展示差异", systemImage: "arrow.triangle.merge")
                }
            } else {
                List(selection: Self.fileSelectionBinding(model: model)) {
                    ForEach(model.changedFiles, id: \.path) { file in
                        fileRow(file)
                            .tag(file.path)
                    }
                }
                .accessibilityLabel("变更文件")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(_ file: GitFileChange) -> some View {
        HStack(spacing: 6) {
            statusBadge(file.status)
            Text(displayPath(of: file))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(displayPath(of: file))
        .contextMenu {
            Button("复制文件路径") {
                copyToPasteboard(file.path)
            }
        }
    }

    /// 重命名与复制显示「旧路径 → 新路径」，其余显示路径本身。
    private func displayPath(of file: GitFileChange) -> String {
        if let previousPath = file.previousPath {
            return "\(previousPath) → \(file.path)"
        }
        return file.path
    }

    /// 状态徽标：固定宽度使各行路径起始位置垂直对齐。
    private func statusBadge(_ status: GitFileChange.Status) -> some View {
        let label: String
        let color: Color
        switch status {
        case .added:
            label = "新增"
            color = Color(nsColor: .systemGreen)
        case .modified:
            label = "修改"
            color = Color(nsColor: .systemOrange)
        case .deleted:
            label = "删除"
            color = Color(nsColor: .systemRed)
        case .renamed:
            label = "重命名"
            color = Color(nsColor: .systemBlue)
        case .copied:
            label = "复制"
            color = Color(nsColor: .systemTeal)
        }
        return Text(label)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(width: 44)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 差异栏

    private var diffColumn: some View {
        VStack(spacing: 0) {
            diffContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 差异栏状态裁决。占位文案锁定于 spec #42 §4/§5/§7；失败只加内联横幅，不弹 alert。
    @ViewBuilder
    private var diffContent: some View {
        if model.selectedCommit == nil {
            HistoryColumnPlaceholder(message: "选中提交后显示", systemImage: "doc.text")
        } else if model.selectedFile == nil {
            if model.patchResult == .mergeCommit {
                HistoryColumnPlaceholder(message: "合并提交，不展示差异", systemImage: "arrow.triangle.merge")
            } else {
                HistoryColumnPlaceholder(message: "选中文件后显示", systemImage: "doc.text")
            }
        } else {
            switch model.patchResult {
            case .content(let text):
                selectedFileDiff(text)
            case .exceedsLimit:
                HistoryColumnPlaceholder(message: "差异超过 1 MiB 上限，无法显示。", systemImage: "exclamationmark.triangle")
            case .binary:
                HistoryColumnPlaceholder(message: "二进制文件，无文本差异", systemImage: "doc.zipper")
            case .failure(let error, let retainedContent):
                inlineError(error)
                if let retainedContent {
                    SideBySideDiffView(patchText: retainedContent)
                        .equatable()
                }
            case .mergeCommit:
                // 防御分支：合并提交无变更文件可选，正常到不了这里。
                HistoryColumnPlaceholder(message: "合并提交，不展示差异", systemImage: "arrow.triangle.merge")
            case nil:
                // 防御分支：选中文件后模型同步给出 patchResult，不会停留于此。
                HistoryColumnPlaceholder(message: "选中文件后显示", systemImage: "doc.text")
            }
        }
    }

    private func selectedFileDiff(_ patchText: String) -> some View {
        VStack(spacing: 0) {
            if let file = model.selectedFile {
                Text(displayPath(of: file))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(displayPath(of: file))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            SideBySideDiffView(patchText: patchText)
                .equatable()
        }
    }

    // MARK: - 列表选中绑定

    /// 提交列表的 List 选中绑定：读模型当前选中提交；写入 hash 选中对应提交，写入 nil 取消选中。
    /// 点选与方向键导航经同一入口，重复选中不重新加载。
    /// TEST: repo://FolbiTests/GitHistoryViewTests.swift
    static func commitSelectionBinding(model: GitHistoryModel) -> Binding<String?> {
        Binding(
            get: { model.selectedCommit?.hash },
            set: { hash in
                guard hash != model.selectedCommit?.hash else { return }
                model.selectCommit(model.commits.first { $0.hash == hash })
            }
        )
    }

    /// 变更文件列表的 List 选中绑定：写入 path 选中对应文件，写入 nil 清空选中与该文件 patch。
    /// TEST: repo://FolbiTests/GitHistoryViewTests.swift
    static func fileSelectionBinding(model: GitHistoryModel) -> Binding<String?> {
        Binding(
            get: { model.selectedFile?.path },
            set: { path in
                guard path != model.selectedFile?.path else { return }
                model.selectFile(model.changedFiles.first { $0.path == path })
            }
        )
    }

    // MARK: - 内联错误

    /// 栏顶内联错误横幅：图标加一行说明，底部以分隔线与正文分区。
    private func inlineError(_ error: GitError) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
        }
    }

    /// 右键菜单共用的剪贴板写入。只读查看能力，不触碰 .git 或工作区。
    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
