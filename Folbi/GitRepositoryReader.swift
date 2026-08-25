import Foundation

// COORD: repo://Folbi/GitRepositoryReader.swift
// INPUT: /usr/bin/git 与 repo://docs/adr/0003-git-cli-over-binding-library.md 的只读命令合同。
// OUTPUT: 仓库顶层、提交、变更文件、patch 或稳定的 GitError。
// POS: Git CLI 跨进程门面；不拥有 Git 会话状态，不写 .git 或工作区。
// TEST: repo://FolbiTests/GitRepositoryReaderTests.swift

enum GitError: Error, Equatable, LocalizedError {
    case gitUnavailable
    case notRepository
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "Git 不可用。"
        case .notRepository:
            return "文件夹不在 Git 仓库中。"
        case .parseFailed:
            return "无法读取 Git 历史。"
        }
    }
}

struct GitProcessResult {
    let stdout: Data
    let exitCode: Int32
}

/// git CLI 的只读门面。它只执行仓库识别、提交列表、变更文件和 patch 命令。
/// 测试坐标：repo://FolbiTests/GitRepositoryReaderTests.swift。
struct GitRepositoryReader {
    typealias Executor = ([String]) throws -> GitProcessResult

    private let executor: Executor

    init() {
        executor = Self.run
    }

    init(executor: @escaping Executor) {
        self.executor = executor
    }

    /// 从目录向上识别仓库。执行或解析失败时 fail closed，返回 nil。
    func repositoryTopLevel(of directory: URL) -> URL? {
        guard let result = try? execute([
            "-C", directory.path,
            "rev-parse", "--show-toplevel",
        ]) else {
            return nil
        }
        return try? GitOutputParser.repositoryTopLevel(stdout: result.stdout, exitCode: result.exitCode)
    }

    /// 分页读取提交。skip 必须非负，maxCount 必须为正数。
    func commits(in repository: URL, skip: Int, maxCount: Int) throws -> [GitCommit] {
        guard skip >= 0, maxCount > 0 else { throw GitError.parseFailed }
        let result = try execute([
            "-C", repository.path,
            "log",
            "--format=%H%x00%an%x00%ae%x00%aI%x00%s",
            "-z",
            "--max-count=\(maxCount)",
            "--skip=\(skip)",
        ])
        return try GitOutputParser.commits(stdout: result.stdout, exitCode: result.exitCode)
    }

    /// 读取一个提交的变更文件。根提交按对空树的创建事件处理。
    /// PARAM: `-M` 启用 Git 默认重命名检测，输出由 parser 映射为 renamed 与 previousPath。
    func changedFiles(of hash: String, in repository: URL) throws -> [GitFileChange] {
        try validateHash(hash)
        let result = try execute([
            "-C", repository.path,
            "diff-tree", "-r", "-M", "--no-commit-id", "--root", "--name-status", "-z", hash,
        ])
        return try GitOutputParser.changedFiles(stdout: result.stdout, exitCode: result.exitCode)
    }

    /// 读取一个提交或其中一个文件的 unified patch。
    func patch(of hash: String, path: String?, in repository: URL) throws -> GitPatch {
        try validateHash(hash)
        var arguments = [
            "--literal-pathspecs",
            "-C", repository.path,
            "diff-tree", "-r", "--no-commit-id", "--root", "-p", hash,
        ]
        if let path {
            try validateArgument(path)
            arguments += ["--", path]
        }
        let result = try execute(arguments)
        return try GitOutputParser.patch(stdout: result.stdout, exitCode: result.exitCode)
    }

    private func execute(_ arguments: [String]) throws -> GitProcessResult {
        do {
            return try executor(arguments)
        } catch let error as GitError {
            throw error
        } catch {
            throw GitError.gitUnavailable
        }
    }

    private func validateArgument(_ argument: String) throws {
        guard !argument.isEmpty, !argument.unicodeScalars.contains("\0") else {
            throw GitError.parseFailed
        }
    }

    private func validateHash(_ hash: String) throws {
        guard (hash.count == 40 || hash.count == 64), hash.allSatisfy(\.isHexDigit) else {
            throw GitError.parseFailed
        }
    }

    private static func run(_ arguments: [String]) throws -> GitProcessResult {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return GitProcessResult(stdout: data, exitCode: process.terminationStatus)
    }
}
