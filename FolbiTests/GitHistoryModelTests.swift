import XCTest
@testable import Folbi

@MainActor
final class GitHistoryModelTests: XCTestCase {
    func testWorkspaceRebuildsGitHistoryForRepositoryAndClearsItForNonRepository() throws {
        let repository = try makeRepository()
        let nonRepository = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repository)
            try? FileManager.default.removeItem(at: nonRepository)
        }
        let child = repository.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)

        let model = WorkspaceModel()
        model.openRootFolder(child)
        XCTAssertEqual(model.gitHistory?.repositoryURL, repository.standardizedFileURL)

        model.openRootFolder(nonRepository)
        XCTAssertNil(model.gitHistory)
    }

    func testEnteringHistoryResetsBrowsingStateAndLoadsLatestFirstPage() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try commitText("one\n", path: "note.txt", subject: "first", in: repository)
        try commitText("two\n", path: "note.txt", subject: "second", in: repository)
        try commitText("three\n", path: "note.txt", subject: "third", in: repository)

        let history = try XCTUnwrap(GitHistoryModel(rootFolderURL: repository, pageSize: 2))
        history.enterHistory()
        XCTAssertEqual(history.commits.map(\.subject), ["third", "second"])
        XCTAssertTrue(history.hasMoreCommits)

        history.loadNextPage()
        XCTAssertEqual(history.commits.map(\.subject), ["third", "second", "first"])
        XCTAssertFalse(history.hasMoreCommits)
        history.selectCommit(history.commits[0])
        history.selectFile(try XCTUnwrap(history.changedFiles.first))
        XCTAssertNotNil(history.selectedCommit)
        XCTAssertNotNil(history.selectedFile)

        try commitText("four\n", path: "note.txt", subject: "fourth", in: repository)
        history.enterHistory()

        XCTAssertEqual(history.commits.map(\.subject), ["fourth", "third"])
        XCTAssertNil(history.selectedCommit)
        XCTAssertNil(history.selectedFile)
        XCTAssertEqual(history.changedFiles, [])
        XCTAssertNil(history.patchResult)
    }

    func testSelectingCommitLoadsRootChangesAndSelectingFileLoadsOnlyItsPatch() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("note\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try Data("other\n".utf8).write(to: repository.appendingPathComponent("other.txt"))
        try Data("old\n".utf8).write(to: repository.appendingPathComponent("old.txt"))
        try commitAll(subject: "root", in: repository)
        try Data("changed\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try FileManager.default.removeItem(at: repository.appendingPathComponent("other.txt"))
        try runGit(["mv", "old.txt", "renamed.txt"], in: repository)
        try commitAll(subject: "changed", in: repository)

        let history = try XCTUnwrap(GitHistoryModel(rootFolderURL: repository))
        history.enterHistory()
        history.selectCommit(try commit(subject: "root", in: history.commits))

        XCTAssertEqual(Set(history.changedFiles.map(\.status)), [.added])
        XCTAssertEqual(Set(history.changedFiles.map(\.path)), ["note.txt", "old.txt", "other.txt"])

        history.selectCommit(try commit(subject: "changed", in: history.commits))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: history.changedFiles.map { ($0.path, $0.status) }),
            [
                "note.txt": .modified,
                "other.txt": .deleted,
                "renamed.txt": .renamed,
            ]
        )
        XCTAssertEqual(
            history.changedFiles.first { $0.path == "renamed.txt" }?.previousPath,
            "old.txt"
        )

        let note = try XCTUnwrap(history.changedFiles.first { $0.path == "note.txt" })
        history.selectFile(note)
        guard case .content(let text) = history.patchResult else {
            return XCTFail("文本文件应返回正常 patch")
        }
        XCTAssertTrue(text.contains("note.txt"))
        XCTAssertFalse(text.contains("other.txt"))
    }

    func testPatchResultClassifiesBinaryOversizeMergeAndPreservesContentOnFailure() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("root\n".utf8).write(to: repository.appendingPathComponent("root.txt"))
        try Data("second\n".utf8).write(to: repository.appendingPathComponent("second.txt"))
        try commitAll(subject: "root", in: repository)

        try Data([0, 1, 2, 3]).write(to: repository.appendingPathComponent("binary.dat"))
        try commitAll(subject: "binary", in: repository)

        let oversized = Data(repeating: 0x61, count: 1_048_577)
        try oversized.write(to: repository.appendingPathComponent("large.txt"))
        try commitAll(subject: "large", in: repository)

        let mainBranch = try gitOutput(["branch", "--show-current"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["switch", "-q", "-c", "side"], in: repository)
        try commitText("side\n", path: "side.txt", subject: "side", in: repository)
        try runGit(["switch", "-q", mainBranch], in: repository)
        try commitText("main\n", path: "main.txt", subject: "main", in: repository)
        try runGit(["merge", "-q", "--no-ff", "side", "-m", "merge"], in: repository)

        let history = try XCTUnwrap(GitHistoryModel(rootFolderURL: repository, pageSize: 10))
        history.enterHistory()

        history.selectCommit(try commit(subject: "binary", in: history.commits))
        history.selectFile(try XCTUnwrap(history.changedFiles.first { $0.path == "binary.dat" }))
        XCTAssertEqual(history.patchResult, .binary)

        history.selectCommit(try commit(subject: "large", in: history.commits))
        history.selectFile(try XCTUnwrap(history.changedFiles.first { $0.path == "large.txt" }))
        XCTAssertEqual(history.patchResult, .exceedsLimit)

        history.selectCommit(try commit(subject: "merge", in: history.commits))
        XCTAssertEqual(history.changedFiles, [])
        XCTAssertEqual(history.patchResult, .mergeCommit)

        history.selectCommit(try commit(subject: "root", in: history.commits))
        let rootFile = try XCTUnwrap(history.changedFiles.first { $0.path == "root.txt" })
        let secondFile = try XCTUnwrap(history.changedFiles.first { $0.path == "second.txt" })
        history.selectFile(rootFile)
        guard case .content(let retainedText) = history.patchResult else {
            return XCTFail("前置 patch 应加载成功")
        }

        try FileManager.default.moveItem(
            at: repository.appendingPathComponent(".git"),
            to: repository.appendingPathComponent(".git-disabled")
        )
        history.selectFile(secondFile)
        XCTAssertEqual(history.patchResult, .failure(.notRepository, retainedContent: retainedText))

        let retainedChanges = history.changedFiles
        history.selectCommit(try commit(subject: "root", in: history.commits))
        XCTAssertEqual(history.changedFiles, retainedChanges)
        XCTAssertEqual(history.changedFilesError, .notRepository)
    }

    private func commit(subject: String, in commits: [GitCommit]) throws -> GitCommit {
        try XCTUnwrap(commits.first { $0.subject == subject })
    }

    private func makeRepository() throws -> URL {
        let repository = try makeTemporaryDirectory()
        try runGit(["init", "-q"], in: repository)
        try runGit(["config", "user.name", "Folbi Tests"], in: repository)
        try runGit(["config", "user.email", "folbi@example.com"], in: repository)
        return repository
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func commitText(_ text: String, path: String, subject: String, in repository: URL) throws {
        try Data(text.utf8).write(to: repository.appendingPathComponent(path))
        try commitAll(subject: subject, in: repository)
    }

    private func commitAll(subject: String, in repository: URL) throws {
        try runGit(["add", "--all"], in: repository)
        try runGit(["commit", "-q", "-m", subject], in: repository)
    }

    private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        let stdout = Pipe()
        let process = gitProcess(arguments, in: directory)
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) 应成功")
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = gitProcess(arguments, in: directory)
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) 应成功")
    }

    private func gitProcess(_ arguments: [String], in directory: URL) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }
}
