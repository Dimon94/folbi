import XCTest
@testable import Folbi

final class GitRepositoryReaderTests: XCTestCase {
    func testReaderDiscoversRepositoryAndReadsPagedHistoryFilesAndPatch() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let child = repository.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)

        let reader = GitRepositoryReader()
        XCTAssertEqual(reader.repositoryTopLevel(of: child), repository.standardizedFileURL)

        let newest = try reader.commits(in: repository, skip: 0, maxCount: 1)
        let oldest = try reader.commits(in: repository, skip: 1, maxCount: 1)
        XCTAssertEqual(newest.map(\.subject), ["second"])
        XCTAssertEqual(oldest.map(\.subject), ["root"])

        XCTAssertEqual(
            try reader.changedFiles(of: oldest[0].hash, in: repository),
            [GitFileChange(status: .added, path: "note.txt")]
        )
        XCTAssertEqual(
            Set(try reader.changedFiles(of: newest[0].hash, in: repository).map(\.path)),
            Set([":literal.txt", "note.txt", "second.txt"])
        )

        let patch = try reader.patch(of: newest[0].hash, path: "note.txt", in: repository)
        XCTAssertTrue(patch.text.contains("-one"))
        XCTAssertTrue(patch.text.contains("+two"))
        XCTAssertTrue(
            try reader.patch(of: newest[0].hash, path: ":literal.txt", in: repository)
                .text.contains("+literal")
        )
    }

    func testInjectedExecutorCoversFailClosedAndUnavailablePaths() throws {
        var capturedArguments: [String] = []
        let nonRepository = GitRepositoryReader { arguments in
            capturedArguments = arguments
            return GitProcessResult(stdout: Data(), exitCode: 128)
        }
        let directory = URL(fileURLWithPath: "/tmp/not-a-repository")

        XCTAssertNil(nonRepository.repositoryTopLevel(of: directory))
        XCTAssertEqual(capturedArguments, [
            "-C", directory.path, "rev-parse", "--show-toplevel",
        ])
        XCTAssertThrowsError(try nonRepository.commits(in: directory, skip: 0, maxCount: 100)) { error in
            XCTAssertEqual(error as? GitError, .notRepository)
        }

        let unavailable = GitRepositoryReader { _ in throw StubError.unavailable }
        XCTAssertNil(unavailable.repositoryTopLevel(of: directory))
        XCTAssertThrowsError(try unavailable.commits(in: directory, skip: 0, maxCount: 100)) { error in
            XCTAssertEqual(error as? GitError, .gitUnavailable)
        }
    }

    func testReaderRejectsInvalidHashBeforeExecution() {
        var didExecute = false
        let reader = GitRepositoryReader { _ in
            didExecute = true
            return GitProcessResult(stdout: Data(), exitCode: 0)
        }

        XCTAssertThrowsError(
            try reader.changedFiles(of: "--help", in: URL(fileURLWithPath: "/tmp/repository"))
        ) { error in
            XCTAssertEqual(error as? GitError, .parseFailed)
        }
        XCTAssertFalse(didExecute)
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: false)
        try runGit(["init", "-q"], in: repository)
        try runGit(["config", "user.name", "Folbi Tests"], in: repository)
        try runGit(["config", "user.email", "folbi@example.com"], in: repository)

        try Data("one\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try runGit(["add", "note.txt"], in: repository)
        try runGit(["commit", "-q", "-m", "root"], in: repository, date: "2026-08-24T10:00:00+08:00")

        try Data("two\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try Data("second\n".utf8).write(to: repository.appendingPathComponent("second.txt"))
        try Data("literal\n".utf8).write(to: repository.appendingPathComponent(":literal.txt"))
        try runGit(["add", "--all"], in: repository)
        try runGit(["commit", "-q", "-m", "second"], in: repository, date: "2026-08-24T11:00:00+08:00")
        return repository
    }

    private func runGit(_ arguments: [String], in directory: URL, date: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let date {
            process.environment = ProcessInfo.processInfo.environment.merging([
                "GIT_AUTHOR_DATE": date,
                "GIT_COMMITTER_DATE": date,
            ]) { _, fixed in fixed }
        }
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) 应成功")
    }

    private enum StubError: Error {
        case unavailable
    }
}
