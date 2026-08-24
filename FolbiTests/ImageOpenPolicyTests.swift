import XCTest
@testable import Folbi

final class ImageOpenPolicyTests: XCTestCase {
    func testWhitelistedContentIsDisplayableWithoutTrustingExtension() {
        let fixtureNames = [
            "png-no-extension",
            "jpeg.png",
            "gif.txt",
            "heic.bin",
            "webp.jpg",
        ]

        for name in fixtureNames {
            XCTAssertEqual(
                ImageOpenPolicy.evaluate(fixtureURL(name)),
                .displayable,
                "\(name) 应按内容识别为可显示图片"
            )
        }
    }

    func testSVGAndTextAreNotImagesEvenWithImageExtensions() {
        for name in ["vector.png", "notes.webp"] {
            XCTAssertEqual(
                ImageOpenPolicy.evaluate(fixtureURL(name)),
                .notImage,
                "\(name) 应按内容回落文本路径"
            )
        }
    }

    func testPixelLimitIsInclusive() {
        XCTAssertEqual(ImageOpenPolicy.evaluate(fixtureURL("at-limit.png")), .displayable)
        XCTAssertEqual(ImageOpenPolicy.evaluate(fixtureURL("over-limit.png")), .exceedsPixelLimit)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ImageOpenPolicy/\(name)")
    }
}
