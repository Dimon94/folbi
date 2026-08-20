import XCTest
@testable import Folbi

final class FolbiCoreTests: XCTestCase {
    func testDirectoryLoadIncludesDotFilesAndSortsFoldersFirst() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("README.md"))
        try Data().write(to: root.appendingPathComponent(".gitignore"))

        let node = FileNode(url: root, isDirectory: true)
        let children = try node.loadChildren()

        XCTAssertEqual(children.map(\.name), ["Sources", ".gitignore", "README.md"])
    }

    func testDocumentReadRejectsFileLargerThanLimit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.txt")
        try Data(repeating: 0x61, count: 17).write(to: file)

        XCTAssertThrowsError(try DocumentIO.readUTF8Text(at: file, maximumBytes: 16)) { error in
            XCTAssertEqual(error as? FolbiError, .fileTooLarge(maximumBytes: 16))
        }
    }

    func testNameValidationRejectsPathTraversal() {
        XCTAssertThrowsError(try DocumentIO.validateNewItemName("../secret"))
        XCTAssertThrowsError(try DocumentIO.validateNewItemName("a/b"))
        XCTAssertNoThrow(try DocumentIO.validateNewItemName("notes.md"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
