import XCTest
@testable import Folbi

@MainActor
final class GitHistoryModelTests: XCTestCase {
    func testWorkspaceRebuildsGitHistoryForRepositoryAndClearsItForNonRepository() throws {
        let repository = try GitTestSupport.makeRepository()
        let nonRepository = try GitTestSupport.makeTemporaryDirectory()
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
        let repository = try GitTestSupport.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try GitTestSupport.commitText("one\n", path: "note.txt", subject: "first", in: repository)
        try GitTestSupport.commitText("two\n", path: "note.txt", subject: "second", in: repository)
        try GitTestSupport.commitText("three\n", path: "note.txt", subject: "third", in: repository)

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

        try GitTestSupport.commitText("four\n", path: "note.txt", subject: "fourth", in: repository)
        history.enterHistory()

        XCTAssertEqual(history.commits.map(\.subject), ["fourth", "third"])
        XCTAssertNil(history.selectedCommit)
        XCTAssertNil(history.selectedFile)
        XCTAssertEqual(history.changedFiles, [])
        XCTAssertNil(history.patchResult)
    }

    func testSelectingCommitLoadsRootChangesAndSelectingFileLoadsOnlyItsPatch() throws {
        let repository = try GitTestSupport.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("note\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try Data("other\n".utf8).write(to: repository.appendingPathComponent("other.txt"))
        try Data("old\n".utf8).write(to: repository.appendingPathComponent("old.txt"))
        try GitTestSupport.commitAll(subject: "root", in: repository)
        try Data("changed\n".utf8).write(to: repository.appendingPathComponent("note.txt"))
        try FileManager.default.removeItem(at: repository.appendingPathComponent("other.txt"))
        try GitTestSupport.runGit(["mv", "old.txt", "renamed.txt"], in: repository)
        try GitTestSupport.commitAll(subject: "changed", in: repository)

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
        let repository = try GitTestSupport.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("root\n".utf8).write(to: repository.appendingPathComponent("root.txt"))
        try Data("second\n".utf8).write(to: repository.appendingPathComponent("second.txt"))
        try GitTestSupport.commitAll(subject: "root", in: repository)

        try Data([0, 1, 2, 3]).write(to: repository.appendingPathComponent("binary.dat"))
        try GitTestSupport.commitAll(subject: "binary", in: repository)

        let oversized = Data(repeating: 0x61, count: 1_048_577)
        try oversized.write(to: repository.appendingPathComponent("large.txt"))
        try GitTestSupport.commitAll(subject: "large", in: repository)

        let mainBranch = try GitTestSupport.gitOutput(["branch", "--show-current"], in: repository)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try GitTestSupport.runGit(["switch", "-q", "-c", "side"], in: repository)
        try GitTestSupport.commitText("side\n", path: "side.txt", subject: "side", in: repository)
        try GitTestSupport.runGit(["switch", "-q", mainBranch], in: repository)
        try GitTestSupport.commitText("main\n", path: "main.txt", subject: "main", in: repository)
        try GitTestSupport.runGit(["merge", "-q", "--no-ff", "side", "-m", "merge"], in: repository)

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
}
