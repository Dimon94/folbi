import XCTest
@testable import Folbi

@MainActor
final class WorkspaceModelImageRoutingTests: XCTestCase {
    func testSelectingImageSetsCurrentImageAndClearsDocument() {
        let model = WorkspaceModel()
        XCTAssertTrue(model.openFile(at: fixtureURL("png-no-extension")))
        XCTAssertEqual(model.currentImageURL, fixtureURL("png-no-extension").standardizedFileURL)
        XCTAssertNil(model.documentURL)
    }

    func testOverLimitImageStillRoutesToImageNotDocument() {
        // 超限是可显示图片选中态，占位由面板承担；不落文本路径。
        let model = WorkspaceModel()
        XCTAssertTrue(model.openFile(at: fixtureURL("over-limit.png")))
        XCTAssertEqual(model.currentImageURL, fixtureURL("over-limit.png").standardizedFileURL)
        XCTAssertNil(model.documentURL)
    }

    func testSelectingTextSetsDocumentAndClearsImage() {
        let model = WorkspaceModel()
        XCTAssertTrue(model.openFile(at: fixtureURL("png-no-extension")))
        XCTAssertTrue(model.openFile(at: fixtureURL("notes.webp")))
        XCTAssertEqual(model.documentURL, fixtureURL("notes.webp").standardizedFileURL)
        XCTAssertNil(model.currentImageURL)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ImageOpenPolicy/\(name)")
    }
}
