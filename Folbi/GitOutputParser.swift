import Foundation

// COORD: repo://Folbi/GitOutputParser.swift
// INPUT: GitRepositoryReader 提供的 stdout Data 与退出码。
// OUTPUT: GitCommit、GitFileChange、GitPatch 或稳定的 GitError。
// POS: Git 机器格式的纯解析层；不启动进程，不读取文件。
// TEST: repo://FolbiTests/GitOutputParserTests.swift

struct GitCommit: Equatable {
    let hash: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let subject: String
}

struct GitFileChange: Equatable {
    enum Status: Equatable {
        case added
        case modified
        case deleted
        case renamed
        case copied
    }

    let status: Status
    let path: String
    let previousPath: String?

    init(status: Status, path: String, previousPath: String? = nil) {
        self.status = status
        self.path = path
        self.previousPath = previousPath
    }
}

struct GitPatch: Equatable {
    let text: String
}

/// 解析 git 的机器格式输出。它不启动进程，也不读取文件。
/// 测试坐标：repo://FolbiTests/GitOutputParserTests.swift。
enum GitOutputParser {
    static func repositoryTopLevel(stdout: Data, exitCode: Int32) throws -> URL? {
        if exitCode == 128 { return nil }
        guard exitCode == 0,
              let output = String(data: stdout, encoding: .utf8)
        else {
            throw GitError.parseFailed
        }

        let path = output.hasSuffix("\n") ? String(output.dropLast()) : output
        guard path.hasPrefix("/") else { throw GitError.parseFailed }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func commits(stdout: Data, exitCode: Int32) throws -> [GitCommit] {
        try requireSuccess(exitCode)
        if stdout.isEmpty { return [] }

        let fields = try nulFields(stdout)
        guard fields.count.isMultiple(of: 5) else { throw GitError.parseFailed }
        let dateFormatter = ISO8601DateFormatter()

        return try stride(from: 0, to: fields.count, by: 5).map { index in
            let hash = fields[index]
            guard (hash.count == 40 || hash.count == 64),
                  hash.allSatisfy(\.isHexDigit),
                  let authorDate = dateFormatter.date(from: fields[index + 3])
            else {
                throw GitError.parseFailed
            }
            return GitCommit(
                hash: hash,
                authorName: fields[index + 1],
                authorEmail: fields[index + 2],
                authorDate: authorDate,
                subject: fields[index + 4]
            )
        }
    }

    static func changedFiles(stdout: Data, exitCode: Int32) throws -> [GitFileChange] {
        try requireSuccess(exitCode)
        if stdout.isEmpty { return [] }

        let fields = try nulFields(stdout)
        var changes: [GitFileChange] = []
        var index = 0
        while index < fields.count {
            let rawStatus = fields[index]
            index += 1

            switch rawStatus.first {
            case "A", "M", "D", "T":
                guard rawStatus.count == 1, index < fields.count, !fields[index].isEmpty else {
                    throw GitError.parseFailed
                }
                let status: GitFileChange.Status = switch rawStatus {
                case "A": .added
                case "M", "T": .modified
                default: .deleted
                }
                changes.append(GitFileChange(status: status, path: fields[index]))
                index += 1
            case "R", "C":
                guard rawStatus.dropFirst().allSatisfy(\.isNumber),
                      index + 1 < fields.count,
                      !fields[index].isEmpty,
                      !fields[index + 1].isEmpty
                else {
                    throw GitError.parseFailed
                }
                changes.append(GitFileChange(
                    status: rawStatus.first == "R" ? .renamed : .copied,
                    path: fields[index + 1],
                    previousPath: fields[index]
                ))
                index += 2
            default:
                throw GitError.parseFailed
            }
        }
        return changes
    }

    static func patch(stdout: Data, exitCode: Int32) throws -> GitPatch {
        try requireSuccess(exitCode)
        guard let text = String(data: stdout, encoding: .utf8) else {
            throw GitError.parseFailed
        }
        return GitPatch(text: text)
    }

    private static func requireSuccess(_ exitCode: Int32) throws {
        guard exitCode == 0 else {
            throw exitCode == 128 ? GitError.notRepository : GitError.parseFailed
        }
    }

    private static func nulFields(_ data: Data) throws -> [String] {
        guard data.last == 0 else { throw GitError.parseFailed }
        var rawFields = data.split(separator: 0, omittingEmptySubsequences: false)
        rawFields.removeLast()
        return try rawFields.map { field in
            guard let value = String(data: field, encoding: .utf8) else {
                throw GitError.parseFailed
            }
            return value
        }
    }
}
