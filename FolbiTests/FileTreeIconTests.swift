import XCTest
@testable import Folbi

// 钉住文件树图标三态与图片扩展名粗判集合（spec #25 §6）：
// 文件夹恒为 folder；8 个图片扩展名小写不敏感显示 photo；其余文件显示 doc。
// 负向边界：tiff / bmp 是图片但不在粗判集合内（粗判只认扩展名白名单）；
// svg 不在集合内（#22 裁决 svg 归编辑器）；无扩展名图片显示 doc 为已接受不一致。
final class FileTreeIconTests: XCTestCase {
    func testAllEightImageExtensionsShowPhotoIcon() {
        for ext in ["png", "jpg", "jpeg", "jpe", "gif", "heic", "heif", "webp"] {
            let url = URL(fileURLWithPath: "/tmp/pic.\(ext)")
            XCTAssertEqual(
                FileTreeIcon.symbolName(for: url, isDirectory: false),
                "photo",
                "扩展名 \(ext) 应显示 photo 图标"
            )
        }
    }

    func testImageExtensionsAreCaseInsensitive() {
        for name in ["PIC.PNG", "Pic.Jpg", "pic.HeIF", "icon.WebP"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            XCTAssertEqual(
                FileTreeIcon.symbolName(for: url, isDirectory: false),
                "photo",
                "\(name) 应显示 photo 图标（小写不敏感）"
            )
        }
    }

    func testImageExtensionsOutsideCoarseSetShowDocIcon() {
        for ext in ["tiff", "bmp", "svg", "txt", "swift"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(
                FileTreeIcon.symbolName(for: url, isDirectory: false),
                "doc",
                "扩展名 \(ext) 应显示 doc 图标"
            )
        }
    }

    func testExtensionlessFileShowsDocIcon() {
        let url = URL(fileURLWithPath: "/tmp/picture")
        XCTAssertEqual(FileTreeIcon.symbolName(for: url, isDirectory: false), "doc")
    }

    func testDirectoryShowsFolderIconEvenWithImageExtension() {
        let url = URL(fileURLWithPath: "/tmp/avatar.png")
        XCTAssertEqual(FileTreeIcon.symbolName(for: url, isDirectory: true), "folder")
    }
}
