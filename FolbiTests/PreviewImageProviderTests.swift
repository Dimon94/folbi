import AppKit
import XCTest
@testable import Folbi

/// 钉住预览图片加载的分支判定（#16）：边界内可解码 → 本地加载；
/// 缺失/越界/SVG/坏文件/缺上下文/非 http(s) scheme → 占位；
/// http(s) → 默认网络加载分支。
/// 越界用例在错误实现下必失败：若丢掉解析器直接读盘，真实存在的
/// outside.png 会被错误加载而非占位。
final class PreviewImageProviderTests: XCTestCase {
    func testExistingImageInsideRootLoadsLocally() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let load = PreviewImageProvider.classify(
            url: fixture.insideImageURL,
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .local(let image) = load else {
            return XCTFail("边界内存在图片应走本地加载，得到 \(load)")
        }
        XCTAssertEqual(image.size, NSSize(width: 2, height: 2))
    }

    func testMissingImageFallsToPlaceholder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let load = PreviewImageProvider.classify(
            url: fixture.rootURL.appendingPathComponent("docs/images/missing.png"),
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .placeholder(let name) = load else {
            return XCTFail("缺失图片应走占位，得到 \(load)")
        }
        XCTAssertEqual(name, "missing.png")
    }

    func testEscapeOutsideRootFailsClosedEvenWhenFileExists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // outside.png 真实存在且可解码；fail closed 由边界判定决定，与磁盘内容无关。
        let load = PreviewImageProvider.classify(
            url: fixture.outsideImageURL,
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .placeholder(let name) = load else {
            return XCTFail("越界图片必须 fail closed 走占位，得到 \(load)")
        }
        XCTAssertEqual(name, "outside.png")
    }

    func testLocalSVGFallsToPlaceholder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        // SVG 真实存在、可读、在边界内；ticket 裁决本地 SVG 走占位分支。
        let svg = fixture.rootURL.appendingPathComponent("docs/images/vector.svg")
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"2\"/>".utf8).write(to: svg)

        let load = PreviewImageProvider.classify(
            url: svg,
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .placeholder(let name) = load else {
            return XCTFail("本地 SVG 应走占位，得到 \(load)")
        }
        XCTAssertEqual(name, "vector.svg")
    }

    func testUndecodableImageFallsToPlaceholder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        // 存在、可读、边界内，但内容不是图片：NSImage 解码失败同样占位，不崩溃。
        let corrupt = fixture.rootURL.appendingPathComponent("docs/images/corrupt.png")
        try Data("not an image".utf8).write(to: corrupt)

        let load = PreviewImageProvider.classify(
            url: corrupt,
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .placeholder = load else {
            return XCTFail("不可解码图片应走占位，得到 \(load)")
        }
    }

    func testRemoteHTTPURLGoesToNetworkBranch() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let remote = URL(string: "https://example.com/pic.png")!

        let load = PreviewImageProvider.classify(
            url: remote,
            documentURL: fixture.documentURL,
            rootURL: fixture.rootURL
        )

        guard case .remote(let url) = load else {
            return XCTFail("远程 http(s) 图片应走网络加载分支，得到 \(load)")
        }
        XCTAssertEqual(url, remote)
    }

    func testUnsupportedSchemeFallsToPlaceholder() {
        let unsupported = URL(string: "ftp://example.com/pic.png")!

        let load = PreviewImageProvider.classify(
            url: unsupported,
            documentURL: nil,
            rootURL: nil
        )

        guard case .placeholder(let name) = load else {
            return XCTFail("非 http(s) scheme 应 fail closed 走占位，得到 \(load)")
        }
        XCTAssertEqual(name, "pic.png")
    }

    func testNilURLFallsToPlaceholder() {
        let load = PreviewImageProvider.classify(url: nil, documentURL: nil, rootURL: nil)

        guard case .placeholder(let name) = load else {
            return XCTFail("空 URL 应走占位，得到 \(load)")
        }
        XCTAssertNil(name)
    }

    func testMissingContextFailsClosedForLocalButKeepsRemote() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let local = PreviewImageProvider.classify(
            url: fixture.insideImageURL,
            documentURL: nil,
            rootURL: nil
        )
        guard case .placeholder = local else {
            return XCTFail("缺少文档/根文件夹上下文时本地图片应 fail closed，得到 \(local)")
        }

        let remote = URL(string: "https://example.com/pic.png")!
        let network = PreviewImageProvider.classify(url: remote, documentURL: nil, rootURL: nil)
        guard case .remote = network else {
            return XCTFail("远程图片不依赖本地上下文，仍应走网络加载分支，得到 \(network)")
        }
    }

    private struct Fixture {
        let baseURL: URL
        let rootURL: URL
        let documentURL: URL
        let insideImageURL: URL
        let outsideImageURL: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    /// 目录结构：base/outside.png 在根文件夹之外；root/docs/note.md 是当前文档。
    private func makeFixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let images = docs.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("# note".utf8).write(to: docs.appendingPathComponent("note.md"))
        let inside = images.appendingPathComponent("pic.png")
        try writePNG(to: inside)
        let outside = base.appendingPathComponent("outside.png")
        try writePNG(to: outside)
        return Fixture(
            baseURL: base,
            rootURL: root,
            documentURL: docs.appendingPathComponent("note.md"),
            insideImageURL: inside,
            outsideImageURL: outside
        )
    }

    /// 2x2 真实 PNG：NSImage 可解码，区别于「存在但不可解码」分支。
    private func writePNG(to url: URL) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        let data = try XCTUnwrap(rep?.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
