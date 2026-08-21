import XCTest
@testable import Folbi

/// 钉住「是否可预览」判定谓词（spec #10 §1）：
/// 6 个 Markdown 扩展名小写不敏感均启用，无扩展名与非 Markdown 文件不启用。
final class MarkdownPreviewabilityTests: XCTestCase {
    func testAllSixMarkdownExtensionsArePreviewable() {
        for ext in ["md", "mkd", "mkdn", "mdwn", "mdown", "markdown"] {
            let url = URL(fileURLWithPath: "/tmp/note.\(ext)")
            XCTAssertTrue(
                MarkdownPreviewability.isPreviewable(documentURL: url),
                "扩展名 \(ext) 应可预览"
            )
        }
    }

    func testExtensionsAreCaseInsensitive() {
        for name in ["NOTE.MD", "Note.Markdown", "note.MkD"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            XCTAssertTrue(
                MarkdownPreviewability.isPreviewable(documentURL: url),
                "\(name) 应可预览（小写不敏感）"
            )
        }
    }

    func testExtensionlessFileIsNotPreviewable() {
        let url = URL(fileURLWithPath: "/tmp/notes")
        XCTAssertFalse(MarkdownPreviewability.isPreviewable(documentURL: url))
    }

    func testNonMarkdownFileIsNotPreviewable() {
        for ext in ["txt", "swift", "json"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertFalse(
                MarkdownPreviewability.isPreviewable(documentURL: url),
                "扩展名 \(ext) 不应可预览"
            )
        }
    }

    func testNoDocumentIsNotPreviewable() {
        XCTAssertFalse(MarkdownPreviewability.isPreviewable(documentURL: nil))
    }
}
