import AppKit
import CodeEditLanguages
import MarkdownUI
import SwiftUI

/// 「切换预览」菜单命令的投递通道：菜单在 App 层，预览开关是 ContentView 的
/// 视图层状态，菜单命令经通知转达，状态仍只有 ContentView 一个 owner。
extension Notification.Name {
    static let toggleMarkdownPreview = Notification.Name("FolbiToggleMarkdownPreview")
}

/// 「是否可预览」判定谓词（spec #10 §1）：复用编辑器语言检测，认 6 个 Markdown
/// 扩展名（md/mkd/mkdn/mdwn/mdown/markdown，小写不敏感），无扩展名文件不启用。
/// 工具栏按钮与 View 菜单「切换预览」共用此判定决定显隐。
enum MarkdownPreviewability {
    static func isPreviewable(documentURL: URL?) -> Bool {
        guard let documentURL else { return false }
        return CodeLanguage.detectLanguageFrom(url: documentURL) == .markdown
    }
}

/// Markdown 预览：编辑缓冲区（含未保存修改）的只读渲染投影，所见即所得。
/// 每次进入预览时对全文渲染一次；预览期间不随编辑刷新，仅外部修改触发的
/// 缓冲区重载会重新渲染。大文档全量渲染慢是已知临时限制，懒渲染归 #15。
struct MarkdownPreviewView: View {
    /// 内容源 = 编辑缓冲区文本。
    let text: String
    /// 页面背景：取编辑器主题背景，编辑/预览切换时底色不跳变。
    let background: Color

    @State private var renderedContent: MarkdownContent?

    var body: some View {
        ScrollView {
            if let renderedContent {
                // 固定 .gitHub 渲染主题；BackgroundColor(nil) 清掉它自带的页面底色
                // （亮色白/暗色 #18191D），页面背景统一由编辑器主题背景给出。
                Markdown(renderedContent)
                    .markdownTheme(.gitHub)
                    .markdownTextStyle {
                        BackgroundColor(nil)
                    }
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(background)
        .onAppear(perform: render)
        .onChange(of: text) { _ in render() }
    }

    private func render() {
        renderedContent = MarkdownContent(text)
    }
}
