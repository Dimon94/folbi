import Combine
import Foundation

// COORD: repo://Folbi/GitHistoryModel.swift
// INPUT: 根文件夹 URL 与 GitRepositoryReader 的只读结果。
// OUTPUT: 仓库、分页提交、选择状态、变更文件与 patch 结果。
// POS: Git 会话状态的唯一 owner；不引用 WorkspaceModel，不写 .git 或工作区。
// TEST: repo://FolbiTests/GitHistoryModelTests.swift

enum GitPatchResult: Equatable {
    case content(String)
    case exceedsLimit
    case binary
    case mergeCommit
    case failure(GitError, retainedContent: String?)
}

@MainActor
final class GitHistoryModel: ObservableObject {
    /// PARAM: maximumPatchBytes，单文件 patch 的 UTF-8 字节上限，固定为 1 MiB（spec #42 §4）。
    /// FAIL: 超过上限返回 exceedsLimit，不回滚文件选择。
    /// TEST: repo://FolbiTests/GitHistoryModelTests.swift
    static let maximumPatchBytes = 1_024 * 1_024

    let repositoryURL: URL

    @Published private(set) var commits: [GitCommit] = []
    @Published private(set) var hasMoreCommits = true
    @Published private(set) var selectedCommit: GitCommit?
    @Published private(set) var changedFiles: [GitFileChange] = []
    @Published private(set) var selectedFile: GitFileChange?
    @Published private(set) var patchResult: GitPatchResult?
    @Published private(set) var commitsError: GitError?
    @Published private(set) var changedFilesError: GitError?

    private let reader: GitRepositoryReader
    private let pageSize: Int

    init?(rootFolderURL: URL, pageSize: Int = 100) {
        guard pageSize > 0 else { return nil }
        let reader = GitRepositoryReader()
        guard let repositoryURL = reader.repositoryTopLevel(of: rootFolderURL) else { return nil }
        self.repositoryURL = repositoryURL
        self.pageSize = pageSize
        self.reader = reader
    }

    /// 每次进入历史视图时清空浏览状态，并只读取最新一页。
    func enterHistory() {
        commits = []
        hasMoreCommits = true
        selectedCommit = nil
        changedFiles = []
        selectedFile = nil
        patchResult = nil
        commitsError = nil
        changedFilesError = nil
        loadNextPage()
    }

    /// 用已加载数作为 skip 增量读取；失败时保留已有提交。
    func loadNextPage() {
        guard hasMoreCommits else { return }
        do {
            let page = try reader.commits(
                in: repositoryURL,
                skip: commits.count,
                maxCount: pageSize
            )
            commits.append(contentsOf: page)
            hasMoreCommits = page.count == pageSize
            commitsError = nil
        } catch {
            commitsError = gitError(error)
        }
    }

    /// 选择提交后按需读取变更文件；空输出按合并提交占位处理。
    func selectCommit(_ commit: GitCommit?) {
        selectedCommit = commit
        selectedFile = nil
        guard let commit else {
            changedFiles = []
            patchResult = nil
            changedFilesError = nil
            return
        }

        do {
            let files = try reader.changedFiles(of: commit.hash, in: repositoryURL)
            changedFiles = files
            patchResult = files.isEmpty ? .mergeCommit : nil
            changedFilesError = nil
        } catch {
            changedFilesError = gitError(error)
        }
    }

    /// 选择文件后只读取该文件 patch；失败时把最近的文本内容带入失败结果。
    func selectFile(_ file: GitFileChange?) {
        selectedFile = file
        guard let file, let commit = selectedCommit else {
            patchResult = nil
            return
        }

        let retainedContent: String? = switch patchResult {
        case .content(let text): text
        case .failure(_, let text): text
        default: nil
        }

        do {
            let patch = try reader.patch(of: commit.hash, path: file.path, in: repositoryURL)
            patchResult = classify(patch)
        } catch {
            patchResult = .failure(gitError(error), retainedContent: retainedContent)
        }
    }

    private func classify(_ patch: GitPatch) -> GitPatchResult {
        if patch.text.utf8.count > Self.maximumPatchBytes { return .exceedsLimit }
        if patch.text.split(separator: "\n").contains(where: {
            $0.hasPrefix("Binary files ") && $0.hasSuffix(" differ")
        }) {
            return .binary
        }
        return patch.text.isEmpty ? .mergeCommit : .content(patch.text)
    }

    private func gitError(_ error: Error) -> GitError {
        error as? GitError ?? .parseFailed
    }
}
