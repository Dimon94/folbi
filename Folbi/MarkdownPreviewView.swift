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
/// 分块懒渲染（#15）：进入预览时用 FenceAwareChunker 把全文切成约 8 KiB 的块，
/// 切分放后台线程（#8 实测 5 MiB 约 102 ms）；每块一个 MarkdownUI 视图入
/// LazyVStack，首帧只构建可视区块，各块的解析与视图构建随滚动惰性执行，
/// 首帧与文档大小解耦（#8 实测恒为约 0.17–0.27 s）。
/// 渲染时机不变：进入时渲染一次，之后不随事件重渲染，仅外部修改触发的
/// 缓冲区重载会重新渲染。
///
/// 已接受 trade-off（spec #10 用户裁决，属预期行为不修）：滚动逐块构建
/// （每个 8 KiB 混合块约 250 ms 主线程占用，快速滚动可能顿挫）；文本选择
/// 以块为单位、跨块选择断裂；块缝处段间距与全量渲染有细微差异；松散列表
/// 可能在空行处分为两个列表（有序列表编号由 cmark 按块首数字起始，保真）。
///
/// 图片（#16）：imageBaseURL = 当前文档 URL，相对路径按文档所在目录解析；
/// 加载走 PreviewImageProvider——本地限根文件夹边界内（fail closed 占位），
/// 远程 http(s) 由 MarkdownUI 默认网络加载；相对文件链接不做 app 内跳转（死点击已知）。
struct MarkdownPreviewView: View {
    private struct RenderChunk: Identifiable {
        let id: UUID
        let text: String
    }

    /// 内容源 = 编辑缓冲区文本。
    let text: String
    /// 页面背景：取编辑器主题背景，编辑/预览切换时底色不跳变。
    let background: Color
    /// 图片解析基准（#16）：相对路径以其所在目录为基准（GitHub 惯例）。
    let documentURL: URL?
    /// 图片加载边界（#16）：本地图片只加载根文件夹内的文件。
    let rootURL: URL?

    @State private var chunks: [RenderChunk]?
    /// 渲染序号：切分在后台线程，外部修改连发时晚到的旧结果不得覆盖新结果。
    /// 读写在主线程，经 @State 存储，跨任务捕获比较的是最新值。
    @State private var renderSequence = 0

    /// ContentView 调用点不传 documentURL/rootURL（本 ticket 不改 ContentView）：
    /// 缺省快照工作区模型当前状态。文档或根文件夹一切换即退出预览、本视图销毁
    /// 重建，存续期间两值不变，快照安全；测试可显式传参。
    @MainActor
    init(text: String, background: Color, documentURL: URL? = nil, rootURL: URL? = nil) {
        self.text = text
        self.background = background
        let model = WorkspaceModel.shared
        self.documentURL = documentURL ?? model.documentURL
        self.rootURL = rootURL ?? model.rootNode?.url
    }

    var body: some View {
        ScrollView {
            if let chunks {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks) { chunk in
                        // 固定 .gitHub 渲染主题；BackgroundColor(nil) 清掉它自带的页面底色
                        // （亮色白/暗色 #18191D），页面背景统一由编辑器主题背景给出。
                        Markdown(chunk.text, imageBaseURL: documentURL)
                            .markdownTheme(.gitHub)
                            .markdownImageProvider(PreviewImageProvider(documentURL: documentURL, rootURL: rootURL))
                            .markdownTextStyle {
                                BackgroundColor(nil)
                            }
                            .textSelection(.enabled)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical)
            }
        }
        .background(background)
        .onAppear(perform: startRender)
        .onChange(of: text) { _ in startRender() }
    }

    /// 启动一次渲染流程：全文切分放后台线程，块结果回主线程一次性换上；
    /// 块的 Markdown 解析在各块视图首次构建时懒执行（Markdown(String) init 内解析）。
    /// 被取代的旧任务不取消（单次切分 ≤ 约 102 ms、成本低），跑完即被序号守卫丢弃。
    private func startRender() {
        renderSequence += 1
        let sequence = renderSequence
        let source = text
        Task.detached(priority: .userInitiated) {
            let result = FenceAwareChunker.split(source)
            await MainActor.run {
                guard sequence == renderSequence else { return }
                chunks = result.map { RenderChunk(id: UUID(), text: $0) }
            }
        }
    }
}
