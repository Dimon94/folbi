import XCTest

/// 编辑器行宽策略（issue #48）：超长行必须软换行，不得横向溢出 UI 边界。
///
/// 本测试断言本仓库唯一的换行策略坐标（EditorPane 的 wrapLines 配置）恒为 true。
/// 无换行时 CodeEditTextView 会把 text view 扩到最长行宽（TextLayoutManager
/// maxContentWidth 注释：wrapLines=false 时取 greatestFiniteMagnitude），内容
/// 超出窗口右边界。
///
/// 测试形态说明（诚实声明）：SourceEditorConfiguration.Appearance.wrapLines 无
/// public 反射 seam，无法用类型构造断言；故用源码坐标断言，防该坐标回退。
final class EditorLineWrapPolicyTests: XCTestCase {
    func testEditorWrapsLongLinesToFitUIWidth() throws {
        let contentViewPath = repositoryRoot()
            .appendingPathComponent("Folbi/ContentView.swift")
        let source = try String(contentsOf: contentViewPath, encoding: .utf8)
        XCTAssertTrue(
            source.contains("wrapLines: true"),
            "编辑器必须软换行长行（issue #48）；请保持 EditorPane 的 wrapLines: true"
        )
        XCTAssertFalse(
            source.contains("wrapLines: false"),
            "禁止禁用行软换行（issue #48）：长行会横向溢出 UI 边界"
        )
    }

    private func repositoryRoot() -> URL {
        // #filePath 指向 FolbiTests/EditorLineWrapPolicyTests.swift，仓库根为其上两级。
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
