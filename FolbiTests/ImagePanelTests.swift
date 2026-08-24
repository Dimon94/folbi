import XCTest
@testable import Folbi

final class ImagePanelTests: XCTestCase {
    func testDisplayableImageDownsamplesWithoutUpscaling() {
        // 16×16 PNG，maxPixelSize=512：不得放大，产出停在原始像素尺寸。
        guard case .image(_, let pixelSize) = ImagePanel.load(url: fixtureURL("png-no-extension"), maxPixelSize: 512) else {
            return XCTFail("白名单图片应解码为可显示图片")
        }
        XCTAssertEqual(pixelSize, CGSize(width: 16, height: 16))
    }

    func testGIFRoutesToAnimatedContentBySniffingNotExtension() {
        // animated.gif：32×16 三帧；gif.txt：GIF 内容 + 文本扩展名。两者都按内容路由到动画分支，
        // 并携带原始帧像素尺寸（非方形尺寸同时锁定宽高不互换）。
        let cases: [(String, CGSize)] = [
            ("animated.gif", CGSize(width: 32, height: 16)),
            ("gif.txt", CGSize(width: 16, height: 16)),
        ]
        for (name, expected) in cases {
            guard case .gif(_, let pixelSize) = ImagePanel.load(url: fixtureURL(name), maxPixelSize: 512) else {
                return XCTFail("\(name) 应按内容路由到动画内容分支")
            }
            XCTAssertEqual(pixelSize, expected, name)
        }
    }

    func testAnimatedContentImageCarriesAllFrames() {
        // NSImageView 依赖 NSBitmapImageRep 持有的全部帧播放；只带首帧的 NSImage 会让动图看似损坏。
        guard case .gif(let image, _) = ImagePanel.load(url: fixtureURL("animated.gif"), maxPixelSize: 512) else {
            return XCTFail("GIF 应路由到动画内容分支")
        }
        let rep = image.representations.first as? NSBitmapImageRep
        XCTAssertEqual(
            rep?.value(forProperty: NSBitmapImageRep.PropertyKey.frameCount) as? Int,
            3,
            "动画内容必须携带全部帧"
        )
    }

    func testOverLimitImageReportsPixelLimit() {
        guard case .exceedsPixelLimit = ImagePanel.load(url: fixtureURL("over-limit.png"), maxPixelSize: 512) else {
            return XCTFail("超 1 亿像素应走超限占位")
        }
    }

    func testNonImageContentReportsDecodeFailure() {
        // 内容为文本，扩展名为图片：二次读头不符即占位，不上屏。
        guard case .decodeFailed = ImagePanel.load(url: fixtureURL("notes.webp"), maxPixelSize: 512) else {
            return XCTFail("非图片内容应走解码失败占位")
        }
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ImageOpenPolicy/\(name)")
    }
}
