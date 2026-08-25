import SwiftUI

// COORD: repo://Folbi/GitHistoryView.swift
// INPUT: GitHistoryModel 的只读可观察状态。
// OUTPUT: 三栏历史视图（提交列表｜变更文件｜差异），变更文件与差异栏本票为占位（#46）。
// POS: 历史视图模块；只读 GitHistoryModel，不写 .git 或工作区。
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

/// 三栏历史视图：提交列表｜变更文件｜差异。
/// 后两栏本票为占位（#46 范围），只呈现占位文案，不做真实联动。
struct GitHistoryView: View {
    @ObservedObject var model: GitHistoryModel

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            commitListColumn
            Divider()
            placeholderColumn(title: "变更文件")
            Divider()
            placeholderColumn(title: "差异")
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
                emptyPlaceholder("暂无提交")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.commits, id: \.hash) { commit in
                            commitRow(commit)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                        if model.hasMoreCommits {
                            LoadMoreAnchor {
                                model.loadNextPage()
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.hash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(commit.subject)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(commit.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: commit.authorDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - 占位栏

    private func placeholderColumn(title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("选中提交后显示")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 内联错误与空态

    private func inlineError(_ error: GitError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func emptyPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
