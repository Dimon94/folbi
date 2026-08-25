import Foundation
import XCTest

/// Git 历史相关测试的共享 fixture：临时真实仓库的创建、提交与只读命令执行。
/// 供 GitHistoryModelTests 与 GitHistoryViewSelectionTests 共用，规则与失败语义只有这一份。
enum GitTestSupport {
    /// 建临时目录并 `git init`，配置固定测试身份。
    static func makeRepository() throws -> URL {
        let repository = try makeTemporaryDirectory()
        try runGit(["init", "-q"], in: repository)
        try runGit(["config", "user.name", "Folbi Tests"], in: repository)
        try runGit(["config", "user.email", "folbi@example.com"], in: repository)
        return repository
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func commitText(_ text: String, path: String, subject: String, in repository: URL) throws {
        try Data(text.utf8).write(to: repository.appendingPathComponent(path))
        try commitAll(subject: subject, in: repository)
    }

    static func commitAll(subject: String, in repository: URL) throws {
        try runGit(["add", "--all"], in: repository)
        try runGit(["commit", "-q", "-m", subject], in: repository)
    }

    static func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        let stdout = Pipe()
        let process = gitProcess(arguments, in: directory)
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) 应成功")
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    static func runGit(_ arguments: [String], in directory: URL) throws {
        let process = gitProcess(arguments, in: directory)
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) 应成功")
    }

    private static func gitProcess(_ arguments: [String], in directory: URL) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }
}
