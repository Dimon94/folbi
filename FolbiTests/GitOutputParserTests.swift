import XCTest
@testable import Folbi

final class GitOutputParserTests: XCTestCase {
    func testCommitsPreserveNULFieldsAndPageBoundary() throws {
        let output = nulData([
            "1111111111111111111111111111111111111111",
            "张 三",
            "zhang@example.com",
            "2026-08-24T10:00:00+08:00",
            "第一条提交",
            "2222222222222222222222222222222222222222",
            "李四",
            "li@example.com",
            "2026-08-24T11:00:00+08:00",
            "第二条提交",
        ])

        let commits = try GitOutputParser.commits(stdout: output, exitCode: 0)

        XCTAssertEqual(commits.map(\.hash), [
            "1111111111111111111111111111111111111111",
            "2222222222222222222222222222222222222222",
        ])
        XCTAssertEqual(commits.map(\.authorName), ["张 三", "李四"])
        XCTAssertEqual(commits.map(\.authorEmail), ["zhang@example.com", "li@example.com"])
        XCTAssertEqual(commits.map(\.subject), ["第一条提交", "第二条提交"])
        XCTAssertEqual(try GitOutputParser.commits(stdout: Data(), exitCode: 0), [])
    }

    func testChangedFilesParseRootRenameCopyAndUnescapedPaths() throws {
        let unusualPath = "目录/空 格\n文件.md"
        let output = nulData([
            "A", "README.md",
            "A", unusualPath,
            "M", "修改.swift",
            "T", "类型变化.swift",
            "D", "删除.swift",
            "R100", "旧 名称.txt", "新 名称.txt",
            "C075", "来源.swift", "副本.swift",
        ])

        let changes = try GitOutputParser.changedFiles(stdout: output, exitCode: 0)

        XCTAssertEqual(changes, [
            GitFileChange(status: .added, path: "README.md"),
            GitFileChange(status: .added, path: unusualPath),
            GitFileChange(status: .modified, path: "修改.swift"),
            GitFileChange(status: .modified, path: "类型变化.swift"),
            GitFileChange(status: .deleted, path: "删除.swift"),
            GitFileChange(status: .renamed, path: "新 名称.txt", previousPath: "旧 名称.txt"),
            GitFileChange(status: .copied, path: "副本.swift", previousPath: "来源.swift"),
        ])
    }

    func testExit128AndMalformedOutputMapToStableErrors() throws {
        XCTAssertNil(try GitOutputParser.repositoryTopLevel(stdout: Data(), exitCode: 128))

        XCTAssertThrowsError(
            try GitOutputParser.commits(stdout: nulData(["hash", "author"]), exitCode: 0)
        ) { error in
            XCTAssertEqual(error as? GitError, .parseFailed)
        }

        XCTAssertThrowsError(
            try GitOutputParser.changedFiles(stdout: nulData(["R100", "old-only"]), exitCode: 0)
        ) { error in
            XCTAssertEqual(error as? GitError, .parseFailed)
        }

        XCTAssertThrowsError(try GitOutputParser.patch(stdout: Data(), exitCode: 128)) { error in
            XCTAssertEqual(error as? GitError, .notRepository)
        }
    }

    func testRepositoryAndPatchRejectMalformedUTF8() throws {
        let invalidUTF8 = Data([0xFF])

        XCTAssertThrowsError(
            try GitOutputParser.repositoryTopLevel(stdout: invalidUTF8, exitCode: 0)
        ) { error in
            XCTAssertEqual(error as? GitError, .parseFailed)
        }
        XCTAssertThrowsError(try GitOutputParser.patch(stdout: invalidUTF8, exitCode: 0)) { error in
            XCTAssertEqual(error as? GitError, .parseFailed)
        }
    }

    private func nulData(_ fields: [String]) -> Data {
        Data((fields.joined(separator: "\0") + "\0").utf8)
    }
}
