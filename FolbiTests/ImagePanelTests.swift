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
