import XCTest
@testable import Folbi

final class ImagePathResolverTests: XCTestCase {
    func testRelativePathResolvesAgainstDocumentDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = ImagePathResolver.resolve(
            "images/pic.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, expectedLoadable(fixture.rootURL.appendingPathComponent("docs/images/pic.png")))
    }

    func testParentReferenceStayingInsideRootResolves() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = ImagePathResolver.resolve(
            "../shared/logo.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, expectedLoadable(fixture.rootURL.appendingPathComponent("shared/logo.png")))
    }

    func testEscapeOutsideRootFailsClosedEvenWhenFileExists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // outside.png 真实存在且可读；fail closed 由路径判定决定，与磁盘内容无关。
        let result = ImagePathResolver.resolve(
            "../../outside.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, .placeholder)
    }

    func testEscapeOutsideRootReturnsBeforeAnyFileManagerAccess() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let spy = SpyFileManager()

        let result = ImagePathResolver.resolve(
            "../../outside.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL,
            fileManager: spy
        )

        XCTAssertEqual(result, .placeholder)
        XCTAssertEqual(spy.statPaths, [], "越界路径必须 fail closed 于词法判定，不得触碰磁盘")
    }

    func testSymlinkEscapingRootFailsClosed() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        // 根内 symlink 指向根外文件：词法路径在边界内，真实路径在边界外。
        let link = fixture.rootURL.appendingPathComponent("docs/link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.baseURL.appendingPathComponent("outside.png"))

        let result = ImagePathResolver.resolve(
            "link.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, .placeholder)
    }

    func testSymlinkStayingInsideRootResolves() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let link = fixture.rootURL.appendingPathComponent("docs/alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.rootURL.appendingPathComponent("shared/logo.png"))

        let result = ImagePathResolver.resolve(
            "alias.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, expectedLoadable(fixture.rootURL.appendingPathComponent("shared/logo.png")))
    }

    func testMissingFileInsideRootFallsBackToPlaceholder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = ImagePathResolver.resolve(
            "images/missing.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, .placeholder)
    }

    func testUnreadableFileFallsBackToPlaceholder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let unreadable = fixture.rootURL.appendingPathComponent("docs/images/unreadable.png")
        try Data().write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)

        let result = ImagePathResolver.resolve(
            "images/unreadable.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, .placeholder)
    }

    func testNonLocalAndEmptyPathsFailClosed() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        for path in ["", "https://example.com/pic.png", "://"] {
            let result = ImagePathResolver.resolve(
                path,
                documentURL: fixture.documentURL,
                rootURL: fixture.rootURL
            )
            XCTAssertEqual(result, .placeholder, "路径 \(path.debugDescription) 应走占位分支")
        }
    }

    func testPercentEncodedPathResolvesDecodedFile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try Data().write(to: fixture.rootURL.appendingPathComponent("docs/my pic.png"))

        let result = ImagePathResolver.resolve(
            "my%20pic.png",
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        XCTAssertEqual(result, expectedLoadable(fixture.rootURL.appendingPathComponent("docs/my pic.png")))
    }

    /// 实现的后条件：返回的 URL 符号链接已解析（临时目录在 /var -> /private/var 下，两侧必须同链比较）。
    private func expectedLoadable(_ url: URL) -> ImagePathResolution {
        .loadable(url.resolvingSymlinksInPath().standardizedFileURL)
    }

    private final class SpyFileManager: FileManager {
        private(set) var statPaths: [String] = []

        override func fileExists(atPath path: String) -> Bool {
            statPaths.append(path)
            return super.fileExists(atPath: path)
        }

        override func isReadableFile(atPath path: String) -> Bool {
            statPaths.append(path)
            return super.isReadableFile(atPath: path)
        }
    }

    private struct Fixture {
        let baseURL: URL
        let rootURL: URL
        let documentURL: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    /// 目录结构：base/outside.png 在根文件夹之外；root/docs/note.md 是当前文档。
    private func makeFixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("shared", isDirectory: true), withIntermediateDirectories: false)
        try Data().write(to: base.appendingPathComponent("outside.png"))
        try Data().write(to: docs.appendingPathComponent("note.md"))
        try Data().write(to: docs.appendingPathComponent("images/pic.png"))
        try Data().write(to: root.appendingPathComponent("shared/logo.png"))
        return Fixture(baseURL: base, rootURL: root, documentURL: docs.appendingPathComponent("note.md"))
    }
}
